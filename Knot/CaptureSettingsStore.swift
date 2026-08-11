import Combine
import Foundation

enum CaptureFileFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg

    var id: String { rawValue }
    var displayName: String { self == .png ? "PNG" : "JPEG" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var screenCaptureType: String { self == .png ? "png" : "jpg" }
}

@MainActor
final class CaptureSettingsStore: ObservableObject {
    static let shared = CaptureSettingsStore()

    @Published private(set) var format: CaptureFileFormat
    @Published private(set) var fileNamePrefix: String
    @Published private(set) var saveEnabled: Bool
    @Published private(set) var copyAfterSave: Bool
    @Published private(set) var openAnnotationEditor: Bool
    @Published private(set) var customDirectoryPath: String?

    private enum Key {
        static let format = "captureFormat"
        static let prefix = "captureFileNamePrefix"
        static let saveEnabled = "captureSaveEnabled"
        static let copyAfterSave = "captureCopyAfterSave"
        static let annotation = "captureOpenAnnotationEditor"
        static let directory = "captureDirectoryPath"
    }

    private init() {
        format = UserDefaults.standard.string(forKey: Key.format)
            .flatMap(CaptureFileFormat.init(rawValue:)) ?? .png
        fileNamePrefix = UserDefaults.standard.string(forKey: Key.prefix) ?? "Knot"
        saveEnabled = UserDefaults.standard.object(forKey: Key.saveEnabled) as? Bool ?? false
        copyAfterSave = UserDefaults.standard.bool(forKey: Key.copyAfterSave)
        openAnnotationEditor = UserDefaults.standard.bool(forKey: Key.annotation)
        customDirectoryPath = UserDefaults.standard.string(forKey: Key.directory)
    }

    func setFormat(_ value: CaptureFileFormat) {
        format = value
        UserDefaults.standard.set(value.rawValue, forKey: Key.format)
    }

    func setFileNamePrefix(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        fileNamePrefix = clean.isEmpty ? "Knot" : String(clean.prefix(40))
        UserDefaults.standard.set(fileNamePrefix, forKey: Key.prefix)
    }

    func setSaveEnabled(_ value: Bool) {
        saveEnabled = value
        UserDefaults.standard.set(value, forKey: Key.saveEnabled)
    }

    func setCopyAfterSave(_ value: Bool) {
        copyAfterSave = value
        UserDefaults.standard.set(value, forKey: Key.copyAfterSave)
    }

    func setOpenAnnotationEditor(_ value: Bool) {
        openAnnotationEditor = value
        UserDefaults.standard.set(value, forKey: Key.annotation)
    }

    func setDirectory(_ url: URL?) {
        customDirectoryPath = url?.path
        UserDefaults.standard.set(customDirectoryPath, forKey: Key.directory)
    }
}
