import AppKit
import SwiftUI

private final class CommandPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onAcceptSuggestion: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let shortcutModifiers = event.modifierFlags.intersection([
            .command, .option, .control, .shift
        ])
        if event.charactersIgnoringModifiers == ",", shortcutModifiers == .command {
            onShowSettings?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class CommandPanelController: NSObject, NSWindowDelegate {
    private let model: SearchModel
    private let panel: CommandPanel
    private var keyEventMonitor: Any?

    init(model: SearchModel, onShowSettings: @escaping () -> Void) {
        self.model = model
        panel = CommandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 486),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.onShowSettings = { [weak self] in
            self?.close()
            onShowSettings()
        }
        panel.onAcceptSuggestion = { [weak model] in
            model?.acceptSelectedSuggestion() ?? false
        }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            let shortcutModifiers = event.modifierFlags.intersection([
                .command, .option, .control, .shift
            ])
            guard event.window === panel,
                  event.keyCode == 48,
                  shortcutModifiers.isEmpty,
                  panel?.onAcceptSuggestion?() == true else {
                return event
            }
            return nil
        }
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: SearchView(model: model))
        model.onRequestClose = { [weak self] in
            self?.close()
        }
    }

    func toggle() {
        if panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func showClipboard() {
        // Read while the source application is still frontmost. Once Knot's
        // panel activates, source detection would otherwise mistake this copy
        // for content produced by Knot itself and exclude it.
        ClipboardMonitor.shared.pollNow()
        if panel.isVisible {
            model.prepare(mode: .clipboard)
            panel.makeKeyAndOrderFront(nil)
        } else {
            show(mode: .clipboard)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func show(mode: SearchMode = .root) {
        model.capturePasteTarget(NSWorkspace.shared.frontmostApplication)
        WindowManager.captureTarget()
        model.prepare(mode: mode)
        positionPanel()
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel.orderOut(nil)
        model.prepare(mode: .root)
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 96
        )
        panel.setFrameOrigin(origin)
    }
}
