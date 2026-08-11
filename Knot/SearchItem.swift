import AppKit
import Foundation

enum SearchSection: String, CaseIterable, Sendable {
    case suggested = "Suggested"
    case applications = "Applications"
    case files = "Files"
    case captures = "Captures"
    case quicklinks = "Quicklinks"
    case clipboard = "Clipboard"
}

enum SearchAction: Hashable, Sendable {
    case openApplication(URL)
    case openURL(URL)
    case copy(String)
    case pasteClipboard(UUID)
    case clearClipboardHistory
    case clearCaptureHistory
    case openCaptureFolder
    case openClipboardHistory
    case toggleBar
    case manageWindow(WindowAction)
    case capture(CaptureAction)
    case setQuery(String)
}

struct SearchItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let section: SearchSection
    let symbol: String
    let aliases: [String]
    let iconURL: URL?
    let imageData: Data?
    let isPinned: Bool
    let action: SearchAction

    init(
        id: String,
        title: String,
        subtitle: String,
        section: SearchSection,
        symbol: String,
        aliases: [String] = [],
        iconURL: URL? = nil,
        imageData: Data? = nil,
        isPinned: Bool = false,
        action: SearchAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.section = section
        self.symbol = symbol
        self.aliases = aliases
        self.iconURL = iconURL
        self.imageData = imageData
        self.isPinned = isPinned
        self.action = action
    }
}

struct Quicklink: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let urlTemplate: String
    let keyword: String

    init(id: UUID = UUID(), title: String, urlTemplate: String, keyword: String) {
        self.id = id
        self.title = title
        self.urlTemplate = urlTemplate
        self.keyword = keyword
    }
}
