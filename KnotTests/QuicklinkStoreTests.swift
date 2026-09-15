import Foundation
import XCTest

final class QuicklinkStoreTests: XCTestCase {
    @MainActor
    func testDefaultsAreCreatedOnlyWhenFileIsMissing() throws {
        try withStorage { url in
            let store = QuicklinkStore(storageURL: url)
            XCTAssertEqual(Set(store.links.map(\.keyword)), ["g", "gh"])
            XCTAssertEqual(QuicklinkStore(storageURL: url).links, store.links)
        }
    }

    @MainActor
    func testDeletingEveryLinkStaysEmptyAfterRestart() throws {
        try withStorage { url in
            let store = QuicklinkStore(storageURL: url)
            for link in store.links { store.remove(id: link.id) }
            XCTAssertTrue(QuicklinkStore(storageURL: url).links.isEmpty)
            XCTAssertEqual(try JSONDecoder().decode([Quicklink].self, from: Data(contentsOf: url)), [])
        }
    }

    @MainActor
    func testMalformedExistingFileIsNotOverwrittenDuringInitialization() throws {
        try withStorage { url in
            let data = Data("not valid json".utf8)
            try data.write(to: url)
            XCTAssertTrue(QuicklinkStore(storageURL: url).links.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    @MainActor
    func testRemovingLegacyChatGPTDoesNotRestoreOtherDefaults() throws {
        try withStorage { url in
            let legacy = Quicklink(title: "ChatGPT", urlTemplate: "https://chatgpt.com", keyword: "chat")
            try JSONEncoder().encode([legacy]).write(to: url)
            XCTAssertTrue(QuicklinkStore(storageURL: url).links.isEmpty)
            XCTAssertTrue(QuicklinkStore(storageURL: url).links.isEmpty)
        }
    }

    @MainActor
    func testExistingLinksKeepTheirIdentity() throws {
        try withStorage { url in
            let link = Quicklink(title: "Example", urlTemplate: "https://example.com", keyword: "example")
            try JSONEncoder().encode([link]).write(to: url)
            XCTAssertEqual(QuicklinkStore(storageURL: url).links, [link])
        }
    }

    @MainActor
    func testAddingAfterMalformedLoadPreservesOriginalOnce() throws {
        try withStorage { url in
            let original = Data("damaged configuration".utf8)
            try original.write(to: url)
            let store = QuicklinkStore(storageURL: url)
            XCTAssertNotNil(store.persistenceMessage)

            let first = try XCTUnwrap(store.add())
            let recovery = try XCTUnwrap(store.recoveryURL)
            XCTAssertEqual(try Data(contentsOf: recovery), original)
            XCTAssertEqual(store.links, [first])
            XCTAssertEqual(QuicklinkStore(storageURL: url).links, store.links)
            XCTAssertTrue(try XCTUnwrap(store.persistenceMessage).contains(recovery.path))

            let second = try XCTUnwrap(store.add())
            XCTAssertTrue(store.update(id: first.id, title: "Updated", urlTemplate: "https://example.com/updated", keyword: "updated"))
            XCTAssertTrue(store.remove(id: second.id))
            XCTAssertEqual(store.recoveryURL, recovery)
            XCTAssertEqual(try recoveryFiles(beside: url).map(\.lastPathComponent), [recovery.lastPathComponent])
            XCTAssertEqual(try Data(contentsOf: recovery), original)
            XCTAssertEqual(QuicklinkStore(storageURL: url).links, store.links)
        }
    }

    @MainActor
    func testImportingAfterMalformedLoadPreservesOriginal() throws {
        try withStorage { url in
            let original = Data("damaged configuration".utf8)
            try original.write(to: url)
            let store = QuicklinkStore(storageURL: url)
            let imported = Quicklink(title: "Imported", urlTemplate: "https://example.com/imported", keyword: "imported")
            let document = QuicklinkTransferDocument(format: "knot.quicklinks", version: 1, links: [imported])
            let data = try JSONEncoder().encode(document)

            XCTAssertEqual(store.importData(data), QuicklinkImportResult(imported: 1, skipped: 0))
            let recovery = try XCTUnwrap(store.recoveryURL)
            XCTAssertEqual(try Data(contentsOf: recovery), original)
            XCTAssertEqual(store.links, [imported])
            XCTAssertEqual(QuicklinkStore(storageURL: url).links, [imported])
            XCTAssertEqual(store.importData(data), QuicklinkImportResult(imported: 0, skipped: 1))
            XCTAssertEqual(try recoveryFiles(beside: url).map(\.lastPathComponent), [recovery.lastPathComponent])
        }
    }

    @MainActor
    func testFailedBackupRejectsAddAndStillProtectsOriginalOnRetry() throws {
        try withStorage { url in
            let original = Data("damaged configuration".utf8)
            try original.write(to: url)
            let fileManager = QuicklinkFailureFileManager()
            fileManager.rejectCopies = true
            let store = QuicklinkStore(storageURL: url, fileManager: fileManager)

            XCTAssertNil(store.add())
            XCTAssertNil(store.add())
            XCTAssertTrue(store.links.isEmpty)
            XCTAssertNil(store.recoveryURL)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertNotNil(store.persistenceMessage)

            fileManager.rejectCopies = false
            let link = try XCTUnwrap(store.add())
            XCTAssertEqual(link.keyword, "link")
            XCTAssertEqual(store.links, [link])
            let recovery = try XCTUnwrap(store.recoveryURL)
            XCTAssertEqual(try Data(contentsOf: recovery), original)
            XCTAssertEqual(try recoveryFiles(beside: url).map(\.lastPathComponent), [recovery.lastPathComponent])
        }
    }

    @MainActor
    func testFailedBackupRejectsImportWithoutClaimingImportedLinks() throws {
        try withStorage { url in
            let original = Data("damaged configuration".utf8)
            try original.write(to: url)
            let fileManager = QuicklinkFailureFileManager()
            fileManager.rejectCopies = true
            let store = QuicklinkStore(storageURL: url, fileManager: fileManager)
            let link = Quicklink(title: "Imported", urlTemplate: "https://example.com", keyword: "imported")
            let data = try JSONEncoder().encode(QuicklinkTransferDocument(format: "knot.quicklinks", version: 1, links: [link]))

            XCTAssertNil(store.importData(data))
            XCTAssertTrue(store.links.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertNotNil(store.persistenceMessage)

            fileManager.rejectCopies = false
            XCTAssertEqual(store.importData(data), QuicklinkImportResult(imported: 1, skipped: 0))
            XCTAssertEqual(store.links, [link])
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.recoveryURL)), original)
        }
    }

    @MainActor
    func testFailedSaveDoesNotPublishUnsavedUpdatesOrRemovals() throws {
        try withStorage { url in
            let fileManager = QuicklinkFailureFileManager()
            let store = QuicklinkStore(storageURL: url, fileManager: fileManager)
            let previous = store.links
            let original = try Data(contentsOf: url)
            let first = try XCTUnwrap(previous.first)
            fileManager.rejectDirectoryCreation = true

            XCTAssertFalse(store.update(id: first.id, title: "Unsaved", urlTemplate: "https://example.com", keyword: "unsaved"))
            XCTAssertEqual(store.links, previous)
            XCTAssertFalse(store.remove(id: first.id))
            XCTAssertEqual(store.links, previous)
            XCTAssertNil(store.add())
            XCTAssertEqual(store.links, previous)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertNotNil(store.persistenceMessage)
        }
    }

    private func recoveryFiles(beside url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("quicklinks-recovery-") }
    }

    @MainActor
    private func withStorage(_ test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("KnotQuicklinkTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(directory.appendingPathComponent("quicklinks.json"))
    }
}

private final class QuicklinkFailureFileManager: FileManager, @unchecked Sendable {
    var rejectCopies = false
    var rejectDirectoryCreation = false

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if rejectCopies { throw CocoaError(.fileWriteNoPermission) }
        try super.copyItem(at: srcURL, to: dstURL)
    }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        if rejectDirectoryCreation { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}
