import CryptoKit
import Foundation
import Security

struct ClipboardEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let value: String
    let imageData: Data?
    let copiedAt: Date
    let sourceBundleID: String?
    let sourceName: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        value: String,
        imageData: Data? = nil,
        copiedAt: Date = Date(),
        sourceBundleID: String?,
        sourceName: String?,
        isPinned: Bool = false
    ) {
        self.id = id
        self.value = value
        self.imageData = imageData
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.isPinned = isPinned
    }

    var isImage: Bool { imageData != nil }

    private enum CodingKeys: String, CodingKey {
        case id, value, imageData, copiedAt, sourceBundleID, sourceName, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        value = try container.decode(String.self, forKey: .value)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

@MainActor
final class ClipboardHistoryStore {
    // v2 intentionally leaves the key created by development builds untouched.
    // Its legacy ACL can prompt after switching to a Developer ID release.
    private let keychainService = "app.baomi.knot.clipboard.v2"
    private let keychainAccount = "history-key"
    private let fileManager = FileManager.default
    private var cachedKey: SymmetricKey?

    func load() -> [ClipboardEntry] {
        guard let encrypted = try? Data(contentsOf: historyURL),
              let key = encryptionKey(),
              let sealedBox = try? AES.GCM.SealedBox(combined: encrypted),
              let data = try? AES.GCM.open(sealedBox, using: key),
              let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func save(_ entries: [ClipboardEntry]) {
        guard let key = encryptionKey(),
              let data = try? JSONEncoder().encode(entries),
              let sealedBox = try? AES.GCM.seal(data, using: key),
              let encrypted = sealedBox.combined else {
            return
        }

        try? fileManager.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? encrypted.write(to: historyURL, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        try? fileManager.removeItem(at: historyURL)
    }

    private var historyURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Knot", isDirectory: true)
            .appendingPathComponent("clipboard-history.bin")
    }

    private func encryptionKey() -> SymmetricKey? {
        if let cachedKey {
            return cachedKey
        }

        if let existing = readKey() {
            let key = SymmetricKey(data: existing)
            cachedKey = key
            return key
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard storeKey(data) else { return nil }
        cachedKey = key
        return key
    }

    private func readKey() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func storeKey(_ data: Data) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecDuplicateItem else {
            return status == errSecSuccess
        }

        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail
        ]
        return SecItemUpdate(
            match as CFDictionary,
            [kSecValueData: data] as CFDictionary
        ) == errSecSuccess
    }
}
