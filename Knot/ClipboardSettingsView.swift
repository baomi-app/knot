import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject var store: ClipboardSettingsStore
    @State private var newBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Clipboard History")
                    .font(.title2.weight(.semibold))
                Text("History stays encrypted on this Mac. Excluded apps are never recorded.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Maximum entries", selection: historyLimitBinding) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("250").tag(250)
                }

                Picker("Keep history", selection: retentionBinding) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }
            }
            .formStyle(.grouped)
            .frame(height: 108)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Excluded Applications")
                        .font(.headline)
                    Spacer()
                    Button("Restore Defaults") {
                        store.restoreDefaultExclusions()
                    }
                    .controlSize(.small)
                }

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.excludedBundleIDs.sorted(), id: \.self) { bundleID in
                            HStack {
                                Image(systemName: "app.badge.checkmark")
                                    .foregroundStyle(.secondary)
                                Text(bundleID)
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    store.removeExclusion(bundleID)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain)
                                .help("Remove exclusion")
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(.primary.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 128)

                HStack {
                    TextField("Bundle identifier, for example com.example.app", text: $newBundleID)
                        .onSubmit(addExclusion)
                    Button("Add", action: addExclusion)
                        .disabled(!store.isValidBundleID(newBundleID))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 640, height: 440)
    }

    private var historyLimitBinding: Binding<Int> {
        Binding(
            get: { store.historyLimit },
            set: { store.setHistoryLimit($0) }
        )
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { store.retentionDays },
            set: { store.setRetentionDays($0) }
        )
    }

    private func addExclusion() {
        guard store.isValidBundleID(newBundleID) else { return }
        store.addExclusion(newBundleID)
        newBundleID = ""
    }
}
