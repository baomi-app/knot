import AppKit
import Combine
import Foundation

enum SearchMode: Sendable {
    case root
    case clipboard
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet {
            selectedIndex = 0
            scheduleFileSearch()
        }
    }
    @Published var selectedIndex = 0
    @Published var isLoading = true
    @Published var message: String?
    @Published private(set) var mode: SearchMode = .root
    var onRequestClose: (() -> Void)?

    @Published private var applications: [SearchItem] = []
    @Published private var fileItems: [SearchItem] = []
    private let clipboardMonitor = ClipboardMonitor.shared
    private let quicklinkStore = QuicklinkStore.shared
    private let captureHistoryStore = CaptureHistoryStore.shared
    private let usageStore = SearchUsageStore()
    private var cancellables = Set<AnyCancellable>()
    private var fileSearchTask: Task<Void, Never>?
    private var pasteTargetApplication: NSRunningApplication?

    init() {
        quicklinkStore.$links
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        captureHistoryStore.$entries
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var results: [SearchItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .clipboard {
            let entries = clipboardItems
            guard !needle.isEmpty else { return entries }
            return entries.filter {
                $0.title.localizedCaseInsensitiveContains(needle)
                    || $0.subtitle.localizedCaseInsensitiveContains(needle)
            }
        }
        if fileSearchTerm != nil {
            return Array(fileItems.prefix(16))
        }
        let all = calculatorItems + primaryCommandItems + fileCommandItems + barItems + windowItems + captureItems + quicklinkItems + applications
        guard !needle.isEmpty else {
            let capture = captureItems.first.map { [$0] } ?? []
            let links = quicklinkItems.sorted { usageStore.weight(for: $0) > usageStore.weight(for: $1) }
            return Array((primaryCommandItems + capture + links).prefix(8))
        }

        return all.compactMap { item -> (SearchItem, Int)? in
            if item.id.hasPrefix("calculator:") {
                return (item, 200)
            }
            guard let score = Self.score(item: item, query: needle) else { return nil }
            return (item, score + usageStore.weight(for: item))
        }
        .sorted {
            if $0.1 == $1.1 { return $0.0.title < $1.0.title }
            return $0.1 > $1.1
        }
        .prefix(9)
        .map(\.0)
    }

    func start() {
        clipboardMonitor.onChange = { [weak self] in self?.selectedIndex = 0 }
        clipboardMonitor.start()
        Task {
            applications = await AppScanner.scan()
            isLoading = false
        }
    }

    func stop() {
        fileSearchTask?.cancel()
        clipboardMonitor.stop()
    }

    func resetQuery() {
        query = ""
        selectedIndex = 0
    }

    func prepare(mode: SearchMode) {
        self.mode = mode
        query = ""
        selectedIndex = 0
        message = mode == .clipboard ? "Search and paste from clipboard history" : nil
    }

    func requestClose() {
        onRequestClose?()
    }

    var selectedClipboardEntry: ClipboardEntry? {
        guard mode == .clipboard,
              results.indices.contains(selectedIndex),
              case .pasteClipboard(let entryID) = results[selectedIndex].action else {
            return nil
        }
        return clipboardMonitor.entries.first(where: { $0.id == entryID })
    }

    func capturePasteTarget(_ application: NSRunningApplication?) {
        pasteTargetApplication = application?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil
            : application
    }

    func togglePin(_ item: SearchItem) {
        guard case .pasteClipboard(let entryID) = item.action else { return }
        clipboardMonitor.togglePinned(entryID: entryID)
        message = item.isPinned ? "Removed from pinned items" : "Pinned clipboard item"
    }

    func moveSelection(by offset: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + offset + count) % count
    }

    func runSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        run(results[selectedIndex])
    }

    @discardableResult
    func acceptSelectedSuggestion() -> Bool {
        guard results.indices.contains(selectedIndex),
              case .setQuery = results[selectedIndex].action else {
            return false
        }
        run(results[selectedIndex])
        return true
    }

    func run(_ item: SearchItem) {
        if case .setQuery = item.action {
        } else {
            usageStore.record(item)
        }
        switch item.action {
        case .openApplication(let url):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .copy(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            message = "Copied to clipboard"
        case .pasteClipboard(let entryID):
            guard clipboardMonitor.writeToPasteboard(entryID: entryID) else {
                message = "Clipboard item is no longer available"
                return
            }
            if ClipboardPasteCoordinator.paste(to: pasteTargetApplication) {
                onRequestClose?()
            } else {
                message = "Copied. Allow Accessibility access to paste directly."
            }
        case .clearClipboardHistory:
            clipboardMonitor.clear()
            message = "Clipboard history cleared"
        case .clearCaptureHistory:
            captureHistoryStore.clear()
            message = "Capture history cleared. Screenshot files were kept."
        case .openCaptureFolder:
            NSWorkspace.shared.open(captureHistoryStore.ensureCaptureDirectory())
        case .openClipboardHistory:
            prepare(mode: .clipboard)
        case .toggleBar:
            KnotBarController.shared.toggle()
            message = KnotBarController.shared.isCollapsed ? "Menu bar items hidden" : "Menu bar items revealed"
        case .manageWindow(let action):
            message = WindowManager.perform(action).message
        case .capture(let action):
            message = "Starting capture"
            onRequestClose?()
            Task {
                message = await CaptureManager.perform(action).message
            }
        case .setQuery(let value):
            query = value
        }
    }

    private var primaryCommandItems: [SearchItem] {
        [
            SearchItem(
                id: "command:clipboard-history",
                title: "Clipboard History",
                subtitle: "Search and paste copied text and images",
                section: .suggested,
                symbol: "clipboard",
                action: .openClipboardHistory
            )
        ]
    }

    private var fileCommandItems: [SearchItem] {
        [
            SearchItem(
                id: "command:search-files",
                title: "Search Files",
                subtitle: "Search file names with Spotlight",
                section: .suggested,
                symbol: "doc.text.magnifyingglass",
                action: .setQuery("file ")
            )
        ]
    }

    private var barItems: [SearchItem] {
        let isCollapsed = KnotBarController.shared.isCollapsed
        return [
            SearchItem(
                id: "command:toggle-menu-bar",
                title: isCollapsed ? "Show Menu Bar Items" : "Hide Menu Bar Items",
                subtitle: isCollapsed ? "Reveal items managed by Knot Bar" : "Hide items managed by Knot Bar",
                section: .suggested,
                symbol: isCollapsed ? "chevron.right" : "chevron.left",
                action: .toggleBar
            )
        ]
    }

    private var quicklinkItems: [SearchItem] {
        quicklinkStore.links.compactMap { link in
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmedQuery.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            let typedKeyword = parts.first.map(String.init)?.localizedLowercase
            let argument = parts.count > 1 ? String(parts[1]) : ""
            let usesArgument = link.urlTemplate.contains("{query}")

            if usesArgument, typedKeyword == link.keyword.localizedLowercase, !argument.isEmpty {
                guard let url = expandedURL(for: link, argument: argument) else { return nil }
                return SearchItem(
                    id: "quicklink:\(link.id):\(argument)",
                    title: "\(link.title): \(argument)",
                    subtitle: trimmedQuery,
                    section: .quicklinks,
                    symbol: "arrow.up.right.square",
                    aliases: [link.keyword],
                    action: .openURL(url)
                )
            }

            if usesArgument {
                return SearchItem(
                    id: "quicklink:\(link.id)",
                    title: link.title,
                    subtitle: "Type \(link.keyword) followed by your query",
                    section: .quicklinks,
                    symbol: "link",
                    aliases: [link.keyword],
                    action: .setQuery("\(link.keyword) ")
                )
            }

            guard let url = URL(string: link.urlTemplate) else { return nil }
            return SearchItem(
                id: "quicklink:\(link.id)",
                title: link.title,
                subtitle: "\(link.keyword)  \(url.host() ?? link.urlTemplate)",
                section: .quicklinks,
                symbol: "link",
                aliases: [link.keyword],
                action: .openURL(url)
            )
        }
    }

    private func expandedURL(for link: Quicklink, argument: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = argument.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: link.urlTemplate.replacingOccurrences(of: "{query}", with: encoded))
    }

    private var windowItems: [SearchItem] {
        WindowAction.allCases.map { action in
            SearchItem(
                id: "window:\(action.rawValue)",
                title: action.rawValue,
                subtitle: action.subtitle,
                section: .suggested,
                symbol: action.symbol,
                action: .manageWindow(action)
            )
        }
    }

    private var clipboardItems: [SearchItem] {
        clipboardMonitor.entries.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.copiedAt > $1.copiedAt
        }.map { entry in
            let textTitle = entry.value.replacingOccurrences(of: "\n", with: " ")
            let title = entry.isImage ? "Clipboard Image" : String(textTitle.prefix(90))
            let source = entry.sourceName.map { "Copied from \($0)" } ?? "Clipboard history"
            return SearchItem(
                id: "clipboard:\(entry.id)",
                title: title,
                subtitle: entry.isPinned ? "Pinned · \(source)" : source,
                section: .clipboard,
                symbol: entry.isImage ? "photo" : "clipboard",
                imageData: entry.imageData,
                isPinned: entry.isPinned,
                action: .pasteClipboard(entry.id)
            )
        }
    }

    private var captureItems: [SearchItem] {
        let actions = CaptureAction.availableActions.map { action in
            SearchItem(
                id: "capture:\(action.rawValue)",
                title: action.rawValue,
                subtitle: action.subtitle,
                section: .suggested,
                symbol: action.symbol,
                action: .capture(action)
            )
        }
        let history = captureHistoryStore.entries.map { entry in
            SearchItem(
                id: "capture-history:\(entry.id)",
                title: entry.fileURL.lastPathComponent,
                subtitle: entry.action.rawValue,
                section: .captures,
                symbol: "photo",
                iconURL: entry.fileURL,
                action: .openURL(entry.fileURL)
            )
        }
        let utilities = [
            SearchItem(
                id: "capture:open-folder",
                title: "Open Capture Folder",
                subtitle: captureHistoryStore.captureDirectoryURL.path,
                section: .captures,
                symbol: "folder",
                iconURL: captureHistoryStore.captureDirectoryURL,
                action: .openCaptureFolder
            ),
            SearchItem(
                id: "capture:clear-history",
                title: "Clear Capture History",
                subtitle: "Remove the index but keep screenshot files",
                section: .captures,
                symbol: "trash",
                action: .clearCaptureHistory
            )
        ]
        return actions + utilities + history
    }

    private var calculatorItems: [SearchItem] {
        guard let value = Calculator.evaluate(query) else { return [] }
        return [
            SearchItem(
                id: "calculator:\(query)",
                title: value,
                subtitle: "Copy calculation result",
                section: .suggested,
                symbol: "function",
                action: .copy(value)
            )
        ]
    }

    private func scheduleFileSearch() {
        fileSearchTask?.cancel()
        fileItems = []
        guard let term = fileSearchTerm, term.count >= 2 else { return }

        fileSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            let items = await FileSearch.search(query: term)
            guard !Task.isCancelled, self?.fileSearchTerm == term else {
                return
            }
            self?.fileItems = items
        }
    }

    private var fileSearchTerm: String? {
        guard query.range(of: "file ", options: [.anchored, .caseInsensitive]) != nil else {
            return nil
        }
        return String(query.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func score(item: SearchItem, query: String) -> Int? {
        let needle = query.localizedLowercase
        let title = item.title.localizedLowercase
        let subtitle = item.subtitle.localizedLowercase
        let aliases = item.aliases.map(\.localizedLowercase)

        if aliases.contains(needle) { return 180 }
        if title == needle { return 120 }
        if subtitle == needle { return 110 }
        if title.hasPrefix(needle) { return 100 }

        let titleWords = words(in: title)
        if initials(of: titleWords) == needle { return 95 }
        if titleWords.contains(where: { $0.hasPrefix(needle) }) { return 90 }

        // Very short queries are usually aliases or abbreviations. Broad substring
        // matching makes `gh` match right, Spotlight, and highlight, which is noise.
        guard needle.count >= 3 else { return nil }

        if aliases.contains(where: { $0.hasPrefix(needle) }) { return 85 }
        if words(in: subtitle).contains(where: { $0.hasPrefix(needle) }) { return 80 }
        if title.contains(needle) { return 70 }
        if subtitle.contains(needle) { return 60 }
        if isSubsequence(needle, of: title) { return 40 }
        if isSubsequence(needle, of: subtitle) { return 30 }
        return nil
    }

    private static func words(in value: String) -> [String] {
        value.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func initials(of words: [String]) -> String {
        String(words.compactMap(\.first))
    }

    private static func isSubsequence(_ needle: String, of value: String) -> Bool {
        var cursor = value.startIndex
        for character in needle {
            guard cursor < value.endIndex,
                  let index = value[cursor...].firstIndex(of: character) else { return false }
            cursor = value.index(after: index)
        }
        return true
    }
}
