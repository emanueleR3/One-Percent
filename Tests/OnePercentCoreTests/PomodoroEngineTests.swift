import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

final class PomodoroEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let task = UUID()
    private var config = PomodoroConfig(focus: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, roundsBeforeLongBreak: 4)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testFocusBlockCountsDown() {
        let s = PomodoroEngine.startFocus(taskID: task, completedBlocks: 0, now: at(0), config: config)
        XCTAssertEqual(s.phase, .focus)
        XCTAssertEqual(s.remaining(at: at(0)), 1_500, accuracy: 0.001)
        XCTAssertEqual(s.remaining(at: at(600)), 900, accuracy: 0.001)
        XCTAssertEqual(s.progress(at: at(750)), 0.5, accuracy: 0.001)
        XCTAssertFalse(s.isFinished(at: at(1_499)))
        XCTAssertTrue(s.isFinished(at: at(1_500)))
        XCTAssertEqual(s.remaining(at: at(5_000)), 0, "never negative")
    }

    func testPausingFreezesTheClockAndResumingContinues() {
        var s = PomodoroEngine.startFocus(taskID: task, completedBlocks: 0, now: at(0), config: config)
        s = PomodoroEngine.pause(s, at: at(600))
        XCTAssertTrue(s.isPaused)
        XCTAssertEqual(s.remaining(at: at(9_000)), 900, accuracy: 0.001, "paused time does not run")
        XCTAssertFalse(s.isFinished(at: at(9_000)))

        s = PomodoroEngine.resume(s, at: at(9_000))
        XCTAssertFalse(s.isPaused)
        XCTAssertEqual(s.remaining(at: at(9_300)), 600, accuracy: 0.001)
    }

    func testPausingTwiceOrResumingARunningBlockChangesNothing() {
        let s = PomodoroEngine.startFocus(taskID: task, completedBlocks: 0, now: at(0), config: config)
        XCTAssertEqual(PomodoroEngine.resume(s, at: at(100)), s)
        let paused = PomodoroEngine.pause(s, at: at(100))
        XCTAssertEqual(PomodoroEngine.pause(paused, at: at(500)), paused)
    }

    func testAFinishedFocusBlockLeadsToAShortBreak() {
        let s = PomodoroEngine.startFocus(taskID: task, completedBlocks: 0, now: at(0), config: config)
        let next = PomodoroEngine.next(after: s, now: at(1_500), config: config)
        XCTAssertEqual(next?.phase, .shortBreak)
        XCTAssertEqual(next?.duration, 300)
        XCTAssertEqual(next?.completedFocusBlocks, 1)
        XCTAssertEqual(next?.taskID, task)
        XCTAssertEqual(next?.startedAt, at(1_500))
    }

    func testEveryFourthBlockEarnsALongBreak() {
        let s = PomodoroEngine.startFocus(taskID: task, completedBlocks: 3, now: at(0), config: config)
        let next = PomodoroEngine.next(after: s, now: at(1_500), config: config)
        XCTAssertEqual(next?.phase, .longBreak)
        XCTAssertEqual(next?.duration, 900)
        XCTAssertEqual(next?.completedFocusBlocks, 4)
    }

    func testTheCycleLengthIsConfigurable() {
        config.roundsBeforeLongBreak = 2
        let s = PomodoroEngine.startFocus(taskID: task, completedBlocks: 1, now: at(0), config: config)
        XCTAssertEqual(PomodoroEngine.next(after: s, now: at(1_500), config: config)?.phase, .longBreak)
    }

    func testAfterABreakTheCycleWaitsForTheUser() {
        let focus = PomodoroEngine.startFocus(taskID: task, completedBlocks: 0, now: at(0), config: config)
        let rest = PomodoroEngine.next(after: focus, now: at(1_500), config: config)!
        XCTAssertNil(PomodoroEngine.next(after: rest, now: at(1_800), config: config))
    }

    func testBlockNumberingWithinTheCycle() {
        XCTAssertEqual(PomodoroEngine.startFocus(taskID: task, completedBlocks: 0, now: at(0), config: config).blockNumber(in: config), 1)
        XCTAssertEqual(PomodoroEngine.startFocus(taskID: task, completedBlocks: 3, now: at(0), config: config).blockNumber(in: config), 4)
        XCTAssertEqual(PomodoroEngine.startFocus(taskID: task, completedBlocks: 4, now: at(0), config: config).blockNumber(in: config), 1)
    }

    func testConfigIsClampedToSaneValues() {
        let wild = PomodoroConfig(focus: 0, shortBreak: -5, longBreak: 99_999, roundsBeforeLongBreak: 0)
        XCTAssertEqual(wild.focus, 60)
        XCTAssertEqual(wild.shortBreak, 60)
        XCTAssertEqual(wild.longBreak, 120 * 60)
        XCTAssertEqual(wild.roundsBeforeLongBreak, 1)
    }
}
