import SwiftUI

struct KnotSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutsSettingsView(store: WindowShortcutStore.shared)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            QuicklinksSettingsView(store: QuicklinkStore.shared)
                .tabItem {
                    Label("Quicklinks", systemImage: "link")
                }

            ClipboardSettingsView(store: ClipboardSettingsStore.shared)
                .tabItem {
                    Label("Clipboard", systemImage: "clipboard")
                }

            CaptureSettingsView(store: CaptureSettingsStore.shared)
                .tabItem {
                    Label("Capture", systemImage: "viewfinder")
                }

            KnotBarSettingsView(store: KnotBarSettingsStore.shared)
                .tabItem {
                    Label("Bar", systemImage: "menubar.rectangle")
                }
        }
        .frame(width: 720, height: 520)
    }
}
