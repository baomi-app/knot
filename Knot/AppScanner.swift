import AppKit
import Foundation

enum AppScanner {
    static func scan() async -> [SearchItem] {
        await Task.detached(priority: .utility) { scanSynchronously() }.value
    }

    private static nonisolated func scanSynchronously() -> [SearchItem] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        let keys: Set<URLResourceKey> = [.isApplicationKey, .localizedNameKey]
        var seen = Set<String>()
        var items: [SearchItem] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                let name = (try? url.resourceValues(forKeys: keys).localizedName)
                    ?? url.deletingPathExtension().lastPathComponent
                let normalized = name.localizedLowercase
                guard seen.insert(normalized).inserted else { continue }
                let bundle = Bundle(url: url)
                let aliases = applicationAliases(name: name, url: url, bundle: bundle)
                items.append(
                    SearchItem(
                        id: "app:\(url.path)",
                        title: name,
                        subtitle: url.deletingLastPathComponent().path,
                        section: .applications,
                        symbol: "app",
                        aliases: aliases,
                        iconURL: url,
                        action: .openApplication(url)
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
        bundle: Bundle?
    ) -> [String] {
        var aliases = Set<String>()
        let fileName = url.deletingPathExtension().lastPathComponent
        aliases.insert(fileName.localizedLowercase)

        if let bundleIdentifier = bundle?.bundleIdentifier?.localizedLowercase {
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
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        ].compactMap { $0 }

        for metadataName in metadataNames {
            aliases.formUnion(transliterationAliases(for: metadataName))
        }
        aliases.remove(name.localizedLowercase)
        return aliases.sorted()
    }

    private static nonisolated func transliterationAliases(for value: String) -> Set<String> {
        guard let latin = value.applyingTransform(.toLatin, reverse: false) else { return [] }
        let plain = (latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin)
            .localizedLowercase
        let compact = plain.filter { $0.isLetter || $0.isNumber }
        return [plain, compact]
    }
}
