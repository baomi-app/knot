import Foundation
import XCTest

final class AppScannerTests: XCTestCase {
    func testScanFindsApplicationInstalledAfterFirstScanAndRemovesUninstalledApplication() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = await AppScanner.scan(roots: [root])
        XCTAssertTrue(before.isEmpty)

        let installed = try makeApplication(at: root.appendingPathComponent("New Fixture.app"))
        let afterInstall = await AppScanner.scan(roots: [root])
        XCTAssertEqual(afterInstall.map { $0.url.lastPathComponent }, [installed.lastPathComponent])

        try FileManager.default.removeItem(at: installed)
        let afterUninstall = await AppScanner.scan(roots: [root])
        XCTAssertTrue(afterUninstall.isEmpty)
    }

    func testScanFindsNestedApplicationsButNotEmbeddedHelpers() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let application = try makeApplication(at: root.appendingPathComponent("Utilities/Nested Fixture.app"))
        _ = try makeApplication(at: application.appendingPathComponent("Contents/Helpers/Hidden Helper.app"))

        let results = await AppScanner.scan(roots: [root])
        XCTAssertEqual(results.map { $0.url.lastPathComponent }, ["Nested Fixture.app"])
    }

    func testRootCreatedAfterStartupIsIncludedOnNextScan() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = root.appendingPathComponent("Applications")
        let before = await AppScanner.scan(roots: [applications])
        XCTAssertTrue(before.isEmpty)
        _ = try makeApplication(at: applications.appendingPathComponent("Later Fixture.app"))
        let after = await AppScanner.scan(roots: [applications])
        XCTAssertEqual(after.count, 1)
    }

    func testNewApplicationRetainsBundleAndTransliterationAliases() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApplication(
            at: root.appendingPathComponent("网易爆米花.app"),
            identifier: "com.example.baomi",
            name: "网易爆米花"
        )
        let results = await AppScanner.scan(roots: [root])
        let application = try XCTUnwrap(results.first)
        XCTAssertTrue(application.aliases.contains("baomi"))
        XCTAssertTrue(application.aliases.contains("com.example.baomi"))
        XCTAssertTrue(application.aliases.contains("wangyibaomihua"))
    }

    func testMetadataArrivingAfterBundleDirectoryIsPickedUpOnRefresh() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("Delayed Fixture.app")
        try FileManager.default.createDirectory(at: application.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let before = await AppScanner.scan(roots: [root])
        XCTAssertFalse(before.first?.aliases.contains("latebundle") == true)
        _ = try makeApplication(at: application, identifier: "org.knot.latebundle")
        let after = await AppScanner.scan(roots: [root])
        XCTAssertTrue(after.first?.aliases.contains("latebundle") == true)
    }

    private func temporaryRoot() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnotAppScannerTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeApplication(at url: URL, identifier: String = "org.knot.tests.fixture", name: String = "Fixture") throws -> URL {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }
}
