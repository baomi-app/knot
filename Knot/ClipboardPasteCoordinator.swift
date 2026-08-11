import AppKit
import CoreGraphics
import Foundation

@MainActor
enum ClipboardPasteCoordinator {
    static func paste(to application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        guard WindowManager.isTrusted(prompt: true) else { return false }

        application.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }
}
