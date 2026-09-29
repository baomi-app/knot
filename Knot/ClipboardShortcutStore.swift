import Carbon
import Combine
import Foundation

struct ClipboardShortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
}

@MainActor
final class ClipboardShortcutStore: ObservableObject {
    static let shared = ClipboardShortcutStore()

    @Published private(set) var shortcut: ClipboardShortcut
    private let defaults: UserDefaults
    private let defaultsKey = "clipboardShortcut"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(ClipboardShortcut.self, from: data),
           ShortcutValidation.isValid(keyCode: saved.keyCode, modifiers: saved.modifiers) {
            shortcut = saved
        } else {
            shortcut = Self.defaultShortcut
        }
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        guard ShortcutValidation.isValid(keyCode: keyCode, modifiers: modifiers) else { return }
        shortcut = ClipboardShortcut(keyCode: keyCode, modifiers: modifiers)
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

    static let defaultShortcut = ClipboardShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )
}
