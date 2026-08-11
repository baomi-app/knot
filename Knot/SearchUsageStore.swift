import Foundation

@MainActor
final class SearchUsageStore {
    private let defaultsKey = "searchUsageCounts"
    private var counts: [String: Int]

    init() {
        counts = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] ?? [:]
    }

    func record(_ item: SearchItem) {
        let key = usageKey(for: item)
        counts[key, default: 0] = min(counts[key, default: 0] + 1, 100)
        UserDefaults.standard.set(counts, forKey: defaultsKey)
    }

    func weight(for item: SearchItem) -> Int {
        min(counts[usageKey(for: item), default: 0] * 3, 30)
    }

    private func usageKey(for item: SearchItem) -> String {
        guard item.id.hasPrefix("quicklink:") else { return item.id }
        return item.id.split(separator: ":", maxSplits: 2).prefix(2).joined(separator: ":")
    }
}

