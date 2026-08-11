import Carbon
import Combine
import Foundation

struct LauncherShortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
}

@MainActor
final class LauncherShortcutStore: ObservableObject {
    static let shared = LauncherShortcutStore()

    @Published private(set) var shortcut: LauncherShortcut
    private let defaultsKey = "launcherShortcut"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(LauncherShortcut.self, from: data),
           saved.modifiers != 0,
           GlobalHotKeyAvailability.canRegister(
               keyCode: saved.keyCode,
               modifiers: saved.modifiers
           ) {
            shortcut = saved
        } else {
            shortcut = Self.defaultShortcut
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        guard modifiers != 0 else { return }
        shortcut = LauncherShortcut(keyCode: keyCode, modifiers: modifiers)
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

    static let defaultShortcut = LauncherShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )
}
