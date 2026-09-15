import CoreServices
import Foundation
import XCTest

final class ApplicationDirectoryMonitorTests: XCTestCase {
    private let roots = [URL(fileURLWithPath: "/Applications")]

    func testAppInstallRemovalAndRenameTriggerRefresh() {
        for flag in [kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved, kFSEventStreamEventFlagItemRenamed] {
            XCTAssertTrue(needsRefresh("/Applications/New.app", flag | kFSEventStreamEventFlagItemIsDir))
        }
    }

    func testMovedNestedFolderTriggersRefresh() {
        XCTAssertTrue(needsRefresh("/Applications/Vendor/Tools", kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemIsDir))
    }

    func testOrdinaryFileAndResourceWritesDoNotTriggerRefresh() {
        XCTAssertFalse(needsRefresh("/Applications/readme.txt", kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile))
        XCTAssertFalse(needsRefresh("/Applications/Existing.app/Contents/Resources/image.png", kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile))
        XCTAssertFalse(needsRefresh("/Applications/Existing.app/Contents/Resources/new-folder", kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir))
    }

    func testMetadataWrittenAfterBundleCreationTriggersRefresh() {
        XCTAssertTrue(needsRefresh("/Applications/New.app/Contents/Info.plist", kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile))
        XCTAssertTrue(needsRefresh("/Applications/New.app/Contents/Resources/zh.lproj/InfoPlist.strings", kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile))
    }

    func testEventsOutsideSearchRootsAreIgnored() {
        XCTAssertFalse(needsRefresh("/Applications Elsewhere/New.app", kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir))
        XCTAssertFalse(needsRefresh("/Users/example/Desktop/New.app", kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir))
    }

    func testDroppedEventsAndRootChangesForceRescan() {
        for flag in [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped, kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged] {
            XCTAssertTrue(needsRefresh("/Applications", flag))
        }
    }

    func testSymlinkAliasesAreNormalizedLikeWatchedRoots() {
        let canonicalRoot = URL(fileURLWithPath: "/tmp").standardizedFileURL.resolvingSymlinksInPath()
        XCTAssertTrue(ApplicationDirectoryMonitor.shouldRefresh(
            path: "/private/tmp/New.app",
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir),
            roots: [canonicalRoot]
        ))
    }

    func testRemovedApplicationPathStillMatchesSymlinkAliasedRoot() throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent("knot-monitor-test-\(UUID().uuidString)")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        let removed = temporary.appendingPathComponent("AlreadyRemoved.app")
        try manager.createDirectory(at: removed, withIntermediateDirectories: true)
        try manager.removeItem(at: removed)
        let root = temporary.standardizedFileURL.resolvingSymlinksInPath()
        let privatePath = root.path.hasPrefix("/var/") ? "/private" + root.path : root.path

        XCTAssertTrue(ApplicationDirectoryMonitor.shouldRefresh(
            path: privatePath + "/AlreadyRemoved.app",
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemIsDir),
            roots: [root]
        ))
    }

    private func needsRefresh(_ path: String, _ flags: Int) -> Bool {
        ApplicationDirectoryMonitor.shouldRefresh(path: path, flags: FSEventStreamEventFlags(flags), roots: roots)
    }
}
