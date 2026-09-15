import Foundation

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
