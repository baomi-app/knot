import AppKit
import Combine
import SwiftUI

@MainActor
final class OnboardingController {
    private static let completedKey = "completedOnboardingV1"
    private var window: NSWindow?

    var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    func showIfNeeded() {
        guard shouldShow else { return }
        let view = OnboardingView { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            self?.window?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Knot"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    let finish: () -> Void
    @ObservedObject private var loginStore = LaunchAtLoginStore.shared
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Tie your Mac tools together")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Knot stays local and asks only for the access its native tools require.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                onboardingRow(
                    title: "Accessibility",
                    detail: "Move windows and paste clipboard history",
                    symbol: "accessibility",
                    granted: accessibilityGranted
                ) { PermissionManager.requestAccessibility() }
                onboardingRow(
                    title: "Screen Recording",
                    detail: "Capture screens and recognize text locally",
                    symbol: "viewfinder",
                    granted: screenRecordingGranted
                ) { PermissionManager.requestScreenRecording() }

                Toggle("Launch Knot when I log in", isOn: Binding(
                    get: { loginStore.isEnabled },
                    set: { value in loginStore.setEnabled(value) }
                ))
                .padding(.horizontal, 12)
            }

            HStack {
                Text("You can change these later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue", action: finish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(34)
        .background(.ultraThickMaterial)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func onboardingRow(
        title: String,
        detail: String,
        symbol: String,
        granted: Bool,
        request: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: request)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func refresh() {
        accessibilityGranted = PermissionManager.accessibilityGranted
        screenRecordingGranted = PermissionManager.screenRecordingGranted
        loginStore.refresh()
    }
}
