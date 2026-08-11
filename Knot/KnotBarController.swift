import AppKit
import Combine
import Foundation

/// Knot's adaptation of Hidden Bar's MIT-licensed status-item length mechanism.
/// Hidden icons are placed left of `separatorItem`; collapsing inflates that item
/// and pushes the hidden group off-screen. No overlay or private API is involved.
@MainActor
final class KnotBarController: ObservableObject {
    static let shared = KnotBarController()

    @Published private(set) var isCollapsed = false

    private let settings = KnotBarSettingsStore.shared
    private let toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separatorItem = NSStatusBar.system.statusItem(withLength: 20)
    private let expandedSeparatorLength: CGFloat = 20
    private var collapsedSeparatorLength: CGFloat = 2_000
    private var autoHideTimer: Timer?
    private var hoverDwellTimer: Timer?
    private var hoverMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var isToggling = false

    private init() {
        configureStatusItems()
    }

    func start() {
        guard !started else { return }
        started = true
        updateCollapsedLength()

        Publishers.CombineLatest4(
            settings.$isEnabled,
            settings.$isAutoHide,
            settings.$autoHideDelay,
            settings.$revealOnHover
        )
        .sink { [weak self] _ in self?.settingsChanged() }
        .store(in: &cancellables)

        settings.$separatorsHidden
            .sink { [weak self] hidden in self?.separatorItem.button?.isHidden = hidden }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenParametersChanged() }
            .store(in: &cancellables)

        toggleItem.isVisible = true
        separatorItem.isVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard self?.settings.isEnabled == true else { return }
            self?.collapse()
        }
    }

    func stop() {
        autoHideTimer?.invalidate()
        hoverDwellTimer?.invalidate()
        removeHoverMonitor()
        cancellables.removeAll()
        started = false
    }

    func toggle() {
        guard settings.isEnabled else {
            settings.setEnabled(true)
            collapse()
            return
        }
        guard !isToggling else { return }
        isToggling = true
        isCollapsed ? reveal() : collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggling = false
        }
    }

    func collapse() {
        guard settings.isEnabled, !isCollapsed else { return }
        updateCollapsedLength()
        separatorItem.length = collapsedSeparatorLength
        isCollapsed = true
        autoHideTimer?.invalidate()
        updateButton()
    }

    func reveal() {
        guard isCollapsed else { return }
        separatorItem.length = expandedSeparatorLength
        isCollapsed = false
        updateButton()
        scheduleAutoHide()
    }

    private func configureStatusItems() {
        toggleItem.autosaveName = "KnotBarExpandCollapse"
        separatorItem.autosaveName = "KnotBarSeparator"

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(togglePressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Knot Bar — click to hide or reveal menu bar items"
        }
        if let button = separatorItem.button {
            button.image = separatorImage()
            button.image?.isTemplate = true
            button.toolTip = "Items to the left belong to Knot Bar's hidden section"
        }
        separatorItem.menu = contextMenu()
        updateButton()
    }

    @objc private func togglePressed(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            separatorItem.menu?.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                in: sender
            )
        } else {
            toggle()
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Hide / Reveal Items", action: #selector(toggleMenuAction), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let disable = NSMenuItem(title: "Disable Knot Bar", action: #selector(disableMenuAction), keyEquivalent: "")
        disable.target = self
        menu.addItem(disable)
        return menu
    }

    @objc private func toggleMenuAction() { toggle() }
    @objc private func disableMenuAction() { settings.setEnabled(false) }

    private func settingsChanged() {
        if settings.isEnabled {
            updateButton()
            configureHoverMonitor()
            if !isCollapsed { scheduleAutoHide() }
        } else {
            separatorItem.length = expandedSeparatorLength
            isCollapsed = false
            autoHideTimer?.invalidate()
            removeHoverMonitor()
            updateButton()
        }
    }

    private func screenParametersChanged() {
        let wasCollapsed = isCollapsed
        updateCollapsedLength()
        if wasCollapsed { separatorItem.length = collapsedSeparatorLength }
    }

    private func updateCollapsedLength() {
        let widestScreen = NSScreen.screens.map { $0.frame.width }.max() ?? 1_728
        collapsedSeparatorLength = max(500, min(widestScreen * 2, 10_000))
    }

    private func updateButton() {
        let symbol = isCollapsed ? "chevron.right" : "chevron.left"
        toggleItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Knot Bar")
        toggleItem.button?.appearsDisabled = !settings.isEnabled
    }

    private func separatorImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 5, height: 18), flipped: false) { rect in
            NSColor.labelColor.setFill()
            NSRect(x: rect.midX - 0.5, y: 2, width: 1, height: rect.height - 4).fill()
            return true
        }
        return image
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        guard settings.isEnabled, settings.isAutoHide, !isCollapsed else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: settings.autoHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isMouseInMenuBar {
                    self.scheduleAutoHide()
                } else {
                    self.collapse()
                }
            }
        }
    }

    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    private func configureHoverMonitor() {
        removeHoverMonitor()
        guard settings.revealOnHover else { return }
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCollapsed, self.isMouseInMenuBar else {
                    self?.hoverDwellTimer?.invalidate()
                    self?.hoverDwellTimer = nil
                    return
                }
                guard self.hoverDwellTimer == nil else { return }
                self.hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.hoverDwellTimer = nil
                        if self?.isCollapsed == true, self?.isMouseInMenuBar == true {
                            self?.reveal()
                        }
                    }
                }
            }
        }
    }

    private func removeHoverMonitor() {
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
        hoverMonitor = nil
        hoverDwellTimer?.invalidate()
        hoverDwellTimer = nil
    }
}
