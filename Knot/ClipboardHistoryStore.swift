import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct ClipboardEntry: Codable, Identifiable, Hashable, Sendable {
    static let maximumTextBytes = 1 * 1_024 * 1_024
    static let maximumImageBytes = 12 * 1_024 * 1_024

    let id: UUID
    let value: String
    let imageData: Data?
    let copiedAt: Date
    let sourceBundleID: String?
    let sourceName: String?
    let isKnotCapture: Bool
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        value: String,
        imageData: Data? = nil,
        copiedAt: Date = Date(),
        sourceBundleID: String?,
        sourceName: String?,
        isKnotCapture: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.value = value
        self.imageData = imageData
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.isKnotCapture = isKnotCapture
        self.isPinned = isPinned
    }

    var isImage: Bool { imageData != nil }

    var isWithinStorageLimit: Bool {
        value.utf8.count <= Self.maximumTextBytes
            && (imageData.map { $0.count <= Self.maximumImageBytes } ?? true)
    }

    static func textForHistory(_ rawValue: String) -> String? {
        guard rawValue.utf8.count <= maximumTextBytes,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return rawValue
    }

    func matchesSearch(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty
            || value.localizedCaseInsensitiveContains(needle)
            || (sourceName?.localizedCaseInsensitiveContains(needle) ?? false)
            || (isImage && "Clipboard Image".localizedCaseInsensitiveContains(needle))
            || (isPinned && "Pinned".localizedCaseInsensitiveContains(needle))
    }

    private enum CodingKeys: String, CodingKey {
        case id, value, imageData, copiedAt, sourceBundleID, sourceName, isKnotCapture, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        value = try container.decode(String.self, forKey: .value)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        isKnotCapture = try container.decodeIfPresent(Bool.self, forKey: .isKnotCapture) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

@MainActor
final class ClipboardHistoryStore {
    static let maximumHistoryFileBytes = 128 * 1_024 * 1_024
    // AES.GCM's combined representation contains a 12-byte nonce and 16-byte tag.
    private static let encryptionOverheadBytes = 28
    // v2 intentionally leaves the key created by development builds untouched.
    // Its legacy ACL can prompt after switching to a Developer ID release.
    private let keychainService = "app.baomi.knot.clipboard.v2"
    private let keychainAccount = "history-key"
    private let fileManager: FileManager
    private let historyURL: URL
    private let maximumFileBytes: Int
    private let keyProvider: (() -> SymmetricKey?)?
    private var cachedKey: SymmetricKey?
    private var didLoad = false
    private var needsRecoveryCopy = false
    private(set) var recoveryURL: URL?
    private(set) var statusMessage: String?

    init(
        historyURL: URL? = nil,
        maximumFileBytes: Int = ClipboardHistoryStore.maximumHistoryFileBytes,
        keyProvider: (() -> SymmetricKey?)? = nil,
        fileManager: FileManager = .default
    ) {
        self.historyURL = historyURL ?? Self.defaultHistoryURL
        self.maximumFileBytes = maximumFileBytes
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    func load() -> [ClipboardEntry] {
        didLoad = true
        guard fileManager.fileExists(atPath: historyURL.path) else {
            needsRecoveryCopy = false
            return []
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: historyURL.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.int64Value <= Int64(maximumFileBytes) else {
                throw HistoryError.exceedsStorageLimit
            }
            let encrypted = try Data(contentsOf: historyURL)
            guard let key = encryptionKey(createIfMissing: false) else {
                throw HistoryError.keyUnavailable
            }
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            let data = try AES.GCM.open(sealedBox, using: key)
            let entries = try JSONDecoder().decode([ClipboardEntry].self, from: data)
            needsRecoveryCopy = false
            statusMessage = nil
            return entries.filter(\.isWithinStorageLimit)
        } catch {
            needsRecoveryCopy = true
            statusMessage = "Earlier clipboard history could not be read. Its original file has been preserved."
            NSLog("[Knot Clipboard] History could not be loaded; preserving the original: %@", String(describing: error))
            return []
        }
    }

    /// Returns the entries that actually reached disk so the visible list shares
    /// the same capacity policy as the archive loaded at the next launch.
    @discardableResult
    func save(_ entries: [ClipboardEntry]) -> [ClipboardEntry]? {
        if !didLoad { _ = load() }

        do {
            guard let key = encryptionKey(createIfMissing: true) else {
                throw HistoryError.keyUnavailable
            }
            let archive = try boundedArchive(entries)
            let sealedBox = try AES.GCM.seal(archive.data, using: key)
            guard let encrypted = sealedBox.combined,
                  encrypted.count <= maximumFileBytes else {
                throw HistoryError.exceedsStorageLimit
            }
            try fileManager.createDirectory(
                at: historyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try preserveUnreadableArchive()
            try encrypted.write(to: historyURL, options: [.atomic, .completeFileProtection])

            if recoveryURL != nil {
                statusMessage = "Earlier clipboard history could not be read. A recovery copy has been preserved."
            } else if archive.entries.count < entries.count {
                statusMessage = "Clipboard storage is full. Older items were removed to make room."
            } else {
                statusMessage = nil
            }
            return archive.entries
        } catch {
            statusMessage = "Clipboard history could not be saved. Existing history has been preserved."
            NSLog("[Knot Clipboard] History was not saved: %@", String(describing: error))
            return nil
        }
    }

    func clear() {
        if !didLoad { _ = load() }
        do {
            // Explicitly clearing the active history does not delete recovery copies.
            if fileManager.fileExists(atPath: historyURL.path) {
                try preserveUnreadableArchive()
                try fileManager.removeItem(at: historyURL)
            }
            didLoad = true
            statusMessage = nil
        } catch {
            statusMessage = "Clipboard history could not be cleared. Its original file has been preserved."
            NSLog("[Knot Clipboard] History was not cleared: %@", String(describing: error))
        }
    }

    private static var defaultHistoryURL: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Knot", isDirectory: true)
            .appendingPathComponent("clipboard-history.bin")
    }

    private func boundedArchive(_ entries: [ClipboardEntry]) throws -> (data: Data, entries: [ClipboardEntry]) {
        let payloadLimit = maximumFileBytes - Self.encryptionOverheadBytes
        guard payloadLimit >= 2 else { throw HistoryError.exceedsStorageLimit }
        let prioritized = entries.enumerated().sorted {
            if $0.element.isPinned != $1.element.isPinned { return $0.element.isPinned }
            if $0.element.copiedAt != $1.element.copiedAt { return $0.element.copiedAt > $1.element.copiedAt }
            return $0.offset < $1.offset
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = Data("[".utf8)
        var retained: [ClipboardEntry] = []
        for (_, entry) in prioritized where entry.isWithinStorageLimit {
            let encoded = try encoder.encode(entry)
            let separatorBytes = retained.isEmpty ? 0 : 1
            // Reserve the closing bracket as well as the exact encoded payload.
            guard data.count + separatorBytes + encoded.count + 1 <= payloadLimit else { continue }
            if !retained.isEmpty { data.append(contentsOf: ",".utf8) }
            data.append(encoded)
            retained.append(entry)
        }
        data.append(contentsOf: "]".utf8)
        return (data, retained)
    }

    private func preserveUnreadableArchive() throws {
        guard needsRecoveryCopy else { return }
        let destination = historyURL.deletingLastPathComponent()
            .appendingPathComponent("clipboard-history-recovery-\(UUID().uuidString).bin")
        // Copy before replacing. If the copy fails, save must leave the original alone.
        try fileManager.copyItem(at: historyURL, to: destination)
        recoveryURL = destination
        needsRecoveryCopy = false
        NSLog("[Knot Clipboard] Preserved unreadable history as %@", destination.lastPathComponent)
    }

    private enum HistoryError: Error {
        case exceedsStorageLimit
        case keyUnavailable
    }

    private func encryptionKey(createIfMissing: Bool) -> SymmetricKey? {
        if let keyProvider { return keyProvider() }
        if let cachedKey {
            return cachedKey
        }

        let lookup = readKey()
        if let existing = lookup.data {
            let key = SymmetricKey(data: existing)
            cachedKey = key
            return key
        }
        // An inaccessible existing key is not a missing key. Never replace it:
        // doing so would make every archive encrypted with that key unrecoverable.
        guard createIfMissing, lookup.status == errSecItemNotFound else { return nil }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard storeKey(data) else { return nil }
        cachedKey = key
        return key
    }

    private func readKey() -> (data: Data?, status: OSStatus) {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecUseAuthenticationContext: context,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status == errSecSuccess ? result as? Data : nil, status)
    }

    private func storeKey(_ data: Data) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseAuthenticationContext: context,
            kSecValueData: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
