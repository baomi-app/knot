import AppKit
import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    let onShowSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchIsFocused: Bool

    private var palette: SearchPalette { SearchPalette(colorScheme) }

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            searchField
            separator
            if model.mode == .clipboard {
                clipboardContent(results)
            } else {
                resultList(results)
            }
            separator
            footer(results)
        }
        .frame(width: 720, height: 486)
        .foregroundStyle(palette.text)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .tint(palette.accent)
        .onAppear { searchIsFocused = true }
        .onChange(of: model.mode) { searchIsFocused = true }
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

    private var separator: some View {
        Rectangle().fill(palette.line).frame(height: 1)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image("KnotMenuBar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                Text("Knot").fontWeight(.semibold)
                Text("/").foregroundStyle(palette.muted.opacity(0.5))
                Text(model.mode == .clipboard ? "Clipboard" : "Search")
                Spacer()
                Text("esc")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.muted)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.muted)
                TextField(
                    model.mode == .clipboard ? "Search clipboard history…" : "Search anything…",
                    text: $model.query
                )
                .textFieldStyle(.plain)
                .font(.system(size: 23, weight: .regular))
                .focused($searchIsFocused)
                .accessibilityLabel(model.mode == .clipboard ? "Search clipboard history" : "Search")

                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        searchIsFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private func resultList(_ results: [SearchItem]) -> some View {
        Group {
            if results.isEmpty {
                SearchEmptyState(
                    symbol: model.isLoading ? "sparkle.magnifyingglass" : "magnifyingglass",
                    title: model.isLoading ? "Finding your apps" : "No results",
                    detail: model.isLoading ? "Your shortcuts will be ready in a moment." : "Try an app name, a command, or a quicklink."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            Color.clear.frame(height: 0).id("results-top")
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                if index == 0 || results[index - 1].section != item.section {
                                    sectionHeading(item.section.rawValue)
                                        .padding(.top, index == 0 ? 1 : 9)
                                }
                                ResultRow(item: item, isSelected: index == model.selectedIndex) {
                                    model.selectedIndex = index
                                    model.run(item)
                                }
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: model.selectedIndex) {
                        scrollToSelection(results, proxy: proxy)
                    }
                    .onChange(of: results.first?.id) {
                        proxy.scrollTo("results-top", anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 14)
            .padding(.bottom, 5)
    }

    private func scrollToSelection(_ results: [SearchItem], proxy: ScrollViewProxy) {
        guard results.indices.contains(model.selectedIndex) else { return }
        proxy.scrollTo(results[model.selectedIndex].id)
    }

    private func clipboardContent(_ results: [SearchItem]) -> some View {
        HStack(spacing: 0) {
            Group {
                if results.isEmpty {
                    SearchEmptyState(
                        symbol: "clipboard",
                        title: model.query.isEmpty ? "Your clipboard, collected" : "No matching items",
                        detail: model.query.isEmpty ? "Copy text or an image to get started." : "Try another word or phrase."
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    ClipboardResultRow(item: item, isSelected: index == model.selectedIndex) {
                                        model.selectedIndex = index
                                    } onActivate: {
                                        model.selectedIndex = index
                                        model.run(item)
                                    } onPin: {
                                        model.togglePin(item)
                                    }
                                    .id(item.id)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: model.selectedIndex) {
                            scrollToSelection(results, proxy: proxy)
                        }
                        .onChange(of: results.first?.id) {
                            if let first = results.first { proxy.scrollTo(first.id, anchor: .top) }
                        }
                    }
                }
            }
            .frame(width: 390)
            Rectangle().fill(palette.line).frame(width: 1)
            ClipboardPreview(entry: model.selectedClipboardEntry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func footer(_ results: [SearchItem]) -> some View {
        let selected = results.indices.contains(model.selectedIndex) ? results[model.selectedIndex] : nil
        return HStack(spacing: 16) {
            Button(action: onShowSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")

            if let message = model.message, model.mode != .clipboard || message != "Search and paste from clipboard history" {
                Text(message).lineLimit(1).help(message)
            } else {
                Text(model.mode == .clipboard ? "Clipboard history" : results.count == 1 ? "1 result" : "\(results.count) results")
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            ShortcutHint(keys: ["↑", "↓"], label: "Navigate")
            if let selected {
                if case .setQuery = selected.action {
                    ShortcutHint(keys: ["⇥"], label: "Complete")
                } else if selected.id.hasPrefix("calculator:") {
                    ShortcutHint(keys: ["↩"], label: nil)
                        .accessibilityLabel("Copy result")
                } else {
                    ShortcutHint(keys: ["↩"], label: model.mode == .clipboard ? "Paste" : "Open")
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 20)
        .frame(height: 42)
        .background(palette.recess)
    }
}

private struct SearchPalette {
    let surface: Color
    let recess: Color
    let text: Color
    let muted: Color
    let line: Color
    let selection: Color
    let hover: Color
    let accent: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        surface = dark ? Color(red: 0.13, green: 0.135, blue: 0.13) : Color(red: 0.975, green: 0.972, blue: 0.961)
        recess = dark ? Color.black.opacity(0.10) : Color.black.opacity(0.018)
        text = dark ? Color(red: 0.94, green: 0.935, blue: 0.91) : Color(red: 0.18, green: 0.19, blue: 0.18)
        muted = dark ? Color(red: 0.60, green: 0.61, blue: 0.58) : Color(red: 0.43, green: 0.45, blue: 0.42)
        line = dark ? Color.white.opacity(0.075) : Color.black.opacity(0.075)
        selection = dark ? Color.white.opacity(0.075) : Color.black.opacity(0.052)
        hover = dark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)
        accent = dark ? Color(red: 0.89, green: 0.64, blue: 0.41) : Color(red: 0.61, green: 0.34, blue: 0.17)
    }
}

private struct SearchRowBackground: ViewModifier {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let palette = SearchPalette(colorScheme)
        content
            .background(isSelected ? palette.selection : isHovered ? palette.hover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 2, height: 16)
                        .padding(.leading, 1)
                        .allowsHitTesting(false)
                }
            }
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var palette: SearchPalette { SearchPalette(colorScheme) }
    private var isCalculation: Bool { item.id.hasPrefix("calculator:") }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                icon
                VStack(alignment: .leading, spacing: isCalculation ? 4 : 3) {
                    if isCalculation {
                        Text("Result")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.muted)
                    }
                    Text(item.title)
                        .font(.system(size: isCalculation ? 32 : 13.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(isCalculation ? 0.5 : 1)
                    if !isCalculation {
                        Text(item.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: isCalculation ? 88 : 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .modifier(SearchRowBackground(isSelected: isSelected))
    }

    private var icon: some View {
        Group {
            if let imageData = item.imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let iconURL = item.iconURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: iconURL.path))
                    .resizable().scaledToFit()
            } else {
                Image(systemName: isCalculation ? "equal" : item.symbol)
                    .font(.system(size: isCalculation ? 22 : 18, weight: .regular))
                    .foregroundStyle(isCalculation ? palette.accent : palette.muted)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

private struct ClipboardResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    let action: () -> Void
    let onActivate: () -> Void
    let onPin: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SearchPalette(colorScheme)
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 11) {
                    Group {
                        if let data = item.imageData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(palette.muted)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(2)
                        Text(item.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .simultaneousGesture(TapGesture(count: 2).onEnded(onActivate))

            Button(action: onPin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(item.isPinned ? palette.accent : palette.muted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(item.isPinned ? "Unpin" : "Pin")
            .accessibilityLabel(item.isPinned ? "Unpin item" : "Pin item")
            .padding(.trailing, 7)
        }
        .modifier(SearchRowBackground(isSelected: isSelected))
    }
}

private struct ClipboardPreview: View {
    let entry: ClipboardEntry?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SearchPalette(colorScheme)
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 14) {
                    if let data = entry.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(entry.value)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    Rectangle().fill(palette.line).frame(height: 1)
                    VStack(alignment: .leading, spacing: 5) {
                        if let sourceName = entry.sourceName {
                            Label(sourceName, systemImage: "app")
                        }
                        Label(entry.copiedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.muted)
                }
                .padding(20)
            } else {
                SearchEmptyState(symbol: "doc.text", title: "Preview", detail: "Select an item to take a closer look.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.recess)
    }
}

private struct SearchEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SearchPalette(colorScheme)
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(palette.muted)
                .padding(.bottom, 4)
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShortcutHint: View {
    let keys: [String]
    let label: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SearchPalette(colorScheme)
        HStack(spacing: 6) {
            if let label { Text(label) }
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .medium))
                        .frame(minWidth: 17, minHeight: 18)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(palette.line, lineWidth: 1)
                        }
                }
            }
        }
    }
}
