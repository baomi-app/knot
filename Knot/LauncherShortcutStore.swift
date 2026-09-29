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
    private let defaults: UserDefaults
    private let defaultsKey = "launcherShortcut"

    init(
        defaults: UserDefaults = .standard,
        isAvailable: (UInt32, UInt32) -> Bool = GlobalHotKeyAvailability.canRegister
    ) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(LauncherShortcut.self, from: data),
           ShortcutValidation.isValid(keyCode: saved.keyCode, modifiers: saved.modifiers),
           isAvailable(saved.keyCode, saved.modifiers) {
            shortcut = saved
        } else {
            shortcut = Self.defaultShortcut
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        guard ShortcutValidation.isValid(keyCode: keyCode, modifiers: modifiers) else { return }
        shortcut = LauncherShortcut(keyCode: keyCode, modifiers: modifiers)
        save()
    }

    func reset() {
        shortcut = Self.defaultShortcut
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static let defaultShortcut = LauncherShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )
}
