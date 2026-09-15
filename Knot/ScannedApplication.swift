import Foundation

struct ScannedApplication: Hashable, Sendable {
    let title: String
    let url: URL
    let aliases: [String]
}
