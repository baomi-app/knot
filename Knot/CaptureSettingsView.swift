import AppKit
import SwiftUI

struct CaptureSettingsView: View {
    @ObservedObject var store: CaptureSettingsStore
    @ObservedObject private var historyStore = CaptureHistoryStore.shared
    @State private var prefixDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Capture Output")
                    .font(.title2.weight(.semibold))
                Text("Choose where screenshots go and what happens immediately after capture.")
                    .foregroundStyle(.secondary)
            }

            Form {
                Toggle("Save captures automatically", isOn: saveEnabledBinding)

                Picker("File format", selection: formatBinding) {
                    ForEach(CaptureFileFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!store.saveEnabled)

                TextField("Filename prefix", text: $prefixDraft)
                    .onSubmit(savePrefix)
                    .onChange(of: prefixDraft) { savePrefix() }
                    .disabled(!store.saveEnabled)

                LabeledContent("Save folder") {
                    HStack(spacing: 8) {
                        Text(historyStore.captureDirectoryURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseDirectory)
                        Button("Reset") { store.setDirectory(nil) }
                            .disabled(store.customDirectoryPath == nil)
                    }
                }
                .disabled(!store.saveEnabled)

                LabeledContent("Capture workflow") {
                    Text("Copy after annotation")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Image(systemName: "lock.shield")
                Text("OCR continues to run entirely on this Mac.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(width: 680, height: 410)
        .onAppear { prefixDraft = store.fileNamePrefix }
    }

    private var formatBinding: Binding<CaptureFileFormat> {
        Binding(
            get: { store.format },
            set: { value in store.setFormat(value) }
        )
    }

    private var saveEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.saveEnabled },
            set: { value in store.setSaveEnabled(value) }
        )
    }

    private func savePrefix() {
        store.setFileNamePrefix(prefixDraft)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            store.setDirectory(panel.url)
        }
    }
}
