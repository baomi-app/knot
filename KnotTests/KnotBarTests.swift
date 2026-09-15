import Combine
import XCTest

final class KnotBarVisibilityPolicyTests: XCTestCase {
    private let ownBundleIdentifier = "app.baomi.knot"

    func testNewApplicationIsAllowedWhileExistingHiddenApplicationStaysHidden() {
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
