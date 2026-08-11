import Combine
import Foundation

@MainActor
final class ClipboardSettingsStore: ObservableObject {
    static let shared = ClipboardSettingsStore()

    @Published private(set) var historyLimit: Int
    @Published private(set) var retentionDays: Int
    @Published private(set) var excludedBundleIDs: Set<String>

    private enum Key {
        static let historyLimit = "clipboardHistoryLimit"
        static let retentionDays = "clipboardRetentionDays"
        static let exclusions = "clipboardExcludedBundleIDs"
    }

    private init() {
        let savedLimit = UserDefaults.standard.integer(forKey: Key.historyLimit)
        historyLimit = [25, 50, 100, 250].contains(savedLimit) ? savedLimit : 100

        let savedRetention = UserDefaults.standard.object(forKey: Key.retentionDays) as? Int
        retentionDays = savedRetention ?? 30

        let savedExclusions = UserDefaults.standard.stringArray(forKey: Key.exclusions)
        excludedBundleIDs = Set(savedExclusions ?? Array(Self.defaultExclusions))
    }

    func setHistoryLimit(_ value: Int) {
        guard [25, 50, 100, 250].contains(value) else { return }
        historyLimit = value
        UserDefaults.standard.set(value, forKey: Key.historyLimit)
    }

    func setRetentionDays(_ value: Int) {
        guard [0, 1, 7, 30, 90].contains(value) else { return }
        retentionDays = value
        UserDefaults.standard.set(value, forKey: Key.retentionDays)
    }

    func addExclusion(_ bundleID: String) {
        let clean = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBundleID(clean) else { return }
        excludedBundleIDs.insert(clean)
        saveExclusions()
    }

    func removeExclusion(_ bundleID: String) {
        excludedBundleIDs.remove(bundleID)
        saveExclusions()
    }

    func restoreDefaultExclusions() {
        excludedBundleIDs = Self.defaultExclusions
        saveExclusions()
    }

    func isValidBundleID(_ value: String) -> Bool {
        value.contains(".") && !value.contains(where: { $0.isWhitespace })
    }

    private func saveExclusions() {
        UserDefaults.standard.set(excludedBundleIDs.sorted(), forKey: Key.exclusions)
    }

    private static let defaultExclusions: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.Passwords",
        "com.bitwarden.desktop",
        "com.enpass.Enpass",
        "com.lastpass.LastPass",
        "org.keepassxc.keepassxc"
    ]
}

