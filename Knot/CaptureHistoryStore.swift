import Combine
import Foundation

struct CaptureHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let fileURL: URL
    let capturedAt: Date
    let action: CaptureAction

    init(
        id: UUID = UUID(),
        fileURL: URL,
        capturedAt: Date = Date(),
        action: CaptureAction
    ) {
        self.id = id
        self.fileURL = fileURL
        self.capturedAt = capturedAt
        self.action = action
    }
}

@MainActor
final class CaptureHistoryStore: ObservableObject {
    static let shared = CaptureHistoryStore()

    @Published private(set) var entries: [CaptureHistoryEntry] = []
    private let fileManager = FileManager.default
    private let settings = CaptureSettingsStore.shared

    private init() {
        entries = load().filter { fileManager.fileExists(atPath: $0.fileURL.path) }
        save()
    }

    var captureDirectoryURL: URL {
        if let path = settings.customDirectoryPath, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("Knot Captures", isDirectory: true)
    }

    func makeDestination() -> URL? {
        do {
            try fileManager.createDirectory(
                at: captureDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return captureDirectoryURL
            .appendingPathComponent(
                "\(settings.fileNamePrefix) \(formatter.string(from: Date())).\(settings.format.fileExtension)"
            )
    }

    func ensureCaptureDirectory() -> URL {
        try? fileManager.createDirectory(
            at: captureDirectoryURL,
            withIntermediateDirectories: true
        )
        return captureDirectoryURL
    }

    func record(fileURL: URL, action: CaptureAction) {
        entries.removeAll { $0.fileURL == fileURL }
        entries.insert(CaptureHistoryEntry(fileURL: fileURL, action: action), at: 0)
        entries = Array(entries.prefix(50))
        save()
    }

    func clear() {
        entries.removeAll()
        try? fileManager.removeItem(at: storageURL)
    }

    func removeMissingFiles() {
        let previous = entries
        entries.removeAll { !fileManager.fileExists(atPath: $0.fileURL.path) }
        if entries != previous { save() }
    }

    private func load() -> [CaptureHistoryEntry] {
        guard let data = try? Data(contentsOf: storageURL),
              let entries = try? JSONDecoder().decode([CaptureHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
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
            .appendingPathComponent("capture-history.json")
    }
}
