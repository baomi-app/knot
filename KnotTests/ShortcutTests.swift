import AppKit
import Carbon
import XCTest

@MainActor
final class ShortcutTests: XCTestCase {
    private let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
        kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    func testRecorderAcceptsAndLabelsEveryFunctionKeyWithoutModifiers() throws {
        for (index, code) in functionKeys.enumerated() {
            // macOS may mark an F key with .function, but it is not a required
            // Carbon modifier. Both forms must produce the same shortcut.
            for flags: NSEvent.ModifierFlags in [[], .function] {
                let recorder = try makeRecorder()
                var recorded: (UInt32, UInt32)?
                recorder.onRecord = { recorded = ($0, $1) }
                recorder.keyDown(with: try event(code, flags: flags))

                let result = try XCTUnwrap(recorded, "F\(index + 1)")
                XCTAssertEqual(result.0, UInt32(code))
                XCTAssertEqual(result.1, 0)
                XCTAssertEqual(
                    ShortcutDisplayFormatter.label(keyCode: result.0, modifiers: result.1),
                    "F\(index + 1)"
                )
            }
        }
    }

    func testRecorderPreservesModifiersOnFunctionKeys() throws {
        let recorder = try makeRecorder()
        var recorded: (UInt32, UInt32)?
        recorder.onRecord = { recorded = ($0, $1) }
        recorder.keyDown(with: try event(kVK_F2, flags: [.command, .shift, .function, .capsLock]))

        let result = try XCTUnwrap(recorded)
        XCTAssertEqual(result.0, UInt32(kVK_F2))
        XCTAssertEqual(result.1, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(ShortcutDisplayFormatter.label(keyCode: result.0, modifiers: result.1), "⇧⌘F2")
    }

    func testRecorderStillRejectsBareTypingAndNavigationKeys() throws {
        let recorder = try makeRecorder()
        var recorded = false
        recorder.onRecord = { _, _ in recorded = true }
        for code in [kVK_ANSI_A, kVK_Space, kVK_LeftArrow, kVK_Delete] {
            // .function is also emitted for navigation keys and must not make
            // every key eligible for a shortcut without modifiers.
            recorder.keyDown(with: try event(code, flags: .function))
        }
        XCTAssertFalse(recorded)
    }

    func testEscapeCancelsFunctionKeyRecording() throws {
        let recorder = try makeRecorder()
        recorder.keyCode = UInt32(kVK_F1)
        var recorded = false
        recorder.onRecord = { _, _ in recorded = true }
        recorder.keyDown(with: try event(kVK_Escape))

        XCTAssertFalse(recorded)
        XCTAssertEqual(recorder.accessibilityLabel(), "F1")
    }

    func testLauncherFunctionKeySurvivesSavingAndReloading() throws {
        try withDefaults { defaults in
            let store = LauncherShortcutStore(defaults: defaults, isAvailable: { _, _ in true })
            for code in [kVK_F1, kVK_F2, kVK_F20] {
                store.update(keyCode: UInt32(code), modifiers: 0)
                var checkedKey: UInt32?
                let reloaded = LauncherShortcutStore(defaults: defaults) { key, modifiers in
                    checkedKey = key
                    XCTAssertEqual(modifiers, 0)
                    return true
                }
                XCTAssertEqual(reloaded.shortcut, LauncherShortcut(keyCode: UInt32(code), modifiers: 0))
                XCTAssertEqual(checkedKey, UInt32(code))
            }
        }
    }

    func testUnavailableLauncherFunctionKeyStillFallsBackToDefault() throws {
        try withDefaults { defaults in
            let store = LauncherShortcutStore(defaults: defaults, isAvailable: { _, _ in true })
            store.update(keyCode: UInt32(kVK_F1), modifiers: 0)
            let reloaded = LauncherShortcutStore(defaults: defaults, isAvailable: { _, _ in false })
            XCTAssertEqual(reloaded.shortcut, LauncherShortcutStore.defaultShortcut)
        }
    }

    func testCaptureAndClipboardFunctionKeysSurviveSavingAndReloading() throws {
        try withDefaults { defaults in
            let capture = CaptureShortcutStore(defaults: defaults)
            let clipboard = ClipboardShortcutStore(defaults: defaults)
            for code in [kVK_F1, kVK_F2, kVK_F20] {
                capture.update(keyCode: UInt32(code), modifiers: 0)
                clipboard.update(keyCode: UInt32(code), modifiers: 0)
                XCTAssertEqual(
                    CaptureShortcutStore(defaults: defaults).shortcut,
                    CaptureShortcut(keyCode: UInt32(code), modifiers: 0)
                )
                XCTAssertEqual(
                    ClipboardShortcutStore(defaults: defaults).shortcut,
                    ClipboardShortcut(keyCode: UInt32(code), modifiers: 0)
                )
            }
        }
    }

    func testWindowFunctionKeysCanSwapAndSurviveReloading() throws {
        try withDefaults { defaults in
            let store = WindowShortcutStore(defaults: defaults)
            store.update(action: .leftHalf, keyCode: UInt32(kVK_F1), modifiers: 0)
            store.update(action: .rightHalf, keyCode: UInt32(kVK_F2), modifiers: 0)
            store.update(action: .rightHalf, keyCode: UInt32(kVK_F1), modifiers: 0)

            let reloaded = WindowShortcutStore(defaults: defaults)
            XCTAssertEqual(reloaded.shortcut(for: .leftHalf), .init(action: .leftHalf, keyCode: UInt32(kVK_F2), modifiers: 0))
            XCTAssertEqual(reloaded.shortcut(for: .rightHalf), .init(action: .rightHalf, keyCode: UInt32(kVK_F1), modifiers: 0))
        }
    }

    func testStoresRejectBareLettersWithoutLosingFunctionKeys() throws {
        try withDefaults { defaults in
            let launcher = LauncherShortcutStore(defaults: defaults, isAvailable: { _, _ in true })
            let capture = CaptureShortcutStore(defaults: defaults)
            let clipboard = ClipboardShortcutStore(defaults: defaults)
            let window = WindowShortcutStore(defaults: defaults)
            for code in [kVK_F1, kVK_ANSI_A] {
                launcher.update(keyCode: UInt32(code), modifiers: 0)
                capture.update(keyCode: UInt32(code), modifiers: 0)
                clipboard.update(keyCode: UInt32(code), modifiers: 0)
                window.update(action: .leftHalf, keyCode: UInt32(code), modifiers: 0)
            }
            XCTAssertEqual(launcher.shortcut.keyCode, UInt32(kVK_F1))
            XCTAssertEqual(capture.shortcut.keyCode, UInt32(kVK_F1))
            XCTAssertEqual(clipboard.shortcut.keyCode, UInt32(kVK_F1))
            XCTAssertEqual(window.shortcut(for: .leftHalf).keyCode, UInt32(kVK_F1))
        }
    }

    func testExistingModifiedLetterShortcutStillRecordsAndPersists() throws {
        try withDefaults { defaults in
            let store = CaptureShortcutStore(defaults: defaults)
            let recorder = try makeRecorder()
            recorder.onRecord = { store.update(keyCode: $0, modifiers: $1) }
            recorder.keyDown(with: try event(kVK_ANSI_B, flags: [.command, .option]))
            XCTAssertEqual(
                CaptureShortcutStore(defaults: defaults).shortcut,
                CaptureShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | optionKey))
            )
        }
    }

    private func makeRecorder() throws -> ShortcutRecorderNSView {
        let recorder = ShortcutRecorderNSView(frame: .zero)
        recorder.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )))
        return recorder
    }

    private func event(_ code: Int, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(code)
        ))
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "knot-shortcut-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
