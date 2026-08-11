import AppKit
import Carbon
import SwiftUI

enum ShortcutDisplayFormatter {
    static func label(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierLabel(modifiers) + keyLabel(keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func modifierLabel(_ modifiers: UInt32) -> String {
        var label = ""
        if modifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        return label
    }

    private static func keyLabel(_ keyCode: UInt32) -> String {
        let labels: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "Esc",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Home): "↖",
            UInt32(kVK_End): "↘",
            UInt32(kVK_PageUp): "⇞",
            UInt32(kVK_PageDown): "⇟",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9"
        ]
        if let label = labels[keyCode] { return label }

        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"),
            (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"),
            (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"),
            (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"),
            (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"), (kVK_ANSI_U, "U"),
            (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z")
        ]
        return letters.first(where: { UInt32($0.0) == keyCode })?.1 ?? "Key \(keyCode)"
    }
}

enum GlobalHotKeyAvailability {
    static func canRegister(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // Spotlight keeps priority over Command-Space even though Carbon may
        // report a successful registration. Treat it as unavailable so the UI
        // does not accept a shortcut that can never reach Knot.
        if keyCode == UInt32(kVK_Space),
           modifiers == UInt32(cmdKey),
           isSpotlightShortcutEnabled {
            return false
        }

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: 0x4B544553, id: 1), // KTES
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if let reference {
            UnregisterEventHotKey(reference)
        }
        return status == noErr
    }

    private static var isSpotlightShortcutEnabled: Bool {
        guard let domain = UserDefaults.standard.persistentDomain(
            forName: "com.apple.symbolichotkeys"
        ),
        let shortcuts = domain["AppleSymbolicHotKeys"] as? [String: Any],
        let spotlight = shortcuts["64"] as? [String: Any],
        let enabled = spotlight["enabled"] as? Bool else {
            return true
        }
        return enabled
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let keyCode: UInt32
    let modifiers: UInt32
    let onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.keyCode = keyCode
        view.modifiers = modifiers
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.keyCode = keyCode
        nsView.modifiers = modifiers
        nsView.onRecord = onRecord
    }
}

final class ShortcutRecorderNSView: NSView {
    var keyCode: UInt32 = 0 { didSet { updateLabel() } }
    var modifiers: UInt32 = 0 { didSet { updateLabel() } }
    var onRecord: ((UInt32, UInt32) -> Void)?

    private let textField = NSTextField(labelWithString: "")
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        textField.alignment = .center
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityRole(.button)
        setAccessibilityHelp("Click, then press a keyboard shortcut")
        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 30) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        updateLabel()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }

        let newModifiers = ShortcutDisplayFormatter.carbonModifiers(from: event.modifierFlags)
        guard newModifiers != 0 else {
            NSSound.beep()
            return
        }

        let newKeyCode = UInt32(event.keyCode)
        onRecord?(newKeyCode, newModifiers)
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateLabel()
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()
    }

    private func finishRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
        updateLabel()
        needsDisplay = true
    }

    private func updateLabel() {
        textField.stringValue = isRecording
            ? "Press shortcut…"
            : ShortcutDisplayFormatter.label(keyCode: keyCode, modifiers: modifiers)
        setAccessibilityLabel(textField.stringValue)
    }
}
