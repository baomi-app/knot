import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var store: WindowShortcutStore
    @ObservedObject private var launcherStore = LauncherShortcutStore.shared
    @ObservedObject private var captureStore = CaptureShortcutStore.shared
    @ObservedObject private var clipboardStore = ClipboardShortcutStore.shared
    @State private var shortcutError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Keyboard Shortcuts")
                    .font(.title2.weight(.semibold))
                Text("Click a shortcut, then press a new combination. Escape cancels recording.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                GridRow {
                    Label {
                        Text("Open Knot Search")
                    } icon: {
                        Image("KnotMenuBar")
                    }
                        .frame(width: 220, alignment: .leading)
                    ShortcutRecorderView(
                        keyCode: launcherStore.shortcut.keyCode,
                        modifiers: launcherStore.shortcut.modifiers,
                        onRecord: updateLauncherShortcut
                    )
                }

                GridRow {
                    Label("Capture & Annotate", systemImage: "viewfinder")
                        .frame(width: 220, alignment: .leading)
                    ShortcutRecorderView(
                        keyCode: captureStore.shortcut.keyCode,
                        modifiers: captureStore.shortcut.modifiers,
                        onRecord: updateCaptureShortcut
                    )
                }

                GridRow {
                    Label("Clipboard History", systemImage: "clipboard")
                        .frame(width: 220, alignment: .leading)
                    ShortcutRecorderView(
                        keyCode: clipboardStore.shortcut.keyCode,
                        modifiers: clipboardStore.shortcut.modifiers,
                        onRecord: updateClipboardShortcut
                    )
                }

                Divider()
                    .gridCellColumns(2)
                    .padding(.vertical, 3)

                ForEach(WindowAction.allCases, id: \.self) { action in
                    shortcutRow(for: action)
                }
            }

            if let shortcutError {
                Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    store.reset()
                    launcherStore.reset()
                    captureStore.reset()
                    clipboardStore.reset()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func shortcutRow(for action: WindowAction) -> some View {
        let shortcut = store.shortcut(for: action)

        GridRow {
            Label(action.rawValue, systemImage: action.symbol)
                .frame(width: 220, alignment: .leading)
            ShortcutRecorderView(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ) { keyCode, modifiers in
                updateWindowShortcut(action: action, keyCode: keyCode, modifiers: modifiers)
            }
        }
    }

    private func updateLauncherShortcut(keyCode: UInt32, modifiers: UInt32) {
        guard validateShortcut(keyCode: keyCode, modifiers: modifiers) else { return }
        let previous = launcherStore.shortcut
        let capture = captureStore.shortcut
        let clipboard = clipboardStore.shortcut
        if capture.keyCode == keyCode && capture.modifiers == modifiers {
            captureStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if clipboard.keyCode == keyCode && clipboard.modifiers == modifiers {
            clipboardStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if let conflict = store.shortcuts.first(where: {
            $0.keyCode == keyCode && $0.modifiers == modifiers
        }) {
            store.update(
                action: conflict.action,
                keyCode: previous.keyCode,
                modifiers: previous.modifiers
            )
        }
        launcherStore.update(keyCode: keyCode, modifiers: modifiers)
    }

    private func updateWindowShortcut(action: WindowAction, keyCode: UInt32, modifiers: UInt32) {
        guard validateShortcut(keyCode: keyCode, modifiers: modifiers) else { return }
        let previous = store.shortcut(for: action)
        let launcher = launcherStore.shortcut
        let capture = captureStore.shortcut
        let clipboard = clipboardStore.shortcut
        if launcher.keyCode == keyCode && launcher.modifiers == modifiers {
            launcherStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if capture.keyCode == keyCode && capture.modifiers == modifiers {
            captureStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if clipboard.keyCode == keyCode && clipboard.modifiers == modifiers {
            clipboardStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        }
        store.update(action: action, keyCode: keyCode, modifiers: modifiers)
    }

    private func updateCaptureShortcut(keyCode: UInt32, modifiers: UInt32) {
        guard validateShortcut(keyCode: keyCode, modifiers: modifiers) else { return }
        let previous = captureStore.shortcut
        let launcher = launcherStore.shortcut
        let clipboard = clipboardStore.shortcut
        if launcher.keyCode == keyCode && launcher.modifiers == modifiers {
            launcherStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if clipboard.keyCode == keyCode && clipboard.modifiers == modifiers {
            clipboardStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if let conflict = store.shortcuts.first(where: {
            $0.keyCode == keyCode && $0.modifiers == modifiers
        }) {
            store.update(
                action: conflict.action,
                keyCode: previous.keyCode,
                modifiers: previous.modifiers
            )
        }
        captureStore.update(keyCode: keyCode, modifiers: modifiers)
    }

    private func updateClipboardShortcut(keyCode: UInt32, modifiers: UInt32) {
        guard validateShortcut(keyCode: keyCode, modifiers: modifiers) else { return }
        let previous = clipboardStore.shortcut
        let launcher = launcherStore.shortcut
        let capture = captureStore.shortcut
        if launcher.keyCode == keyCode && launcher.modifiers == modifiers {
            launcherStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if capture.keyCode == keyCode && capture.modifiers == modifiers {
            captureStore.update(keyCode: previous.keyCode, modifiers: previous.modifiers)
        } else if let conflict = store.shortcuts.first(where: {
            $0.keyCode == keyCode && $0.modifiers == modifiers
        }) {
            store.update(
                action: conflict.action,
                keyCode: previous.keyCode,
                modifiers: previous.modifiers
            )
        }
        clipboardStore.update(keyCode: keyCode, modifiers: modifiers)
    }

    private func validateShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let isAlreadyKnotShortcut = launcherStore.shortcut.keyCode == keyCode
            && launcherStore.shortcut.modifiers == modifiers
            || captureStore.shortcut.keyCode == keyCode
            && captureStore.shortcut.modifiers == modifiers
            || clipboardStore.shortcut.keyCode == keyCode
            && clipboardStore.shortcut.modifiers == modifiers
            || store.shortcuts.contains {
                $0.keyCode == keyCode && $0.modifiers == modifiers
            }

        if isAlreadyKnotShortcut || GlobalHotKeyAvailability.canRegister(
            keyCode: keyCode,
            modifiers: modifiers
        ) {
            shortcutError = nil
            return true
        }

        let label = ShortcutDisplayFormatter.label(keyCode: keyCode, modifiers: modifiers)
        shortcutError = "\(label) is already used by macOS or another app. Choose a different shortcut."
        NSSound.beep()
        return false
    }
}
