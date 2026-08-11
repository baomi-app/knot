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
                items.append(
                    SearchItem(
                        id: "app:\(url.path)",
                        title: name,
                        subtitle: url.deletingLastPathComponent().path,
                            section: .applications,
                            symbol: "app",
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
}
