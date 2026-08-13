import AppKit
import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.55)
            if model.mode == .clipboard {
                clipboardContent
            } else {
                resultList
            }
            footer
        }
        .frame(width: 720, height: 486)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .preferredColorScheme(nil)
        .onAppear { searchIsFocused = true }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            model.runSelected()
            return .handled
        }
        .onKeyPress(.escape) {
            model.requestClose()
            return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(
                model.mode == .clipboard ? "Search clipboard history" : "Search apps, commands, and links",
                text: $model.query
            )
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .focused($searchIsFocused)
                .onKeyPress(.tab) {
                    model.acceptSelectedSuggestion() ? .handled : .ignored
                }

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 72)
    }

    private var resultList: some View {
        Group {
            if model.results.isEmpty {
                ContentUnavailableView.search(text: model.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                                ResultRow(item: item, isSelected: index == model.selectedIndex) {
                                    model.selectedIndex = index
                                    model.run(item)
                                } onPin: {
                                    model.togglePin(item)
                                }
                                .id(item.id)
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: model.selectedIndex) {
                        guard model.results.indices.contains(model.selectedIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(model.results[model.selectedIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var clipboardContent: some View {
        HStack(spacing: 0) {
            Group {
                if model.results.isEmpty {
                    ContentUnavailableView(
                        "No Clipboard Items",
                        systemImage: "clipboard",
                        description: Text(model.query.isEmpty
                            ? "Copy something to start building your history."
                            : "No items match your search.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                                    ClipboardResultRow(
                                        item: item,
                                        isSelected: index == model.selectedIndex
                                    ) {
                                        model.selectedIndex = index
                                    } onPin: {
                                        model.togglePin(item)
                                    }
                                    .id(item.id)
                                }
                            }
                            .padding(10)
                        }
                        .onChange(of: model.selectedIndex) {
                            guard model.results.indices.contains(model.selectedIndex) else { return }
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(model.results[model.selectedIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(width: 390)

            Divider().opacity(0.55)

            ClipboardPreview(entry: model.selectedClipboardEntry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(model.message ?? "Knot keeps your everyday tools one shortcut away.")
                .lineLimit(1)
            Spacer()
            ShortcutHint(keys: ["↑", "↓"], label: "Navigate")
            ShortcutHint(keys: ["↩"], label: model.mode == .clipboard ? "Paste" : "Open")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.primary.opacity(0.035))
    }
}

private struct ClipboardResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let action: () -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 11) {
                    Group {
                        if let data = item.imageData, let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(2)
                        Text(item.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.leading, 9)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onPin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.isPinned ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 7)
        }
        .background(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ClipboardPreview: View {
    let entry: ClipboardEntry?

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 14) {
                    if let data = entry.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(entry.value)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        if let sourceName = entry.sourceName {
                            Label(sourceName, systemImage: "app")
                        }
                        Label(entry.copiedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
                .padding(18)
            } else {
                ContentUnavailableView("Select an Item", systemImage: "doc.text.magnifyingglass")
            }
        }
    }
}

private struct ResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let action: () -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 13) {
                Group {
                    if let imageData = item.imageData, let image = NSImage(data: imageData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if let iconURL = item.iconURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: iconURL.path))
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    } else {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .medium))
                    }
                }
                .frame(width: 36, height: 36)
                .background(.primary.opacity(isSelected ? 0.11 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(item.section.rawValue)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                }
                .padding(.leading, 10)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if case .pasteClipboard = item.action {
                Button(action: onPin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .frame(width: 30, height: 30)
                        .foregroundStyle(item.isPinned ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin")
                .padding(.trailing, 8)
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ShortcutHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .frame(minWidth: 19, minHeight: 19)
                        .background(.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            Text(label)
        }
    }
}
