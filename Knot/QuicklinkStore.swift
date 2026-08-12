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
    private let fileManager = FileManager.default

    private init() {
        let loadedLinks = load()
        links = loadedLinks.filter { !Self.isLegacyChatGPTDefault($0) }
        if links.isEmpty {
            links = Self.defaultLinks
        }
        if links != loadedLinks {
            save()
        }
    }

    func add() -> Quicklink {
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
        links.append(link)
        save()
        return link
    }

    func update(id: UUID, title: String, urlTemplate: String, keyword: String) {
        guard isValid(
            title: title,
            urlTemplate: urlTemplate,
            keyword: keyword,
            excluding: id
        ) else { return }
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        links[index] = Quicklink(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            urlTemplate: urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        )
        links.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        save()
    }

    func remove(id: UUID) {
        links.removeAll { $0.id == id }
        save()
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

        links.append(contentsOf: importedLinks)
        links.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if imported > 0 { save() }
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

    private func load() -> [Quicklink] {
        guard let data = try? Data(contentsOf: storageURL),
              let links = try? JSONDecoder().decode([Quicklink].self, from: data) else {
            return []
        }
        return links
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(links) else { return }
        try? fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: storageURL, options: .atomic)
    }

    private var storageURL: URL {
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
        Quicklink(title: "GitHub", urlTemplate: "https://github.com", keyword: "gh")
    ]

    private static func isLegacyChatGPTDefault(_ link: Quicklink) -> Bool {
        link.title == "ChatGPT"
            && link.urlTemplate == "https://chatgpt.com"
            && link.keyword == "chat"
    }
}
