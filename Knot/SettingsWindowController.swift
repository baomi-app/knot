import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Knot Settings"
        window.identifier = NSUserInterfaceItemIdentifier("app.baomi.knot.settings")
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentView = NSHostingView(rootView: KnotSettingsView())
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
