import XCTest
@testable import OnePercent
@testable import OnePercentCore
import OnePercentTestSupport

final class HoverStateMachineTests: XCTestCase {
    func testExpandsImmediatelyWhenCursorEnters() {
        var state = HoverStateMachine()

        XCTAssertEqual(state.update(pointerIsInside: true), [.show])
        XCTAssertTrue(state.isExpanded)
        XCTAssertFalse(state.isCloseScheduled)
    }

    func testReentryCancelsThePendingCloseWithoutHiding() {
        var state = HoverStateMachine()
        _ = state.update(pointerIsInside: true)
        XCTAssertEqual(state.update(pointerIsInside: false), [.scheduleHide])

        XCTAssertEqual(state.update(pointerIsInside: true), [.cancelScheduledHide])
        XCTAssertEqual(state.closeDelayElapsed(), [])
        XCTAssertTrue(state.isExpanded)
    }

    func testLeavingThenWaitingClosesThePanel() {
        var state = HoverStateMachine()
        _ = state.update(pointerIsInside: true)
        XCTAssertEqual(state.update(pointerIsInside: false), [.scheduleHide])

        XCTAssertEqual(state.closeDelayElapsed(), [.hide])
        XCTAssertFalse(state.isExpanded)
    }

    @MainActor
    func testHoverMonitorInteractionLockPreventsPrematureClose() {
        let monitor = HoverMonitor(closeDelay: 0.05)
        var hideCalled = false
        monitor.onHide = { hideCalled = true }
        monitor.forceExpanded()
        monitor.setInteractionLocked(true)

        monitor.evaluateCurrentMouseLocation()
        XCTAssertFalse(hideCalled)
    }
}

// MARK: - Open delay

@MainActor
final class HoverOpenDelayTests: XCTestCase {
    private let zone = NSRect(x: 100, y: 900, width: 200, height: 40)
    private var pointer = NSPoint(x: 0, y: 0)
    private var shows = 0

    private func makeMonitor(openDelay: TimeInterval) -> HoverMonitor {
        let monitor = HoverMonitor(closeDelay: 0.05, openDelay: openDelay, pointerLocation: { [unowned self] in self.pointer })
        monitor.onShow = { [unowned self] in self.shows += 1 }
        monitor.update(activationRect: zone, interactiveRect: zone)
        return monitor
    }

    private func wait(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testWithoutADelayTheStatePanelOpensAtOnce() {
        let monitor = makeMonitor(openDelay: 0)
        pointer = NSPoint(x: 150, y: 920)
        monitor.evaluateCurrentMouseLocation()
        XCTAssertEqual(shows, 1)
    }

    func testTheOpenDelayHoldsTheShowBackUntilItElapses() async {
        let monitor = makeMonitor(openDelay: 0.12)
        pointer = NSPoint(x: 150, y: 920)
        monitor.evaluateCurrentMouseLocation()
        XCTAssertEqual(shows, 0)

        await wait(0.3)
        XCTAssertEqual(shows, 1)
    }

    func testLeavingBeforeTheDelayCancelsTheOpen() async {
        let monitor = makeMonitor(openDelay: 0.15)
        pointer = NSPoint(x: 150, y: 920)
        monitor.evaluateCurrentMouseLocation()
        await wait(0.04)

        pointer = NSPoint(x: 600, y: 100)
        monitor.evaluateCurrentMouseLocation()
        await wait(0.3)

        XCTAssertEqual(shows, 0)
    }

    func testLingeringKeepsASingleScheduledOpen() async {
        let monitor = makeMonitor(openDelay: 0.1)
        pointer = NSPoint(x: 150, y: 920)
        for _ in 0..<5 { monitor.evaluateCurrentMouseLocation() }
        await wait(0.3)
        XCTAssertEqual(shows, 1)
    }

    func testChangingTheDelayAppliesToTheNextVisit() {
        let monitor = makeMonitor(openDelay: 0.5)
        monitor.openDelay = 0
        pointer = NSPoint(x: 150, y: 920)
        monitor.evaluateCurrentMouseLocation()
        XCTAssertEqual(shows, 1)
    }
}

// MARK: - Holding the panel open while a menu is showing

@MainActor
final class HoverHoldOpenTests: XCTestCase {
    private let zone = NSRect(x: 100, y: 900, width: 200, height: 40)
    private var pointer = NSPoint(x: 150, y: 920)
    private var shows = 0
    private var hides = 0

    private func makeMonitor() -> HoverMonitor {
        let monitor = HoverMonitor(closeDelay: 0.05, openDelay: 0, pointerLocation: { [unowned self] in self.pointer })
        monitor.onShow = { [unowned self] in self.shows += 1 }
        monitor.onHide = { [unowned self] in self.hides += 1 }
        monitor.update(activationRect: zone, interactiveRect: zone)
        return monitor
    }

    private func wait(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testAMenuOpenOutsideThePanelDoesNotCloseIt() async {
        let monitor = makeMonitor()
        monitor.evaluateCurrentMouseLocation()          // opens
        XCTAssertEqual(shows, 1)

        monitor.setHeldOpen(true)                       // a menu begins tracking
        pointer = NSPoint(x: 600, y: 100)               // pointer travels down into the menu, outside the panel
        monitor.evaluateCurrentMouseLocation()
        await wait(0.25)

        XCTAssertEqual(hides, 0)
    }

    func testClosingTheMenuWithThePointerStillOutsideClosesThePanel() async {
        let monitor = makeMonitor()
        monitor.evaluateCurrentMouseLocation()
        monitor.setHeldOpen(true)
        pointer = NSPoint(x: 600, y: 100)
        monitor.evaluateCurrentMouseLocation()

        monitor.setHeldOpen(false)
        await wait(0.25)

        XCTAssertEqual(hides, 1)
    }

    func testClosingTheMenuWithThePointerBackInsideKeepsThePanel() async {
        let monitor = makeMonitor()
        monitor.evaluateCurrentMouseLocation()
        monitor.setHeldOpen(true)
        pointer = NSPoint(x: 150, y: 920)

        monitor.setHeldOpen(false)
        await wait(0.25)

        XCTAssertEqual(hides, 0)
    }

    func testHoldingOpenNeverOpensAClosedPanel() {
        pointer = NSPoint(x: 600, y: 100)               // starts away from the notch, panel closed
        let monitor = makeMonitor()
        XCTAssertEqual(shows, 0)
        monitor.setHeldOpen(true)                       // e.g. the menu bar item's own menu
        monitor.evaluateCurrentMouseLocation()
        XCTAssertEqual(shows, 0)

        pointer = NSPoint(x: 150, y: 920)
        monitor.evaluateCurrentMouseLocation()
        XCTAssertEqual(shows, 0, "even with the pointer on the notch, a held monitor stays shut")
    }

    func testAHideAlreadyScheduledIsCancelledWhenTheMenuOpens() async {
        let monitor = makeMonitor()
        monitor.evaluateCurrentMouseLocation()
        pointer = NSPoint(x: 600, y: 100)
        monitor.evaluateCurrentMouseLocation()          // pointer left: hide scheduled
        monitor.setHeldOpen(true)                       // menu appears before the delay runs out
        await wait(0.25)
        XCTAssertEqual(hides, 0)
    }
}

final class InteractionLockTests: XCTestCase {
    func testKeyboardAndMenuLocksAreIndependent() {
        var lock = InteractionLock()
        XCTAssertFalse(lock.isKeyboardLocked)
        lock.keyboard = true
        XCTAssertTrue(lock.isKeyboardLocked)
        lock.menuTrackingDepth = 1
        XCTAssertTrue(lock.isMenuHolding)
        lock.keyboard = false
        XCTAssertFalse(lock.isKeyboardLocked)
        XCTAssertTrue(lock.isMenuHolding, "closing the keyboard lock must not release a menu")
    }

    func testNestedMenusAreCounted() {
        var lock = InteractionLock()
        lock.menuDidBeginTracking()
        lock.menuDidBeginTracking()      // a submenu
        lock.menuDidEndTracking()
        XCTAssertTrue(lock.isMenuHolding)
        lock.menuDidEndTracking()
        XCTAssertFalse(lock.isMenuHolding)
    }

    func testUnbalancedEndNeverGoesNegative() {
        var lock = InteractionLock()
        lock.menuDidEndTracking()
        lock.menuDidEndTracking()
        lock.menuDidBeginTracking()
        XCTAssertTrue(lock.isMenuHolding)
    }
}
