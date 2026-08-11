import Combine
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var loginStore = LaunchAtLoginStore.shared
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("General")
                    .font(.title2.weight(.semibold))
                Text("Knot requests system access only for features that need it.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Permissions") {
                VStack(spacing: 0) {
                    permissionRow(
                        title: "Accessibility",
                        detail: "Window management and direct clipboard paste",
                        symbol: "accessibility",
                        granted: accessibilityGranted,
                        request: { PermissionManager.requestAccessibility() },
                        openSettings: PermissionManager.openAccessibilitySettings
                    )
                    Divider().padding(.leading, 42)
                    permissionRow(
                        title: "Screen Recording",
                        detail: "Screenshots and on-device OCR",
                        symbol: "rectangle.dashed.badge.record",
                        granted: screenRecordingGranted,
                        request: { PermissionManager.requestScreenRecording() },
                        openSettings: PermissionManager.openScreenRecordingSettings
                    )
                }
                .padding(8)
            }

            startupCard

            Spacer()
        }
        .padding(24)
        .frame(width: 650, height: 420)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func permissionRow(
        title: String,
        detail: String,
        symbol: String,
        granted: Bool,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(granted ? "Allowed" : "Not Allowed", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
            if !granted {
                Button("Allow") { request() }
                Button("Settings") { openSettings() }
            }
        }
        .frame(height: 54)
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginStore.isEnabled },
            set: { value in loginStore.setEnabled(value) }
        )
    }

    private var startupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(loginStore.isEnabled ? Color.accentColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at Login")
                        .fontWeight(.medium)
                    Text(loginStore.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Open Knot at Login", isOn: loginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(12)

            if loginStore.status == .requiresApproval || loginStore.errorMessage != nil {
                Divider().padding(.leading, 56)

                HStack(spacing: 10) {
                    if let error = loginStore.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else {
                        Text("macOS needs your approval before Knot can open automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if loginStore.status == .requiresApproval {
                        Button("Open Settings") {
                            loginStore.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 56)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
            }
        }
        .background(.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
        .accessibilityElement(children: .contain)
    }

    private func refresh() {
        accessibilityGranted = PermissionManager.accessibilityGranted
        screenRecordingGranted = PermissionManager.screenRecordingGranted
        loginStore.refresh()
    }
}
