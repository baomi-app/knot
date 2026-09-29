import AppKit
import ApplicationServices
import Combine
import Foundation

/// Controls Knot's compact menu-bar section. macOS 14–26 use the classic
/// status-item length mechanism; macOS 27 uses a runtime-resolved compatibility
/// backend because oversized status items no longer displace their neighbors.
@MainActor
final class KnotBarController: NSObject, ObservableObject, NSMenuDelegate {
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
    private var assessmentPolicy: KnotBarVisibilityPolicy?
    private var assessmentGeneration = UUID()
    private var latestRunningBundleIdentifiers = Set<String>()
    private var latestRunningProcessIdentifiers = Set<pid_t>()
    private let settingsUpdateScheduler = KnotBarUpdateScheduler()
    private let assessmentRefreshScheduler = KnotBarUpdateScheduler()
    private let menuBarReader = KnotBarMenuBarReader()
    private lazy var menuBarMonitor = KnotBarMenuBarMonitor(
        timing: .init(),
        read: { [weak self] in await self?.readMenuBar() },
        onRead: { [weak self] snapshot in self?.didReadMenuBar(snapshot) }
    )
    private var removedCompatibilitySeparator = false

    var usesMacOS27Compatibility: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    private override init() {
        super.init()
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
        .sink { [weak self] _ in self?.scheduleSettingsUpdate() }
        .store(in: &cancellables)

        settings.$separatorsHidden
            .sink { [weak self] _ in self?.scheduleSettingsUpdate() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenParametersChanged() }
            .store(in: &cancellables)

        if usesMacOS27Compatibility {
            // Accessory/menu-bar-only apps do not reliably emit workspace
            // launch notifications. The running-applications KVO list does.
            NSWorkspace.shared.publisher(for: \.runningApplications, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink { [weak self] applications in
                    self?.scheduleAssessmentRefresh(runningApplications: applications)
                }
                .store(in: &cancellables)

            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.menuBarMonitor.layoutMayHaveChanged() }
                .store(in: &cancellables)
        }

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
            guard self?.started == true, self?.settings.isEnabled == true else { return }
            self?.collapse()
        }
    }

    func stop() {
        autoHideTimer?.invalidate()
        hoverDwellTimer?.invalidate()
        removeHoverMonitor()
        cancellables.removeAll()
        settingsUpdateScheduler.cancel()
        assessmentRefreshScheduler.cancel()
        latestRunningBundleIdentifiers.removeAll()
        latestRunningProcessIdentifiers.removeAll()
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
        (isCollapsed || menuBarMonitor.isRunning) ? reveal() : collapse()
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
        guard isCollapsed || menuBarMonitor.isRunning else { return }
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
                at: NSPoint(x: 0, y: sender.bounds.minY - 4),
                in: sender
            )
        } else {
            toggle()
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
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
        let updates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(AppUpdater.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updates.target = AppUpdater.shared
        updates.isEnabled = AppUpdater.shared.canCheckForUpdates
        menu.addItem(updates)
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

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(AppUpdater.checkForUpdates(_:)) {
            item.isEnabled = AppUpdater.shared.canCheckForUpdates
        }
    }

    @objc private func toggleMenuAction() { toggle() }
    @objc private func openKnotMenuAction() { AppDelegate.shared?.togglePanel() }
    @objc private func openSettingsMenuAction() { AppDelegate.shared?.showSettings() }
    @objc private func disableMenuAction() { settings.setEnabled(false) }
    @objc private func quitMenuAction() { NSApp.terminate(nil) }

    private func scheduleSettingsUpdate() {
        // @Published emits in willSet. Reconcile once after all setters finish,
        // including updates triggered together by a settings binding.
        settingsUpdateScheduler.schedule { [weak self] in
            guard let self, self.started else { return }
            self.settingsChanged()
            self.updateSeparatorAppearance()
        }
    }

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
            if isCollapsed, let policy = assessmentPolicy {
                // Keep the original hidden set while the display layout settles.
                // The menu-bar monitor will pick up newly positioned items.
                applyAssessmentPolicy(policy.updatingRunningApplications(
                    Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                ))
            }
            menuBarMonitor.layoutMayHaveChanged()
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

        menuBarMonitor.start()
    }

    private func scheduleAssessmentRefresh(runningApplications: [NSRunningApplication]) {
        // Save every emitted snapshot, even when a refresh is already queued,
        // so rapid launches/exits apply the latest list rather than the first.
        latestRunningBundleIdentifiers = Set(runningApplications.compactMap(\.bundleIdentifier))
        let processIdentifiers = Set(runningApplications.map(\.processIdentifier))
        if processIdentifiers != latestRunningProcessIdentifiers {
            latestRunningProcessIdentifiers = processIdentifiers
            menuBarMonitor.layoutMayHaveChanged()
        }
        guard isCollapsed, assessmentPolicy != nil else { return }
        assessmentRefreshScheduler.schedule { [weak self] in
            guard let self, self.started else { return }
            guard self.settings.isEnabled, self.isCollapsed, let policy = self.assessmentPolicy else { return }
            // The collapsed AX tree omits hidden groups. Keep their original
            // classification, including across an app's exit and relaunch.
            let refreshed = policy.updatingRunningApplications(
                self.latestRunningBundleIdentifiers
            )
            guard refreshed != policy else { return }
            self.applyAssessmentPolicy(refreshed)
        }
    }

    private func applyAssessmentPolicy(_ policy: KnotBarVisibilityPolicy) {
        guard !policy.hidden.isEmpty else {
            releaseAssessmentAssertion()
            assessmentPolicy = policy
            compatibilityMessage = nil
            isCollapsed = true
            autoHideTimer?.invalidate()
            updateButton()
            return
        }

        let generation = UUID()
        assessmentGeneration = generation
        let assertion = KnotBarAssessmentActivate(
            (0...8).map(NSNumber.init(value:)),
            Array(policy.allowed).sorted()
        ) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                guard let self, self.assessmentGeneration == generation else { return }
                self.invalidateAssessmentAssertion()
                self.isCollapsed = false
                self.updateButton()
                self.compatibilityMessage = "Could not hide menu bar items: \(error.localizedDescription)"
            }
        }
        guard let assertion else {
            invalidateAssessmentAssertion()
            isCollapsed = false
            updateButton()
            compatibilityMessage = "Knot Bar is not available on this macOS 27 build."
            return
        }

        if let previousAssertion = assessmentAssertion {
            KnotBarAssessmentInvalidate(previousAssertion)
        }
        assessmentAssertion = assertion as AnyObject
        assessmentPolicy = policy
        compatibilityMessage = nil
        isCollapsed = true
        autoHideTimer?.invalidate()
        updateButton()
    }

    private func readMenuBar() async -> KnotBarVisibilityPolicy? {
        guard let request = menuBarReadRequest() else { return nil }
        return await menuBarReader.read(request)
    }

    private func menuBarReadRequest() -> KnotBarMenuBarReadRequest? {
        guard started, settings.isEnabled,
              let boundaryX = toggleItem.button?.window?.frame.minX else { return nil }
        let applications = NSWorkspace.shared.runningApplications
        guard let agent = applications.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) else {
            return nil
        }
        let bundles = Dictionary(uniqueKeysWithValues: applications.compactMap { application in
            application.bundleIdentifier.map { (application.processIdentifier, $0) }
        })
        return KnotBarMenuBarReadRequest(
            agentPID: agent.processIdentifier,
            bundleIdentifiersByPID: bundles,
            ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.baomi.knot",
            boundaryX: boundaryX
        )
    }

    private func didReadMenuBar(_ snapshot: KnotBarVisibilityPolicy?) {
        guard started, settings.isEnabled, menuBarMonitor.isRunning else { return }
        guard let snapshot else {
            if !isCollapsed {
                menuBarMonitor.stop()
                compatibilityMessage = "Could not read the menu bar. Try toggling Accessibility access for Knot."
            }
            return
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let refreshed = (assessmentPolicy ?? snapshot).updatingRunningApplications(
            running,
            newlyHidden: snapshot.hidden
        )
        guard refreshed != assessmentPolicy else { return }
        applyAssessmentPolicy(refreshed)
    }

    private func invalidateAssessmentAssertion() {
        menuBarMonitor.stop()
        assessmentPolicy = nil
        releaseAssessmentAssertion()
    }

    private func releaseAssessmentAssertion() {
        assessmentGeneration = UUID()
        guard let assessmentAssertion else { return }
        KnotBarAssessmentInvalidate(assessmentAssertion)
        self.assessmentAssertion = nil
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
