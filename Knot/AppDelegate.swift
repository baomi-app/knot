import AppKit
import Carbon
import Combine
import SwiftUI

private let knotHotKeySignature: OSType = 0x4B4E4F54 // KNOT
private let windowHotKeySignature: OSType = 0x4B574E44 // KWND
private let captureHotKeySignature: OSType = 0x4B434150 // KCAP
private let clipboardHotKeySignature: OSType = 0x4B434C50 // KCLP

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SearchModel()
    private let shortcutStore = WindowShortcutStore.shared
    private let launcherShortcutStore = LauncherShortcutStore.shared
    private let captureShortcutStore = CaptureShortcutStore.shared
    private let clipboardShortcutStore = ClipboardShortcutStore.shared
    private var panelController: CommandPanelController?
    private var launcherHotKeyRef: EventHotKeyRef?
    private var captureHotKeyRef: EventHotKeyRef?
    private var clipboardHotKeyRef: EventHotKeyRef?
    private var windowHotKeyRefs: [EventHotKeyRef] = []
    private var windowActionsByID: [UInt32: WindowAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var shortcutCancellable: AnyCancellable?
    private var launcherShortcutCancellable: AnyCancellable?
    private var captureShortcutCancellable: AnyCancellable?
    private var clipboardShortcutCancellable: AnyCancellable?
    private var isHotKeyRegistrationScheduled = false
    private let onboardingController = OnboardingController()
    private lazy var settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = CommandPanelController(model: model) { [weak self] in
            self?.showSettings()
        }
        installHotKeyEventHandler()
        registerAllHotKeys()
        shortcutCancellable = shortcutStore.$shortcuts
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHotKeyRegistration()
            }
        launcherShortcutCancellable = launcherShortcutStore.$shortcut
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHotKeyRegistration()
            }
        captureShortcutCancellable = captureShortcutStore.$shortcut
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHotKeyRegistration()
            }
        clipboardShortcutCancellable = clipboardShortcutStore.$shortcut
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleHotKeyRegistration()
            }
        model.start()
        KnotBarController.shared.start()
        onboardingController.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        KnotBarController.shared.stop()
        unregisterAllHotKeys()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func togglePanel() {
        panelController?.toggle()
    }

    func showSettings() {
        settingsWindowController.show()
    }

    private func installHotKeyEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyID.signature == knotHotKeySignature {
                    Task { @MainActor in delegate.togglePanel() }
                    return noErr
                }
                if hotKeyID.signature == windowHotKeySignature {
                    Task { @MainActor in delegate.handleWindowHotKey(id: hotKeyID.id) }
                    return noErr
                }
                if hotKeyID.signature == captureHotKeySignature {
                    Task { @MainActor in CaptureCoordinator.shared.unified() }
                    return noErr
                }
                if hotKeyID.signature == clipboardHotKeySignature {
                    Task { @MainActor in delegate.panelController?.showClipboard() }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            pointer,
            &eventHandlerRef
        )

    }

    private func registerLauncherHotKey() {
        let shortcut = launcherShortcutStore.shortcut
        let hotKeyID = EventHotKeyID(signature: knotHotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &launcherHotKeyRef
        )
        if status != noErr {
            NSLog("[Knot Shortcuts] Could not register launcher shortcut (status %d)", status)
        }
    }

    private func registerWindowHotKeys() {
        unregisterWindowHotKeys()

        for (index, shortcut) in shortcutStore.shortcuts.enumerated() {
            let id = UInt32(index + 100)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                EventHotKeyID(signature: windowHotKeySignature, id: id),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                windowHotKeyRefs.append(reference)
                windowActionsByID[id] = shortcut.action
            }
        }
    }

    private func registerCaptureHotKey() {
        let shortcut = captureShortcutStore.shortcut
        let hotKeyID = EventHotKeyID(signature: captureHotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &captureHotKeyRef
        )
        if status != noErr {
            NSLog("[Knot Shortcuts] Could not register capture shortcut (status %d)", status)
        }
    }

    private func registerClipboardHotKey() {
        let shortcut = clipboardShortcutStore.shortcut
        let hotKeyID = EventHotKeyID(signature: clipboardHotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &clipboardHotKeyRef
        )
        if status != noErr {
            NSLog("[Knot Shortcuts] Could not register clipboard shortcut (status %d)", status)
        }
    }

    private func scheduleHotKeyRegistration() {
        guard !isHotKeyRegistrationScheduled else { return }
        isHotKeyRegistrationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isHotKeyRegistrationScheduled = false
            self.registerAllHotKeys()
        }
    }

    private func registerAllHotKeys() {
        unregisterAllHotKeys()
        registerLauncherHotKey()
        registerCaptureHotKey()
        registerClipboardHotKey()
        registerWindowHotKeys()
    }

    private func unregisterAllHotKeys() {
        if let launcherHotKeyRef {
            UnregisterEventHotKey(launcherHotKeyRef)
            self.launcherHotKeyRef = nil
        }
        if let captureHotKeyRef {
            UnregisterEventHotKey(captureHotKeyRef)
            self.captureHotKeyRef = nil
        }
        if let clipboardHotKeyRef {
            UnregisterEventHotKey(clipboardHotKeyRef)
            self.clipboardHotKeyRef = nil
        }
        unregisterWindowHotKeys()
    }

    private func unregisterWindowHotKeys() {
        windowHotKeyRefs.forEach { UnregisterEventHotKey($0) }
        windowHotKeyRefs.removeAll()
        windowActionsByID.removeAll()
    }

    private func handleWindowHotKey(id: UInt32) {
        guard let action = windowActionsByID[id] else { return }
        _ = WindowManager.performCurrent(action)
    }
}
