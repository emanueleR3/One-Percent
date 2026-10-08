import XCTest
@testable import OnePercent

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
