import AppKit
import Foundation

enum AppScanner {
    static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
    }

    static func scan(roots: [URL] = defaultRoots) async -> [ScannedApplication] {
        await Task.detached(priority: .utility) { scanSynchronously(roots: roots) }.value
    }

    private static nonisolated func scanSynchronously(roots: [URL]) -> [ScannedApplication] {
        let keys: Set<URLResourceKey> = [.isApplicationKey, .localizedNameKey]
        var seen = Set<String>()
        var items: [ScannedApplication] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                let name = (try? url.resourceValues(forKeys: keys).localizedName)
                    ?? url.deletingPathExtension().lastPathComponent
                let normalized = name.localizedLowercase
                guard seen.insert(normalized).inserted else { continue }
                let aliases = applicationAliases(name: name, url: url, metadata: metadata(at: url))
                items.append(
                    ScannedApplication(
                        title: name,
                        url: url,
                        aliases: aliases
                    )
                )
            }
        }

        return items.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static nonisolated func applicationAliases(
        name: String,
        url: URL,
        metadata: [String: Any]
    ) -> [String] {
        var aliases = Set<String>()
        let fileName = url.deletingPathExtension().lastPathComponent
        aliases.insert(fileName.localizedLowercase)

        if let bundleIdentifier = (metadata["CFBundleIdentifier"] as? String)?.localizedLowercase {
            aliases.insert(bundleIdentifier)
            for component in bundleIdentifier.split(separator: ".") {
                let value = String(component)
                if value.count >= 2, !["app", "com", "mac", "org"].contains(value) {
                    aliases.insert(value)
                }
            }
        }

        let metadataNames = [
            name,
            metadata["CFBundleDisplayName"] as? String,
            metadata["CFBundleName"] as? String
        ].compactMap { $0 }

        for metadataName in metadataNames {
            aliases.formUnion(transliterationAliases(for: metadataName))
        }
        aliases.remove(name.localizedLowercase)
        return aliases.sorted()
    }

    private static nonisolated func metadata(at url: URL) -> [String: Any] {
        // Bundle caches Info.plist for the lifetime of the process. A scan can
        // see a newly created .app before its metadata has finished copying,
        // so refresh directly from disk on each scan instead of caching misses.
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let metadata = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any] else { return [:] }
        return metadata
    }

    private static nonisolated func transliterationAliases(for value: String) -> Set<String> {
        guard let latin = value.applyingTransform(.toLatin, reverse: false) else { return [] }
        let plain = (latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin)
            .localizedLowercase
        let compact = plain.filter { $0.isLetter || $0.isNumber }
        return [plain, compact]
    }
}
