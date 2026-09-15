import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates").fontWeight(.medium)
                    Text("Knot \(updater.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Button(updater.isCheckingFeed ? "Checking…" : "Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            if let error = updater.configurationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let message = updater.lastCheckMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticChecksEnabled },
                    set: updater.setAutomaticChecksEnabled
                ))
                Toggle("Download updates automatically", isOn: Binding(
                    get: { updater.automaticDownloadsEnabled },
                    set: updater.setAutomaticDownloadsEnabled
                ))
                .disabled(!updater.automaticChecksEnabled)

                Text("Updates are verified before installation. Knot restarts to apply them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(0.08))
        }
        .onAppear { updater.start() }
    }
}
