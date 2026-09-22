import CoreGraphics
import Foundation
import XCTest

@MainActor
final class WindowTargetResolverTests: XCTestCase {
    private let sourcePID: pid_t = 42
    private let knotPID: pid_t = 99

    func testApplicationFocusedWindowDoesNotRequireSystemFocus() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(1, pid: sourcePID)
        access.focusedWindows[sourcePID] = 1
        let resolver = WindowTargetResolver(access: access)

        resolver.capture(applicationPID: sourcePID)
        let target = try XCTUnwrap(resolver.resolve())

        XCTAssertEqual(target.window, 1)
        XCTAssertEqual(target.frame, access.frames[1])
        XCTAssertEqual(access.lookups, [.focused(sourcePID)])
    }

    func testSystemFocusedWindowFallsBackOnlyWithinCapturedApplication() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(2, pid: sourcePID)
        access.systemWindow = 2
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID, canReadWindows: false)

        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 2)
        XCTAssertEqual(access.lookups, [.focused(sourcePID), .system])
    }

    func testMainWindowIsUsedWhenBothFocusedLookupsAreMissing() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(3, pid: sourcePID)
        access.mainWindows[sourcePID] = 3
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID, canReadWindows: false)

        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 3)
        XCTAssertEqual(access.lookups, [.focused(sourcePID), .system, .main(sourcePID)])
    }

    func testEveryLookupRejectsWindowsOwnedByAnotherProcess() {
        let access = FakeWindowTargetAccess()
        access.addWindow(1, pid: knotPID)
        access.addWindow(2, pid: knotPID)
        access.addWindow(3, pid: knotPID)
        access.focusedWindows[sourcePID] = 1
        access.systemWindow = 2
        access.mainWindows[sourcePID] = 3
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID, canReadWindows: false)

        XCTAssertNil(resolver.resolve())
        XCTAssertEqual(access.lookups, [.focused(sourcePID), .system, .main(sourcePID)])
        XCTAssertTrue(access.frameReads.isEmpty)
    }

    func testUnknownWindowProcessIsRejectedBeforeReadingItsFrame() throws {
        let access = FakeWindowTargetAccess()
        access.frames[1] = CGRect(x: 0, y: 0, width: 600, height: 400)
        access.focusedWindows[sourcePID] = 1
        access.addWindow(2, pid: sourcePID)
        access.mainWindows[sourcePID] = 2
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID, canReadWindows: false)

        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 2)
        XCTAssertEqual(access.frameReads, [2])
    }

    func testFailedCaptureRetriesOriginalApplicationAfterKnotGetsFocus() throws {
        let access = FakeWindowTargetAccess()
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID)
        XCTAssertNil(resolver.resolve())

        // Opening the search panel changes system focus, not the captured PID.
        access.addWindow(9, pid: knotPID)
        access.systemWindow = 9
        access.focusedWindows[knotPID] = 9
        access.addWindow(4, pid: sourcePID)
        access.mainWindows[sourcePID] = 4
        access.lookups.removeAll()

        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 4)
        XCTAssertEqual(access.lookups, [.focused(sourcePID), .system, .main(sourcePID)])
    }

    func testCachedWindowRemainsTheTargetAndItsFrameIsReadAgain() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(1, pid: sourcePID)
        access.focusedWindows[sourcePID] = 1
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID)

        access.addWindow(2, pid: sourcePID)
        access.focusedWindows[sourcePID] = 2
        access.systemWindow = 2
        let updatedFrame = CGRect(x: -1_200, y: 40, width: 700, height: 900)
        access.frames[1] = updatedFrame
        access.lookups.removeAll()
        access.frameReads.removeAll()

        let target = try XCTUnwrap(resolver.resolve())
        XCTAssertEqual(target.window, 1)
        XCTAssertEqual(target.frame, updatedFrame)
        XCTAssertTrue(access.lookups.isEmpty)
        XCTAssertEqual(access.frameReads, [1])
    }

    func testUnreadableCachedWindowIsReplacedWithinCapturedApplication() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(1, pid: sourcePID)
        access.focusedWindows[sourcePID] = 1
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID)

        access.frames[1] = nil
        access.addWindow(2, pid: sourcePID)
        access.focusedWindows[sourcePID] = 2
        access.lookups.removeAll()
        access.frameReads.removeAll()

        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 2)
        XCTAssertEqual(access.lookups, [.focused(sourcePID)])
        XCTAssertEqual(access.frameReads, [1, 2])
    }

    func testCachedWindowWhoseProcessCannotBeVerifiedIsDiscarded() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(1, pid: sourcePID)
        access.focusedWindows[sourcePID] = 1
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID)

        access.processIdentifiers[1] = nil
        access.focusedWindows[sourcePID] = nil
        access.addWindow(2, pid: sourcePID)
        access.mainWindows[sourcePID] = 2

        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 2)
    }

    func testNewCaptureDiscardsThePreviousApplicationsCachedWindow() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(1, pid: sourcePID)
        access.focusedWindows[sourcePID] = 1
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID)

        access.addWindow(2, pid: knotPID)
        access.focusedWindows[knotPID] = 2
        resolver.capture(applicationPID: knotPID)

        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 2)
    }

    func testMissingOrInvalidCapturedPIDClearsOldTargetWithoutAXLookups() {
        for invalidPID: pid_t? in [nil, 0, -1] {
            let access = FakeWindowTargetAccess()
            access.addWindow(1, pid: sourcePID)
            access.focusedWindows[sourcePID] = 1
            let resolver = WindowTargetResolver(access: access)
            resolver.capture(applicationPID: sourcePID)
            access.lookups.removeAll()
            access.frameReads.removeAll()

            resolver.capture(applicationPID: invalidPID)

            XCTAssertNil(resolver.resolve())
            XCTAssertTrue(access.lookups.isEmpty)
            XCTAssertTrue(access.frameReads.isEmpty)
        }
    }

    func testCaptureWithoutPermissionDefersAXReadsButRemembersPID() throws {
        let access = FakeWindowTargetAccess()
        access.addWindow(1, pid: sourcePID)
        access.focusedWindows[sourcePID] = 1
        let resolver = WindowTargetResolver(access: access)
        resolver.capture(applicationPID: sourcePID)

        access.addWindow(2, pid: knotPID)
        access.focusedWindows[knotPID] = 2
        access.lookups.removeAll()
        access.frameReads.removeAll()
        resolver.capture(applicationPID: knotPID, canReadWindows: false)
        XCTAssertTrue(access.lookups.isEmpty)
        XCTAssertTrue(access.frameReads.isEmpty)

        // Permission becomes available after another app has gained focus.
        access.systemWindow = 1
        XCTAssertEqual(try XCTUnwrap(resolver.resolve()).window, 2)
        XCTAssertEqual(access.lookups, [.focused(knotPID)])
    }

    func testInvalidFramesAreRejected() {
        let invalidFrames: [CGRect] = [
            .zero,
            CGRect(x: 10, y: 10, width: 0, height: 400),
            CGRect(x: 10, y: 10, width: 600, height: 0),
            CGRect(x: 10, y: 10, width: -600, height: 400),
            CGRect(x: 10, y: 10, width: 600, height: -400),
            CGRect(x: CGFloat.nan, y: 10, width: 600, height: 400),
            CGRect(x: 10, y: CGFloat.nan, width: 600, height: 400),
            CGRect(x: CGFloat.infinity, y: 10, width: 600, height: 400),
            CGRect(x: 10, y: -CGFloat.infinity, width: 600, height: 400),
            CGRect(x: 10, y: 10, width: CGFloat.nan, height: 400),
            CGRect(x: 10, y: 10, width: 600, height: CGFloat.nan),
            CGRect(x: 10, y: 10, width: CGFloat.infinity, height: 400),
            CGRect(x: 10, y: 10, width: 600, height: CGFloat.infinity),
            .null
        ]
        for frame in invalidFrames {
            let access = FakeWindowTargetAccess()
            access.addWindow(1, pid: sourcePID, frame: frame)
            access.focusedWindows[sourcePID] = 1
            let resolver = WindowTargetResolver(access: access)
            resolver.capture(applicationPID: sourcePID, canReadWindows: false)

            XCTAssertNil(resolver.resolve(), "Unexpectedly accepted frame: \(frame)")
        }
    }
}

@MainActor
private final class FakeWindowTargetAccess: WindowTargetAccess {
    enum Lookup: Equatable {
        case focused(pid_t)
        case system
        case main(pid_t)
    }

    var focusedWindows: [pid_t: Int] = [:]
    var mainWindows: [pid_t: Int] = [:]
    var systemWindow: Int?
    var processIdentifiers: [Int: pid_t] = [:]
    var frames: [Int: CGRect] = [:]
    var lookups: [Lookup] = []
    var frameReads: [Int] = []

    func addWindow(_ window: Int, pid: pid_t, frame: CGRect = CGRect(x: 80, y: 50, width: 600, height: 400)) {
        processIdentifiers[window] = pid
        frames[window] = frame
    }

    func window(for applicationPID: pid_t, attribute: WindowTargetAttribute) -> Int? {
        switch attribute {
        case .focused:
            lookups.append(.focused(applicationPID))
            return focusedWindows[applicationPID]
        case .main:
            lookups.append(.main(applicationPID))
            return mainWindows[applicationPID]
        }
    }

    func systemFocusedWindow() -> Int? {
        lookups.append(.system)
        return systemWindow
    }

    func processIdentifier(of window: Int) -> pid_t? {
        processIdentifiers[window]
    }

    func frame(of window: Int) -> CGRect? {
        frameReads.append(window)
        return frames[window]
    }
}

final class WindowGeometryTests: XCTestCase {
    private let visible = CGRect(x: -1_281, y: 31, width: 1_281, height: 801)
    private let current = CGRect(x: -1_000, y: 80, width: 601, height: 401)

    func testLeftAndRightHalvesTileOddWidthWithoutGaps() {
        let left = WindowGeometry.frame(for: .leftHalf, current: current, visible: visible)
        let right = WindowGeometry.frame(for: .rightHalf, current: current, visible: visible)

        XCTAssertEqual(left, CGRect(x: -1_281, y: 31, width: 640, height: 801))
        XCTAssertEqual(right, CGRect(x: -641, y: 31, width: 641, height: 801))
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.union(right), visible)
    }

    func testTopAndBottomHalvesUseAXCoordinatesAndTileOddHeight() {
        let top = WindowGeometry.frame(for: .topHalf, current: current, visible: visible)
        let bottom = WindowGeometry.frame(for: .bottomHalf, current: current, visible: visible)

        XCTAssertEqual(top, CGRect(x: -1_281, y: 31, width: 1_281, height: 400))
        XCTAssertEqual(bottom, CGRect(x: -1_281, y: 431, width: 1_281, height: 401))
        XCTAssertEqual(top.maxY, bottom.minY)
        XCTAssertEqual(top.union(bottom), visible)
    }

    func testMaximizeUsesVisibleBoundsIncludingScreenOffsets() {
        XCTAssertEqual(WindowGeometry.frame(for: .maximize, current: current, visible: visible), visible)
    }

    func testCenterPreservesWindowSizeWhenItFits() {
        let centered = WindowGeometry.frame(for: .center, current: current, visible: visible)

        XCTAssertEqual(centered, CGRect(x: -941, y: 231, width: 601, height: 401))
        XCTAssertEqual(centered.size, current.size)
        XCTAssertEqual(centered.midX, visible.midX)
        XCTAssertEqual(centered.midY, visible.midY)
    }

    func testCenterClampsOversizedWindowToVisibleBounds() {
        let oversized = CGRect(x: 500, y: 500, width: 2_000, height: 1_500)

        XCTAssertEqual(WindowGeometry.frame(for: .center, current: oversized, visible: visible), visible)
    }
}
