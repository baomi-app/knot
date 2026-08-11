import Foundation

enum FileSearch {
    static func search(query: String) async -> [SearchItem] {
        await Task.detached(priority: .utility) {
            searchSynchronously(query: query)
        }.value
    }

    private static nonisolated func searchSynchronously(query: String) -> [SearchItem] {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
        let metadataQuery = "kMDItemFSName == '*\(escaped)*'cd"

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "-onlyin",
            FileManager.default.homeDirectoryForCurrentUser.path,
            metadataQuery
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return output
                .split(separator: "\n")
                .prefix(16)
                .map(String.init)
                .map { path in
                    let url = URL(fileURLWithPath: path)
                    return SearchItem(
                        id: "file:\(path)",
                        title: url.lastPathComponent,
                        subtitle: url.deletingLastPathComponent().path,
                        section: .files,
                        symbol: "doc",
                        iconURL: url,
                        action: .openURL(url)
                    )
                }
        } catch {
            return []
        }
    }
}

