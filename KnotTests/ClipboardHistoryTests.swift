import AppKit
import CryptoKit
import XCTest

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private let key = SymmetricKey(data: Data(repeating: 7, count: 32))

    func testStorageBudgetRetainsPinnedAndNewestEntriesAndRoundTrips() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("history.bin")
            let store = makeStore(at: url, limit: 4_096)
            let now = Date()
            let entries = (0..<5).map { index in
                ClipboardEntry(
                    value: "Line \(index)\n\"quoted\"\\text",
                    imageData: Data(repeating: 255, count: 1_024),
                    copiedAt: now.addingTimeInterval(-Double(index)),
                    sourceBundleID: "test.source",
                    sourceName: "Source",
                    isPinned: index == 4
                )
            }

            let retained = try XCTUnwrap(store.save(entries))
            XCTAssertGreaterThan(retained.count, 0)
            XCTAssertLessThan(retained.count, entries.count)
            XCTAssertEqual(retained.first?.id, entries[4].id)
            XCTAssertTrue(retained.contains { $0.id == entries[0].id })
            XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, 4_096)
            XCTAssertEqual(makeStore(at: url, limit: 4_096).load(), retained)
            XCTAssertNotNil(store.statusMessage)
        }
    }

    func testExactArchiveSizeFitsAndOneByteLessStillProducesValidHistory() throws {
        try withTemporaryDirectory { directory in
            let entry = makeEntry("\tA quoted \"value\" with \\ and a newline\n")
            let reference = directory.appendingPathComponent("reference.bin")
            XCTAssertEqual(makeStore(at: reference).save([entry]), [entry])
            let exactSize = try Data(contentsOf: reference).count

            let exactURL = directory.appendingPathComponent("exact.bin")
            XCTAssertEqual(makeStore(at: exactURL, limit: exactSize).save([entry]), [entry])
            XCTAssertEqual(makeStore(at: exactURL, limit: exactSize).load(), [entry])

            let smallerURL = directory.appendingPathComponent("smaller.bin")
            XCTAssertEqual(makeStore(at: smallerURL, limit: exactSize - 1).save([entry]), [])
            XCTAssertEqual(makeStore(at: smallerURL, limit: exactSize - 1).load(), [])
            XCTAssertLessThanOrEqual(try Data(contentsOf: smallerURL).count, exactSize - 1)
        }
    }

    func testOversizedHistoryIsPreservedOnceBeforeStartingNewArchive() throws {
        try assertUnreadableHistoryIsPreserved(Data(repeating: 17, count: 2_049), limit: 2_048)
    }

    func testCorruptHistoryIsPreservedOnceBeforeStartingNewArchive() throws {
        try assertUnreadableHistoryIsPreserved(Data("not an encrypted archive".utf8), limit: 2_048)
    }

    func testUnavailableKeyCannotOverwriteExistingHistory() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("history.bin")
            let original = makeEntry("Original history")
            XCTAssertEqual(makeStore(at: url).save([original]), [original])
            let originalBytes = try Data(contentsOf: url)

            let lockedStore = ClipboardHistoryStore(historyURL: url, keyProvider: { nil })
            XCTAssertEqual(lockedStore.load(), [])
            XCTAssertNil(lockedStore.save([makeEntry("New copy while key is unavailable")]))
            XCTAssertEqual(try Data(contentsOf: url), originalBytes)
            XCTAssertNotNil(lockedStore.statusMessage)
            XCTAssertEqual(makeStore(at: url).load(), [original])
        }
    }

    func testWrongKeyPreservesOriginalEncryptedBytesForRecovery() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("history.bin")
            _ = makeStore(at: url).save([makeEntry("Original history")])
            let originalBytes = try Data(contentsOf: url)
            let otherKey = SymmetricKey(data: Data(repeating: 9, count: 32))
            let store = ClipboardHistoryStore(historyURL: url, keyProvider: { otherKey })

            XCTAssertEqual(store.load(), [])
            XCTAssertNotNil(store.save([makeEntry("New history")]))
            let recoveryURL = try XCTUnwrap(store.recoveryURL)
            XCTAssertEqual(try Data(contentsOf: recoveryURL), originalBytes)
            // The preserved archive remains decryptable with its original key.
            XCTAssertEqual(makeStore(at: recoveryURL).load().first?.value, "Original history")
        }
    }

    func testFailedRecoveryCopyCannotReplaceOriginalFile() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("history.bin")
            let original = Data("corrupt history that must be kept".utf8)
            try original.write(to: url)
            let key = key
            let store = ClipboardHistoryStore(
                historyURL: url,
                keyProvider: { key },
                fileManager: RejectingRecoveryFileManager()
            )

            XCTAssertEqual(store.load(), [])
            XCTAssertNil(store.save([makeEntry("New clipboard entry")]))
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertNil(store.recoveryURL)
            XCTAssertNotNil(store.statusMessage)
        }
    }

    func testPolicyChangesReadTheNewHistoryLimitAndExclusions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knot-clipboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "knot-clipboard-settings-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ClipboardSettingsStore(defaults: defaults)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = makeStore(at: directory.appendingPathComponent("history.bin"), limit: 32_768)
        _ = store.save((0..<30).map { makeEntry("Item \($0)") })
        let monitor = ClipboardMonitor(pasteboard: pasteboard, store: store, settings: settings)
        monitor.start()
        defer { monitor.stop() }
        XCTAssertEqual(monitor.entries.count, 30)

        let limitApplied = expectation(description: "New history limit applied")
        monitor.onChange = { if monitor.entries.count == 25 { limitApplied.fulfill() } }
        settings.setHistoryLimit(25)
        await fulfillment(of: [limitApplied], timeout: 1)
        XCTAssertEqual(monitor.entries.count, 25)

        let exclusionApplied = expectation(description: "New source exclusion applied")
        monitor.onChange = { if monitor.entries.isEmpty { exclusionApplied.fulfill() } }
        settings.addExclusion("test.source")
        await fulfillment(of: [exclusionApplied], timeout: 1)
        XCTAssertTrue(monitor.entries.isEmpty)
        monitor.onChange = nil
    }

    func testTextCapturePreservesWhitespaceAndIgnoresWhitespaceOnlyCopies() {
        let source = "    return value\n\t"
        XCTAssertEqual(ClipboardEntry.textForHistory(source), source)
        XCTAssertNil(ClipboardEntry.textForHistory(" \n\t "))
        XCTAssertNil(ClipboardEntry.textForHistory(String(repeating: "a", count: ClipboardEntry.maximumTextBytes + 1)))
    }

    func testSearchMatchesFullTextBeyondTheDisplayTitle() {
        let entry = makeEntry(String(repeating: "prefix ", count: 30) + "UNIQUE-TRAILER")
        XCTAssertFalse(String(entry.value.prefix(90)).contains("UNIQUE-TRAILER"))
        XCTAssertTrue(entry.matchesSearch("unique-trailer"))
        XCTAssertTrue(entry.matchesSearch("  unique-trailer  "))
        XCTAssertTrue(entry.matchesSearch("source"))
        XCTAssertFalse(entry.matchesSearch("not present"))
    }

    func testOCRCopyRecordsTextOnceAndRetainsItsOriginalWhitespace() throws {
        try withTemporaryDirectory { directory in
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            let store = makeStore(at: directory.appendingPathComponent("history.bin"))
            let monitor = ClipboardMonitor(pasteboard: pasteboard, store: store)
            let text = "  Recognized text\n"

            XCTAssertTrue(ClipboardService.copyText(text, to: pasteboard, monitor: monitor))
            XCTAssertEqual(pasteboard.string(forType: .string), text)
            XCTAssertEqual(monitor.entries.map(\.value), [text])
            XCTAssertEqual(monitor.entries.first?.sourceName, "Knot OCR")
            XCTAssertTrue(try XCTUnwrap(monitor.entries.first).isKnotCapture)
            monitor.pollNow()
            XCTAssertEqual(monitor.entries.count, 1)
            monitor.togglePinned(entryID: try XCTUnwrap(monitor.entries.first).id)
            XCTAssertTrue(try XCTUnwrap(monitor.entries.first).isPinned)
            XCTAssertEqual(store.load(), monitor.entries)

            XCTAssertTrue(ClipboardService.copyText(text.trimmingCharacters(in: .whitespacesAndNewlines), to: pasteboard, monitor: monitor))
            XCTAssertEqual(monitor.entries.count, 2)
        }
    }

    func testMonitorImmediatelyReflectsThePersistedCapacityLimit() throws {
        try withTemporaryDirectory { directory in
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            let store = makeStore(at: directory.appendingPathComponent("history.bin"), limit: 700)
            let monitor = ClipboardMonitor(pasteboard: pasteboard, store: store)
            for index in 0..<5 {
                XCTAssertTrue(ClipboardService.copyText(
                    "\(index): " + String(repeating: "x", count: 128),
                    to: pasteboard,
                    monitor: monitor
                ))
            }
            XCTAssertFalse(monitor.entries.isEmpty)
            XCTAssertLessThan(monitor.entries.count, 5)
            XCTAssertNotNil(monitor.persistenceMessage)
            XCTAssertEqual(store.load(), monitor.entries)
        }
    }

    func testLegacyEntriesWithoutCaptureMarkerStillDecode() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(makeEntry("legacy"))) as? [String: Any])
        object.removeValue(forKey: "isKnotCapture")
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.isKnotCapture)
        XCTAssertEqual(decoded.value, "legacy")
    }

    private func assertUnreadableHistoryIsPreserved(_ original: Data, limit: Int) throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("history.bin")
            try original.write(to: url)
            let store = makeStore(at: url, limit: limit)
            XCTAssertEqual(store.load(), [])
            XCTAssertNotNil(store.statusMessage)
            XCTAssertEqual(try Data(contentsOf: url), original)

            let first = makeEntry("First new copy")
            XCTAssertEqual(store.save([first]), [first])
            let recoveryURL = try XCTUnwrap(store.recoveryURL)
            XCTAssertEqual(try Data(contentsOf: recoveryURL), original)
            let second = makeEntry("Second new copy")
            XCTAssertEqual(store.save([second]), [second])
            XCTAssertEqual(store.recoveryURL, recoveryURL)
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("clipboard-history-recovery-") }
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(makeStore(at: url, limit: limit).load(), [second])
        }
    }

    private func makeEntry(_ value: String) -> ClipboardEntry {
        ClipboardEntry(value: value, sourceBundleID: "test.source", sourceName: "Source")
    }

    private func makeStore(at url: URL, limit: Int = 4_096) -> ClipboardHistoryStore {
        let key = key
        return ClipboardHistoryStore(historyURL: url, maximumFileBytes: limit, keyProvider: { key })
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knot-clipboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private final class RejectingRecoveryFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
