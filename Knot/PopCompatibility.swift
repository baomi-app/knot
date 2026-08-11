import AppKit
import SwiftUI

// Compatibility surface for the screenshot implementation shared with Pop.
// Pop is another baomi-app project and intentionally supplies Knot Capture's core flow.
enum Brand {
    static let cornYellow = Color(red: 1.0, green: 0.823, blue: 0.290)
    static let leafGreen = Color(red: 0.30, green: 0.62, blue: 0.35)
    static let charcoal = Color(red: 0.18, green: 0.16, blue: 0.14)

    enum Copy {
        static let saved = "截图已复制并保存"
    }
}

@MainActor
final class HotkeyStore {
    static let shared = HotkeyStore()
    private init() {}

    var modernEngine: Bool { true }
    var saveEnabled: Bool { CaptureSettingsStore.shared.saveEnabled }
    var toastEnabled: Bool { false }
    var savePath: URL? { CaptureHistoryStore.shared.ensureCaptureDirectory() }

    func withSaveDirectoryAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        try body(CaptureHistoryStore.shared.ensureCaptureDirectory())
    }
}

@MainActor
enum Toast {
    static func show(_ message: String) {
        NSLog("[Knot Capture] %@", message)
    }
}
