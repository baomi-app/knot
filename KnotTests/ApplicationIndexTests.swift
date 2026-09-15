import Combine
import Foundation
import XCTest

@MainActor
final class ApplicationIndexTests: XCTestCase {
    func testStartScansOnceAndPublishesApplications() async {
        let scanner = ControlledApplicationScanner()
        let index = ApplicationIndex { await scanner.scan() }
        XCTAssertTrue(index.isLoading)
        index.start()
        index.start()
        await scanner.waitForCallCount(1)
        XCTAssertTrue(index.applications.isEmpty)

        let applications = [application("First")]
        let changed = expectation(description: "Initial applications published")
        let observation = index.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in changed.fulfill() }
        scanner.complete(call: 1, with: applications)
        await fulfillment(of: [changed], timeout: 2)

        XCTAssertEqual(index.applications, applications)
        XCTAssertEqual(scanner.callCount, 1)
        XCTAssertFalse(index.isLoading)
        withExtendedLifetime(observation) {}
        index.stop()
    }

    func testRefreshKeepsExistingApplicationsUntilReplacementIsReady() async {
        let scanner = ControlledApplicationScanner()
        let index = ApplicationIndex { await scanner.scan() }
        let old = [application("Old")]
        index.start()
        await scanner.waitForCallCount(1)
        await complete(scanner, call: 1, with: old, in: index)

        index.refresh()
        await scanner.waitForCallCount(2)
        XCTAssertEqual(index.applications, old)
        XCTAssertFalse(index.isLoading)

        let replacement = [application("New")]
        await complete(scanner, call: 2, with: replacement, in: index)
        XCTAssertEqual(index.applications, replacement)
        index.stop()
    }

    func testRefreshRequestsDuringScanCoalesceIntoOneAdditionalScan() async {
        let scanner = ControlledApplicationScanner()
        let index = ApplicationIndex { await scanner.scan() }
        index.start()
        await scanner.waitForCallCount(1)
        for _ in 0..<20 { index.refresh() }
        XCTAssertEqual(scanner.callCount, 1)

        scanner.complete(call: 1, with: [application("Before install")])
        await scanner.waitForCallCount(2)
        await complete(scanner, call: 2, with: [application("After install")], in: index)

        XCTAssertEqual(scanner.callCount, 2)
        XCTAssertEqual(scanner.maximumConcurrentScans, 1)
        XCTAssertEqual(index.applications.map(\.title), ["After install"])
        index.stop()
    }

    func testStopDiscardsLateResultsAndRefreshWhileStoppedDoesNothing() async {
        let scanner = ControlledApplicationScanner()
        let index = ApplicationIndex { await scanner.scan() }
        index.start()
        await scanner.waitForCallCount(1)
        index.refresh()
        index.stop()
        index.refresh()

        let published = expectation(description: "Stopped index does not publish late results")
        published.isInverted = true
        let observation = index.$applications.dropFirst().sink { _ in published.fulfill() }

        // This mock deliberately ignores Task cancellation, like a synchronous
        // filesystem operation that is already running on a detached task.
        scanner.complete(call: 1, with: [application("Stale")])
        await fulfillment(of: [published], timeout: 0.1)
        XCTAssertTrue(index.applications.isEmpty)
        XCTAssertFalse(index.isLoading)
        XCTAssertEqual(scanner.callCount, 1)
        withExtendedLifetime(observation) {}
    }

    func testRestartWaitsForCancelledScanThenRejectsItsResults() async {
        let scanner = ControlledApplicationScanner()
        let index = ApplicationIndex { await scanner.scan() }
        index.start()
        await scanner.waitForCallCount(1)
        index.stop()
        index.start()
        index.refresh()
        XCTAssertEqual(scanner.callCount, 1)

        scanner.complete(call: 1, with: [application("Old generation")])
        await scanner.waitForCallCount(2)
        XCTAssertTrue(index.applications.isEmpty)
        XCTAssertTrue(index.isLoading)

        await complete(scanner, call: 2, with: [application("Current generation")], in: index)
        XCTAssertEqual(index.applications.map(\.title), ["Current generation"])
        XCTAssertEqual(scanner.callCount, 2)
        XCTAssertEqual(scanner.maximumConcurrentScans, 1)
        index.stop()
    }

    func testRefreshCanPublishAnEmptyListAfterUninstall() async {
        let scanner = ControlledApplicationScanner()
        let index = ApplicationIndex { await scanner.scan() }
        index.start()
        await scanner.waitForCallCount(1)
        await complete(scanner, call: 1, with: [application("Removed")], in: index)
        index.refresh()
        await scanner.waitForCallCount(2)
        await complete(scanner, call: 2, with: [], in: index)
        XCTAssertTrue(index.applications.isEmpty)
        index.stop()
    }

    private func application(_ title: String) -> ScannedApplication {
        ScannedApplication(title: title, url: URL(fileURLWithPath: "/Applications/\(title).app"), aliases: [])
    }

    private func complete(
        _ scanner: ControlledApplicationScanner,
        call: Int,
        with applications: [ScannedApplication],
        in index: ApplicationIndex
    ) async {
        let changed = expectation(description: "Applications published for scan \(call)")
        let observation = index.$applications.dropFirst().filter { $0 == applications }.prefix(1)
            .sink { _ in changed.fulfill() }
        scanner.complete(call: call, with: applications)
        await fulfillment(of: [changed], timeout: 2)
        withExtendedLifetime(observation) {}
    }

}

@MainActor
private final class ControlledApplicationScanner {
    private(set) var callCount = 0
    private(set) var maximumConcurrentScans = 0
    private var pending: [Int: CheckedContinuation<[ScannedApplication], Never>] = [:]
    private var callWaiters: [(Int, XCTestExpectation)] = []

    func scan() async -> [ScannedApplication] {
        callCount += 1
        let call = callCount
        return await withCheckedContinuation { continuation in
            pending[call] = continuation
            maximumConcurrentScans = max(maximumConcurrentScans, pending.count)
            let ready = callWaiters.filter { $0.0 <= callCount }
            callWaiters.removeAll { $0.0 <= callCount }
            ready.forEach { $0.1.fulfill() }
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        let started = XCTestExpectation(description: "Scan \(count) started")
        callWaiters.append((count, started))
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(result, .completed)
    }

    func complete(call: Int, with applications: [ScannedApplication]) {
        guard let continuation = pending.removeValue(forKey: call) else {
            XCTFail("No pending scan for call \(call)")
            return
        }
        continuation.resume(returning: applications)
    }
}
