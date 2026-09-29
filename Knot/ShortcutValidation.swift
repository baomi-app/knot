import Carbon

enum ShortcutValidation {
    // Virtual key codes are not ordered by function-key number.
    private static let functionKeyCodes = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
        kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ].map(UInt32.init)

    static func functionKeyNumber(for keyCode: UInt32) -> Int? {
        functionKeyCodes.firstIndex(of: keyCode).map { $0 + 1 }
    }

    static func isValid(keyCode: UInt32, modifiers: UInt32) -> Bool {
        modifiers != 0 || functionKeyNumber(for: keyCode) != nil
    }
}
