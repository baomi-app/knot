import SwiftUI

@main
struct KnotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var launcherStore = LauncherShortcutStore.shared

    var body: some Scene {
        MenuBarExtra("Knot", image: "KnotMenuBar") {
            Button("Open Knot") {
                appDelegate.togglePanel()
            }

            Divider()

            Text("\(ShortcutDisplayFormatter.label(keyCode: launcherStore.shortcut.keyCode, modifiers: launcherStore.shortcut.modifiers)) to open")
                .foregroundStyle(.secondary)

            Divider()

            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit Knot") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            KnotSettingsView()
        }
        .windowResizability(.contentSize)
    }
}
