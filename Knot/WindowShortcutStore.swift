import Carbon
import Combine
import Foundation

struct WindowShortcut: Codable, Hashable, Sendable {
    let action: WindowAction
    var keyCode: UInt32
    var modifiers: UInt32
}

@MainActor
final class WindowShortcutStore: ObservableObject {
    static let shared = WindowShortcutStore()

    @Published private(set) var shortcuts: [WindowShortcut]
    private let defaultsKey = "windowShortcuts"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([WindowShortcut].self, from: data),
           Set(saved.map(\.action)) == Set(WindowAction.allCases) {
            shortcuts = saved
        } else {
            shortcuts = Self.defaultShortcuts
        }
    }

    func shortcut(for action: WindowAction) -> WindowShortcut {
        shortcuts.first(where: { $0.action == action })
            ?? Self.defaultShortcuts.first(where: { $0.action == action })!
    }

    func update(action: WindowAction, keyCode: UInt32, modifiers: UInt32) {
        guard let targetIndex = shortcuts.firstIndex(where: { $0.action == action }) else { return }
        let previousKeyCode = shortcuts[targetIndex].keyCode
        let previousModifiers = shortcuts[targetIndex].modifiers

        if let conflictIndex = shortcuts.firstIndex(where: {
            $0.action != action && $0.keyCode == keyCode && $0.modifiers == modifiers
        }) {
            shortcuts[conflictIndex].keyCode = previousKeyCode
            shortcuts[conflictIndex].modifiers = previousModifiers
        }

        shortcuts[targetIndex].keyCode = keyCode
        shortcuts[targetIndex].modifiers = modifiers
        save()
    }

    func reset() {
        shortcuts = Self.defaultShortcuts
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static let defaultModifiers = UInt32(controlKey | optionKey)
    private static let defaultShortcuts: [WindowShortcut] = [
        WindowShortcut(action: .leftHalf, keyCode: UInt32(kVK_LeftArrow), modifiers: defaultModifiers),
        WindowShortcut(action: .rightHalf, keyCode: UInt32(kVK_RightArrow), modifiers: defaultModifiers),
        WindowShortcut(action: .topHalf, keyCode: UInt32(kVK_UpArrow), modifiers: defaultModifiers),
        WindowShortcut(action: .bottomHalf, keyCode: UInt32(kVK_DownArrow), modifiers: defaultModifiers),
        WindowShortcut(action: .maximize, keyCode: UInt32(kVK_Return), modifiers: defaultModifiers),
        WindowShortcut(action: .center, keyCode: UInt32(kVK_ANSI_C), modifiers: defaultModifiers)
    ]
}
