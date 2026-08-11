import Carbon
import Combine
import Foundation

struct CaptureShortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
}

@MainActor
final class CaptureShortcutStore: ObservableObject {
    static let shared = CaptureShortcutStore()

    @Published private(set) var shortcut: CaptureShortcut
    private let defaultsKey = "captureShortcut"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(CaptureShortcut.self, from: data),
           saved.modifiers != 0 {
            shortcut = saved
        } else {
            shortcut = Self.defaultShortcut
        }
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        guard modifiers != 0 else { return }
        shortcut = CaptureShortcut(keyCode: keyCode, modifiers: modifiers)
        save()
    }

    func reset() {
        shortcut = Self.defaultShortcut
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static let defaultShortcut = CaptureShortcut(
        keyCode: UInt32(kVK_ANSI_X),
        modifiers: UInt32(cmdKey | shiftKey)
    )
}
