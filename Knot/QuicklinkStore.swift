import Combine
import Foundation

struct QuicklinkTransferDocument: Codable, Sendable {
    let format: String
    let version: Int
    let links: [Quicklink]
}

struct QuicklinkImportResult: Equatable, Sendable {
    let imported: Int
    let skipped: Int

    var message: String {
        if imported == 0 {
            return skipped == 0 ? "No Quicklinks were found" : "No Quicklinks imported. \(skipped) skipped."
        }
        return "Imported \(imported) Quicklinks. \(skipped) skipped."
    }
}

@MainActor
final class QuicklinkStore: ObservableObject {
    static let shared = QuicklinkStore()

    @Published private(set) var links: [Quicklink] = []
    @Published private(set) var persistenceMessage: String?
    private let fileManager: FileManager
    private let storageURL: URL
    private var needsRecoveryCopy = false
    private(set) var recoveryURL: URL?

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL
        // An existing empty configuration is a choice, not a first launch.
        guard fileManager.fileExists(atPath: self.storageURL.path) else {
            save(Self.defaultLinks)
            return
        }
        // Do not overwrite unreadable or malformed data with defaults either.
        guard let loadedLinks = load() else {
            needsRecoveryCopy = true
            persistenceMessage = "Existing Quicklinks could not be read. The original configuration has been preserved."
            NSLog("[Knot Quicklinks] Existing configuration could not be loaded; preserving the original.")
            return
        }
        let migratedLinks = loadedLinks
            .filter { !Self.isLegacyChatGPTDefault($0) }
            .map(Self.migratingLegacyDefault)
        links = loadedLinks
        if migratedLinks != loadedLinks {
            save(migratedLinks)
        }
    }

    func add() -> Quicklink? {
        var candidate = "link"
        var suffix = 2
        while links.contains(where: { $0.keyword == candidate }) {
            candidate = "link\(suffix)"
            suffix += 1
        }
        let link = Quicklink(
            title: "New Quicklink",
            urlTemplate: "https://example.com",
            keyword: candidate
        )
        guard save(links + [link]) else { return nil }
        return link
    }

    @discardableResult
    func update(id: UUID, title: String, urlTemplate: String, keyword: String) -> Bool {
        guard isValid(
            title: title,
            urlTemplate: urlTemplate,
            keyword: keyword,
            excluding: id
        ) else { return false }
        guard let index = links.firstIndex(where: { $0.id == id }) else { return false }
        var updatedLinks = links
        updatedLinks[index] = Quicklink(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            urlTemplate: urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        )
        updatedLinks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return save(updatedLinks)
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        let remaining = links.filter { $0.id != id }
        guard remaining.count != links.count else { return true }
        return save(remaining)
    }

    func exportData() -> Data? {
        let document = QuicklinkTransferDocument(
            format: "knot.quicklinks",
            version: 1,
            links: links
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(document)
    }

    func importData(_ data: Data) -> QuicklinkImportResult? {
        guard let document = try? JSONDecoder().decode(QuicklinkTransferDocument.self, from: data),
              document.format == "knot.quicklinks",
              document.version == 1 else {
            return nil
        }

        var knownIDs = Set(links.map(\.id))
        var knownKeywords = Set(links.map { Self.normalizedKeyword($0.keyword) })
        var importedLinks: [Quicklink] = []
        var imported = 0
        var skipped = 0
        for link in document.links {
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlTemplate = link.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            let keyword = Self.normalizedKeyword(link.keyword)
            guard !knownIDs.contains(link.id),
                  !knownKeywords.contains(keyword),
                  Self.hasValidFields(
                    title: title,
                    urlTemplate: urlTemplate,
                    keyword: keyword
                  ) else {
                skipped += 1
                continue
            }

            importedLinks.append(Quicklink(
                id: link.id,
                title: title,
                urlTemplate: urlTemplate,
                keyword: keyword
            ))
            knownIDs.insert(link.id)
            knownKeywords.insert(keyword)
            imported += 1
        }

        if imported > 0 {
            let merged = (links + importedLinks).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            guard save(merged) else { return nil }
        }
        return QuicklinkImportResult(imported: imported, skipped: skipped)
    }

    func isValid(
        title: String,
        urlTemplate: String,
        keyword: String,
        excluding id: UUID? = nil
    ) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURLTemplate = urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKeyword = Self.normalizedKeyword(keyword)
        guard Self.hasValidFields(
            title: cleanTitle,
            urlTemplate: cleanURLTemplate,
            keyword: cleanKeyword
        ), !links.contains(where: {
            $0.id != id && Self.normalizedKeyword($0.keyword) == cleanKeyword
        }) else {
            return false
        }
        return true
    }

    private static func normalizedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private static func hasValidFields(
        title: String,
        urlTemplate: String,
        keyword: String
    ) -> Bool {
        guard !title.isEmpty,
              !keyword.isEmpty,
              !keyword.contains(where: { $0.isWhitespace }),
              let url = URL(string: urlTemplate.replacingOccurrences(of: "{query}", with: "test")),
              ["http", "https"].contains(url.scheme?.localizedLowercase ?? ""),
              url.host != nil else {
            return false
        }
        return true
    }

    private func load() -> [Quicklink]? {
        guard let data = try? Data(contentsOf: storageURL),
              let links = try? JSONDecoder().decode([Quicklink].self, from: data) else {
            return nil
        }
        return links
    }

    @discardableResult
    private func save(_ proposedLinks: [Quicklink]) -> Bool {
        do {
            let data = try JSONEncoder().encode(proposedLinks)
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if needsRecoveryCopy {
                let destination = storageURL.deletingLastPathComponent()
                    .appendingPathComponent("quicklinks-recovery-\(UUID().uuidString).json")
                // A failed backup must stop the write. Keep this flag set so
                // a later retry cannot silently skip protecting the original.
                try fileManager.copyItem(at: storageURL, to: destination)
                recoveryURL = destination
                needsRecoveryCopy = false
                NSLog("[Knot Quicklinks] Preserved unreadable configuration as %@", destination.lastPathComponent)
            }
            try data.write(to: storageURL, options: .atomic)
            links = proposedLinks
            persistenceMessage = recoveryURL.map {
                "The previous Quicklinks configuration was preserved at \($0.path)."
            }
            return true
        } catch {
            persistenceMessage = "Quicklinks could not be saved. The existing configuration has not been replaced."
            NSLog("[Knot Quicklinks] Configuration was not saved: %@", String(describing: error))
            return false
        }
    }

    private static var defaultStorageURL: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Knot", isDirectory: true)
            .appendingPathComponent("quicklinks.json")
    }

    private static let defaultLinks: [Quicklink] = [
        Quicklink(
            title: "Search Google",
            urlTemplate: "https://www.google.com/search?q={query}",
            keyword: "g"
        ),
        Quicklink(
            title: "Search GitHub",
            urlTemplate: "https://github.com/search?q={query}",
            keyword: "gh"
        )
    ]

    private static func migratingLegacyDefault(_ link: Quicklink) -> Quicklink {
        guard link.title == "GitHub",
              link.urlTemplate == "https://github.com",
              link.keyword == "gh" else {
            return link
        }
        return Quicklink(
            id: link.id,
            title: "Search GitHub",
            urlTemplate: "https://github.com/search?q={query}",
            keyword: "gh"
        )
    }

    private static func isLegacyChatGPTDefault(_ link: Quicklink) -> Bool {
        link.title == "ChatGPT"
            && link.urlTemplate == "https://chatgpt.com"
            && link.keyword == "chat"
    }
}
