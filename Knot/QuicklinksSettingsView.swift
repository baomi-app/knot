import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuicklinksSettingsView: View {
    @ObservedObject var store: QuicklinkStore
    @State private var selection: UUID?
    @State private var title = ""
    @State private var urlTemplate = ""
    @State private var keyword = ""
    @State private var transferMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            editor
        }
        .frame(width: 680, height: 410)
        .overlay(alignment: .bottomTrailing) {
            if let transferMessage {
                Text(transferMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(12)
            }
        }
        .onAppear {
            selection = selection ?? store.links.first?.id
            loadSelection()
        }
        .onChange(of: selection) {
            loadSelection()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.links) { link in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(link.title).fontWeight(.medium)
                        Text(link.keyword)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(link.id)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    selection = store.add().id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Quicklink")

                Button {
                    guard let selection else { return }
                    store.remove(id: selection)
                    self.selection = store.links.first?.id
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                .help("Remove Quicklink")

                Spacer()

                Button {
                    importQuicklinks()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import Quicklinks")

                Button {
                    exportQuicklinks()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export Quicklinks")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .frame(height: 38)
        }
        .frame(width: 220)
    }

    private var editor: some View {
        Group {
            if let selection {
                Form {
                    TextField("Name", text: $title)
                    TextField("Keyword", text: $keyword)
                    TextField("URL template", text: $urlTemplate)

                    Text("Use {query} where the typed argument should appear. Keywords cannot contain spaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer()
                        Button("Save") {
                            store.update(
                                id: selection,
                                title: title,
                                urlTemplate: urlTemplate,
                                keyword: keyword
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.isValid(
                            title: title,
                            urlTemplate: urlTemplate,
                            keyword: keyword,
                            excluding: selection
                        ))
                    }
                }
                .formStyle(.grouped)
                .padding(18)
            } else {
                ContentUnavailableView(
                    "No Quicklink Selected",
                    systemImage: "link",
                    description: Text("Add a Quicklink to open a URL from Knot Search.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadSelection() {
        guard let selection,
              let link = store.links.first(where: { $0.id == selection }) else {
            title = ""
            urlTemplate = ""
            keyword = ""
            return
        }
        title = link.title
        urlTemplate = link.urlTemplate
        keyword = link.keyword
    }

    private func importQuicklinks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Knot Quicklinks export file. Existing Quicklinks will be kept."
        guard panel.runModal() == .OK else { return }
        guard let url = panel.url,
              let data = try? Data(contentsOf: url),
              let result = store.importData(data) else {
            transferMessage = "The selected file is not a valid Knot Quicklinks export."
            return
        }
        transferMessage = result.message
        selection = selection ?? store.links.first?.id
    }

    private func exportQuicklinks() {
        guard let data = store.exportData() else {
            transferMessage = "Quicklinks could not be exported."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Knot Quicklinks.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            transferMessage = "Exported \(store.links.count) Quicklinks."
        } catch {
            transferMessage = "Quicklinks could not be exported."
        }
    }
}
