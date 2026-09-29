import Combine
import XCTest

final class KnotBarVisibilityPolicyTests: XCTestCase {
    private let ownBundleIdentifier = "app.baomi.knot"

    func testNewApplicationIsAllowedUntilItsMenuBarPlacementIsKnown() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: ["app.visible", "app.hidden"],
            hidden: ["app.hidden"],
            ownBundleIdentifier: ownBundleIdentifier
        )
        let refreshed = policy.updatingRunningApplications(["app.visible", "app.hidden", "app.new"])

        XCTAssertTrue(refreshed.allowed.contains("app.new"))
        XCTAssertTrue(refreshed.allowed.contains("app.visible"))
        XCTAssertFalse(refreshed.allowed.contains("app.hidden"))
        XCTAssertEqual(refreshed.hidden, ["app.hidden"])
    }

    func testNewApplicationToTheLeftIsHiddenWithoutRevealingExistingHiddenItems() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: ["app.visible", "app.hidden"],
            hidden: ["app.hidden"],
            ownBundleIdentifier: ownBundleIdentifier
        )
        let running: Set<String> = ["app.visible", "app.hidden", "app.new"]
        let afterLaunch = policy.updatingRunningApplications(running)
        // The collapsed AX snapshot contains the new item, but omits app.hidden.
        let afterMenuBarItemAppears = afterLaunch.updatingRunningApplications(
            running,
            newlyHidden: ["app.new"]
        )

        XCTAssertEqual(afterMenuBarItemAppears.hidden, ["app.hidden", "app.new"])
        XCTAssertFalse(afterMenuBarItemAppears.allowed.contains("app.new"))
        XCTAssertFalse(afterMenuBarItemAppears.allowed.contains("app.hidden"))
        XCTAssertTrue(afterMenuBarItemAppears.allowed.contains("app.visible"))
    }

    func testDelayedMenuBarItemIsHiddenWhenInitialHiddenSectionWasEmpty() {
        let running: Set<String> = ["app.visible", "app.delayed"]
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: running,
            hidden: [],
            ownBundleIdentifier: ownBundleIdentifier
        )
        // The process was already running at collapse time; creating its item
        // later does not produce another running-applications notification.
        let refreshed = policy.updatingRunningApplications(running, newlyHidden: ["app.delayed"])

        XCTAssertEqual(refreshed.hidden, ["app.delayed"])
        XCTAssertFalse(refreshed.allowed.contains("app.delayed"))
        XCTAssertTrue(refreshed.allowed.contains("app.visible"))
    }

    func testNewApplicationToTheRightStaysVisibleAfterMenuBarRefresh() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: ["app.hidden"],
            hidden: ["app.hidden"],
            ownBundleIdentifier: ownBundleIdentifier
        )
        let refreshed = policy.updatingRunningApplications(
            ["app.hidden", "app.new.visible"],
            newlyHidden: []
        )

        XCTAssertTrue(refreshed.allowed.contains("app.new.visible"))
        XCTAssertEqual(refreshed.hidden, ["app.hidden"])
    }

    func testNewlyHiddenApplicationStaysHiddenAcrossFurtherScansAndRelaunch() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: ["app.visible"],
            hidden: [],
            ownBundleIdentifier: ownBundleIdentifier
        )
        let afterLaunch = policy.updatingRunningApplications(
            ["app.visible", "app.new"],
            newlyHidden: ["app.new"]
        )
        let afterExit = afterLaunch.updatingRunningApplications(["app.visible"])
        let afterRelaunch = afterExit.updatingRunningApplications(["app.visible", "app.new"])

        XCTAssertEqual(afterRelaunch, afterLaunch)
        XCTAssertFalse(afterRelaunch.allowed.contains("app.new"))
    }

    func testMenuBarRefreshCannotHideKnotOrSystemApplications() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: [ownBundleIdentifier, "com.apple.controlcenter"],
            hidden: [],
            ownBundleIdentifier: ownBundleIdentifier
        )
        let refreshed = policy.updatingRunningApplications(
            [ownBundleIdentifier, "com.apple.controlcenter", "app.new"],
            newlyHidden: [ownBundleIdentifier, "com.apple.controlcenter", "app.new"]
        )

        XCTAssertEqual(refreshed.hidden, ["app.new"])
        XCTAssertTrue(refreshed.allowed.contains(ownBundleIdentifier))
        XCTAssertTrue(refreshed.allowed.contains("com.apple.controlcenter"))
    }

    func testHiddenApplicationKeepsClassificationAcrossExitAndRelaunch() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: ["app.visible", "app.hidden"],
            hidden: ["app.hidden"],
            ownBundleIdentifier: ownBundleIdentifier
        )
        let afterExit = policy.updatingRunningApplications(["app.visible"])
        let afterRelaunch = afterExit.updatingRunningApplications(["app.visible", "app.hidden"])

        XCTAssertEqual(afterExit.hidden, ["app.hidden"])
        XCTAssertFalse(afterRelaunch.allowed.contains("app.hidden"))
        XCTAssertEqual(afterRelaunch, policy)
    }

    func testTerminatedVisibleApplicationIsRemovedFromAllowlist() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: ["app.visible", "app.hidden"],
            hidden: ["app.hidden"],
            ownBundleIdentifier: ownBundleIdentifier
        )
        let refreshed = policy.updatingRunningApplications(["app.hidden"])

        XCTAssertFalse(refreshed.allowed.contains("app.visible"))
        XCTAssertTrue(refreshed.allowed.contains(ownBundleIdentifier))
        XCTAssertTrue(refreshed.allowed.contains("com.apple.systemuiserver"))
    }

    func testKnotAndSystemApplicationsCannotBecomeHidden() {
        let policy = KnotBarVisibilityPolicy(
            runningBundleIdentifiers: [ownBundleIdentifier, "com.apple.controlcenter", "app.hidden"],
            hidden: [ownBundleIdentifier, "com.apple.controlcenter", "app.hidden"],
            ownBundleIdentifier: ownBundleIdentifier
        )

        XCTAssertEqual(policy.hidden, ["app.hidden"])
        XCTAssertTrue(policy.allowed.contains(ownBundleIdentifier))
        XCTAssertTrue(policy.allowed.contains("com.apple.controlcenter"))
    }
}

@MainActor
final class KnotBarUpdateSchedulerTests: XCTestCase {
    private final class Preferences {
        @Published var isEnabled = true
        @Published var separatorsHidden = false
    }

    func testPublishedChangesApplyTogetherAfterTheirSettersFinish() async {
        let preferences = Preferences()
        let scheduler = KnotBarUpdateScheduler()
        var observations: [(Bool, Bool)] = []
        let subscription = Publishers.CombineLatest(preferences.$isEnabled, preferences.$separatorsHidden)
            .dropFirst()
            .sink { _ in
                scheduler.schedule {
                    observations.append((preferences.isEnabled, preferences.separatorsHidden))
                }
            }

        preferences.isEnabled = false
        preferences.separatorsHidden = true
        XCTAssertTrue(observations.isEmpty)
        await nextMainQueueTurn()

        XCTAssertEqual(observations.count, 1)
        XCTAssertFalse(observations.first?.0 ?? true)
        XCTAssertTrue(observations.first?.1 ?? false)
        withExtendedLifetime(subscription) {}
    }

    func testCancellationPreventsStoppedControllerUpdatesAndAllowsRestart() async {
        let scheduler = KnotBarUpdateScheduler()
        var calls = 0
        scheduler.schedule { calls += 1 }
        scheduler.cancel()
        scheduler.schedule { calls += 10 }
        await nextMainQueueTurn()

        XCTAssertEqual(calls, 10)
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
final class KnotBarMenuBarMonitorTests: XCTestCase {
    private func snapshot(_ hidden: String) -> KnotBarVisibilityPolicy {
        KnotBarVisibilityPolicy(
            runningBundleIdentifiers: ["app.visible", hidden],
            hidden: [hidden],
            ownBundleIdentifier: "app.baomi.knot"
        )
    }

    func testBurstOfChangesIsCoalescedIntoOneRead() async {
        let didRead = expectation(description: "coalesced read")
        var reads = 0
        let expected = snapshot("app.hidden")
        let monitor = KnotBarMenuBarMonitor(
            timing: .init(debounce: 0.01, retries: [], fallback: 60),
            read: { reads += 1; return expected },
            onRead: { result in
                XCTAssertEqual(result, expected)
                didRead.fulfill()
            }
        )
        monitor.start()
        for _ in 0..<20 { monitor.layoutMayHaveChanged() }
        await fulfillment(of: [didRead], timeout: 2)
        monitor.stop()

        XCTAssertEqual(reads, 1)
    }

    func testChangesDuringSlowReadDiscardOldResultAndScheduleOnlyOneFollowup() async {
        let readStarted = expectation(description: "first read suspended")
        let didRead = expectation(description: "latest result")
        var pending: CheckedContinuation<KnotBarVisibilityPolicy?, Never>?
        var reads = 0
        var delivered: [KnotBarVisibilityPolicy?] = []
        let old = snapshot("app.old")
        let latest = snapshot("app.latest")
        let monitor = KnotBarMenuBarMonitor(
            timing: .init(debounce: 0, retries: [], fallback: 60),
            read: {
                reads += 1
                if reads == 1 {
                    return await withCheckedContinuation { continuation in
                        pending = continuation
                        readStarted.fulfill()
                    }
                }
                return latest
            },
            onRead: { result in delivered.append(result); didRead.fulfill() }
        )
        monitor.start()
        await fulfillment(of: [readStarted], timeout: 2)
        // The main actor remains available while the reader is suspended.
        for _ in 0..<20 { monitor.layoutMayHaveChanged() }
        XCTAssertEqual(reads, 1)
        pending?.resume(returning: old)
        await fulfillment(of: [didRead], timeout: 2)
        monitor.stop()

        XCTAssertEqual(reads, 2)
        XCTAssertEqual(delivered, [latest])
    }

    func testStopAndRestartCannotApplyPreviousCollapseResult() async {
        let readStarted = expectation(description: "old session suspended")
        let didRead = expectation(description: "new session result")
        var pending: CheckedContinuation<KnotBarVisibilityPolicy?, Never>?
        var reads = 0
        var delivered: [KnotBarVisibilityPolicy?] = []
        let old = snapshot("app.old")
        let latest = snapshot("app.latest")
        let monitor = KnotBarMenuBarMonitor(
            timing: .init(debounce: 0, retries: [], fallback: 60),
            read: {
                reads += 1
                if reads == 1 {
                    return await withCheckedContinuation { continuation in
                        pending = continuation
                        readStarted.fulfill()
                    }
                }
                return latest
            },
            onRead: { result in delivered.append(result); didRead.fulfill() }
        )
        monitor.start()
        await fulfillment(of: [readStarted], timeout: 2)
        monitor.stop()
        monitor.start()
        XCTAssertEqual(reads, 1)
        pending?.resume(returning: old)
        await fulfillment(of: [didRead], timeout: 2)
        monitor.stop()

        XCTAssertEqual(reads, 2)
        XCTAssertEqual(delivered, [latest])
    }

    func testStopDiscardsInFlightResultAndCancelsRetriesAndFallback() async {
        let readStarted = expectation(description: "read suspended")
        let unwantedRead = expectation(description: "no result after reveal")
        unwantedRead.isInverted = true
        var pending: CheckedContinuation<KnotBarVisibilityPolicy?, Never>?
        var reads = 0
        let value = snapshot("app.hidden")
        let monitor = KnotBarMenuBarMonitor(
            timing: .init(debounce: 0, retries: [0.05, 0.1], fallback: 0.1),
            read: {
                reads += 1
                return await withCheckedContinuation { continuation in
                    pending = continuation
                    readStarted.fulfill()
                }
            },
            onRead: { _ in unwantedRead.fulfill() }
        )
        monitor.start()
        await fulfillment(of: [readStarted], timeout: 2)
        monitor.stop()
        pending?.resume(returning: value)
        await fulfillment(of: [unwantedRead], timeout: 0.25)

        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(reads, 1)
    }

    func testShortRetriesFinishAndOnlyFallbackContinues() async {
        let burst = expectation(description: "initial read and two retries")
        burst.expectedFulfillmentCount = 3
        let fallback = expectation(description: "low frequency fallback")
        var reads = 0
        let value = snapshot("app.hidden")
        let monitor = KnotBarMenuBarMonitor(
            timing: .init(debounce: 0, retries: [0.1, 0.2], fallback: 0.6),
            read: { reads += 1; return value },
            onRead: { _ in
                if reads <= 3 { burst.fulfill() }
                else { fallback.fulfill() }
            }
        )
        monitor.start()
        await fulfillment(of: [burst], timeout: 2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reads, 3)
        await fulfillment(of: [fallback], timeout: 2)
        monitor.stop()

        XCTAssertEqual(reads, 4)
    }
}
