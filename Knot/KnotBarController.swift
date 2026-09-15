import AppKit
import ApplicationServices
import Combine
import Foundation

/// Controls Knot's compact menu-bar section. macOS 14–26 use the classic
/// status-item length mechanism; macOS 27 uses a runtime-resolved compatibility
/// backend because oversized status items no longer displace their neighbors.
@MainActor
final class KnotBarController: ObservableObject {
    static let shared = KnotBarController()

    @Published private(set) var isCollapsed = false
    @Published private(set) var compatibilityMessage: String?

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
    private var assessmentAssertion: AnyObject?
    private var removedCompatibilitySeparator = false

    var usesMacOS27Compatibility: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

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
            .sink { [weak self] _ in self?.updateSeparatorAppearance() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenParametersChanged() }
            .store(in: &cancellables)

        toggleItem.isVisible = true
        if usesMacOS27Compatibility {
            if !removedCompatibilitySeparator {
                NSStatusBar.system.removeStatusItem(separatorItem)
                removedCompatibilitySeparator = true
            }
        } else {
            separatorItem.isVisible = true
        }
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
        invalidateAssessmentAssertion()
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
        if usesMacOS27Compatibility {
            collapseOnMacOS27()
            return
        }
        updateCollapsedLength()
        separatorItem.length = collapsedSeparatorLength
        isCollapsed = true
        autoHideTimer?.invalidate()
        updateButton()
    }

    func reveal() {
        guard isCollapsed else { return }
        invalidateAssessmentAssertion()
        if !usesMacOS27Compatibility {
            separatorItem.length = expandedSeparatorLength
        }
        isCollapsed = false
        updateSeparatorAppearance()
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
            button.setAccessibilityTitle("Knot.Bar.Toggle")
        }
        toggleItem.behavior = .removalAllowed
        if let button = separatorItem.button {
            button.image = separatorImage()
            button.image?.isTemplate = true
            button.toolTip = "Items to the left belong to Knot Bar's hidden section"
            button.setAccessibilityTitle("Knot.Bar.Separator")
        }
        separatorItem.behavior = .removalAllowed
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
        let open = NSMenuItem(title: "Open Knot", action: #selector(openKnotMenuAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsMenuAction), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let disable = NSMenuItem(title: "Disable Knot Bar", action: #selector(disableMenuAction), keyEquivalent: "")
        disable.target = self
        menu.addItem(disable)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Knot", action: #selector(quitMenuAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleMenuAction() { toggle() }
    @objc private func openKnotMenuAction() { (NSApp.delegate as? AppDelegate)?.togglePanel() }
    @objc private func openSettingsMenuAction() { (NSApp.delegate as? AppDelegate)?.showSettings() }
    @objc private func disableMenuAction() { settings.setEnabled(false) }
    @objc private func quitMenuAction() { NSApp.terminate(nil) }

    private func settingsChanged() {
        if settings.isEnabled {
            updateButton()
            configureHoverMonitor()
            if !isCollapsed { scheduleAutoHide() }
        } else {
            invalidateAssessmentAssertion()
            if !usesMacOS27Compatibility {
                separatorItem.length = expandedSeparatorLength
            }
            isCollapsed = false
            autoHideTimer?.invalidate()
            removeHoverMonitor()
            updateSeparatorAppearance()
            updateButton()
        }
    }

    private func screenParametersChanged() {
        if usesMacOS27Compatibility {
            if isCollapsed {
                invalidateAssessmentAssertion()
                isCollapsed = false
                collapseOnMacOS27()
            }
            return
        }
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

    private func updateSeparatorAppearance() {
        guard !usesMacOS27Compatibility else { return }
        separatorItem.button?.isHidden = settings.separatorsHidden
    }

    // MARK: - macOS 27 compatibility

    /// macOS 27 no longer lets an oversized NSStatusItem push neighboring
    /// items off-screen. It does expose a system-owned menu-bar policy object,
    /// so we build an allowlist from the items currently to the separator's
    /// right. Everything is resolved at runtime and fails open.
    private func collapseOnMacOS27() {
        guard AXIsProcessTrusted() else {
            compatibilityMessage = "Accessibility access is required on macOS 27."
            return
        }
        guard KnotBarAssessmentIsAvailable() else {
            compatibilityMessage = "Knot Bar is not available on this macOS 27 build."
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.settings.isEnabled, !self.isCollapsed else { return }
            guard let boundaryX = self.toggleItem.button?.window?.frame.minX,
                  let policy = self.menuBarPolicy(boundaryX: boundaryX) else {
                self.compatibilityMessage = "Could not read the menu bar. Try toggling Accessibility access for Knot."
                return
            }
#if DEBUG
            NSLog(
                "[Knot Bar] boundary %.1f; hidden: %@; allowed bundles: %@",
                boundaryX,
                policy.hidden.sorted().joined(separator: ", "),
                policy.allowed.sorted().joined(separator: ", ")
            )
#endif

            guard !policy.hidden.isEmpty else {
                self.invalidateAssessmentAssertion()
                self.compatibilityMessage = nil
                self.isCollapsed = true
                self.autoHideTimer?.invalidate()
                self.updateButton()
                return
            }

            let assertion = KnotBarAssessmentActivate(
                (0...8).map(NSNumber.init(value:)),
                Array(policy.allowed).sorted()
            ) { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.invalidateAssessmentAssertion()
                    self.isCollapsed = false
                    self.updateButton()
                    self.compatibilityMessage = "Could not hide menu bar items: \(error.localizedDescription)"
                }
            }
            guard let assertion else {
                self.compatibilityMessage = "Knot Bar is not available on this macOS 27 build."
                return
            }

            self.invalidateAssessmentAssertion()
            self.assessmentAssertion = assertion as AnyObject
            self.compatibilityMessage = nil
            self.isCollapsed = true
            self.autoHideTimer?.invalidate()
            self.updateButton()
        }
    }

    private func invalidateAssessmentAssertion() {
        guard let assessmentAssertion else { return }
        KnotBarAssessmentInvalidate(assessmentAssertion)
        self.assessmentAssertion = nil
    }

    /// Returns third-party bundle identifiers whose macOS 27 menu-bar groups
    /// are positioned to the separator's right. The MenuBarAgent repeats its
    /// tree per display; selecting the window that contains our separator
    /// keeps all comparisons in one coordinate space.
    private func menuBarPolicy(boundaryX: CGFloat) -> (allowed: Set<String>, hidden: Set<String>)? {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.MenuBarAgent"
        }) else { return nil }

        let agentElement = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(agentElement, 0.4)
        let windows = axChildren(of: agentElement).filter { axRole(of: $0) == "AXWindow" }
        let ownBundleID = Bundle.main.bundleIdentifier ?? "app.baomi.knot"

        var bestGroups: [AXUIElement]?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for window in windows {
            let groups = axChildren(of: window)
            for group in groups where bundleIdentifier(in: group, agentPID: agent.processIdentifier) == ownBundleID {
                guard let frame = axFrame(of: group) else { continue }
                let distance = abs(frame.minX - boundaryX)
                if distance < bestDistance {
                    bestDistance = distance
                    bestGroups = groups
                }
            }
        }
        guard bestDistance < 80, let groups = bestGroups else { return nil }

        var bundlesToLeft = Set<String>()
        var bundlesToRight = Set<String>()
        for group in groups {
            guard let frame = axFrame(of: group) else { continue }
            if frame.minX < boundaryX - 1 {
                if let bundleID = bundleIdentifier(in: group, agentPID: agent.processIdentifier) {
                    bundlesToLeft.insert(bundleID)
                }
            } else if frame.minX > boundaryX + 1 {
                if let bundleID = bundleIdentifier(in: group, agentPID: agent.processIdentifier) {
                    bundlesToRight.insert(bundleID)
                }
            }
        }

        // The macOS 27 primitive hides at bundle granularity. If one app owns
        // items on both sides, visible wins so a mixed placement cannot make
        // the app's required control disappear.
        var hidden = bundlesToLeft.subtracting(bundlesToRight)
        hidden.remove(ownBundleID)
        hidden = Set(hidden.filter { !$0.hasPrefix("com.apple.") })

        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        allowed.subtract(hidden)
        allowed.insert(ownBundleID)
        allowed.insert("com.apple.systemuiserver")
        return (allowed, hidden)
    }

    private func bundleIdentifier(in element: AXUIElement, agentPID: pid_t, depth: Int = 0) -> String? {
        guard depth <= 3 else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid > 0, pid != agentPID,
           let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            return bundleID
        }
        for child in axChildren(of: element) {
            if let bundleID = bundleIdentifier(in: child, agentPID: agentPID, depth: depth + 1) {
                return bundleID
            }
        }
        return nil
    }

    private func axChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func axRole(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return value as? String ?? ""
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var frame = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &frame) else { return nil }
        return frame
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
