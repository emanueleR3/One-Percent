import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

private final class Settings: FocusSettings {
    var pomodoroEnabled = true
    var pomodoroConfig = PomodoroConfig(focus: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, roundsBeforeLongBreak: 4)
    var focusSound = false
    var focusNotifications = false
}

/// A timer that outlived the app: the block comes back, and a sleeping Mac leaves other devices' timers alone.
@MainActor
final class FocusRestoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var dateService: DateService!

    override func setUp() async throws {
        dateService = DateService(calendar: Calendar(identifier: .gregorian))
    }

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// A store that already holds a running timer, as after relaunching the app.
    private func reopened(pomodoro: Bool, startedAt: Date, ours: Bool) -> (TaskStore, UUID) {
        let goal = TaskItem(
            title: "Study", status: .inProgress, scheduledDate: dateService.today,
            createdAt: startedAt, updatedAt: startedAt, timerStartedAt: startedAt, timerIsPomodoro: pomodoro
        )
        let disk = MockTaskPersistence()
        disk.storedTasks = [goal]
        let origin = InMemoryTimerOrigin()
        if ours { origin.save(LocalTimerMarker(taskID: goal.id, startedAt: startedAt)) }
        let store = TaskStore(
            persistence: disk, dateService: dateService, habitPersistence: InMemoryHabitPersistence(),
            timerRelaunch: .keepRunning, timerOrigin: origin
        )
        return (store, goal.id)
    }

    private func controller(_ store: TaskStore, now: @escaping () -> Date, settings: Settings = Settings()) -> FocusController {
        FocusController(store: store, preferences: settings, scheduler: nil, now: now, autoTick: false)
    }

    func testABlockStillRunningComesBackWithItsRemainingTime() {
        let (store, id) = reopened(pomodoro: true, startedAt: at(0), ours: true)

        let focus = controller(store) { self.at(10 * 60) }

        let block = try! XCTUnwrap(focus.pomodoro)
        XCTAssertEqual(block.taskID, id)
        XCTAssertEqual(block.phase, .focus)
        XCTAssertEqual(block.remaining(at: at(10 * 60)), 15 * 60, accuracy: 0.001)
        XCTAssertEqual(store.runningTimerTaskID, id)
    }

    func testABlockThatEndedWhileClosedBanksExactlyTheBlock() {
        let (store, id) = reopened(pomodoro: true, startedAt: at(0), ours: true)

        let focus = controller(store) { self.at(2 * 3_600) }   // two hours later

        XCTAssertNil(focus.pomodoro)
        XCTAssertNil(store.runningTimerTaskID)
        XCTAssertEqual(store.allTasks.first { $0.id == id }!.focusSessions.map(\.seconds), [25 * 60])
    }

    func testAFreeTimerNeedsNoBlock() {
        let (store, id) = reopened(pomodoro: false, startedAt: at(0), ours: true)

        let focus = controller(store) { self.at(3_600) }

        XCTAssertNil(focus.pomodoro)
        XCTAssertEqual(store.runningTimerTaskID, id)
    }

    func testABlockThatAnotherDeviceRunsIsNotTakenOver() {
        let (store, id) = reopened(pomodoro: true, startedAt: at(0), ours: false)

        let focus = controller(store) { self.at(10 * 60) }

        XCTAssertNil(focus.pomodoro)
        XCTAssertEqual(store.runningTimerTaskID, id)
        XCTAssertTrue(store.allTasks.first!.focusSessions.isEmpty)
    }

    func testASleepingMacLeavesAnotherDevicesTimerRunning() {
        let (store, id) = reopened(pomodoro: false, startedAt: at(0), ours: false)
        let focus = controller(store) { self.at(600) }

        focus.systemWillSleep()

        XCTAssertEqual(store.runningTimerTaskID, id)
    }

    func testASleepingMacStillPausesItsOwnTimer() {
        let (store, id) = reopened(pomodoro: false, startedAt: at(0), ours: true)
        let focus = controller(store) { self.at(600) }

        focus.systemWillSleep()

        XCTAssertNil(store.runningTimerTaskID)
        XCTAssertEqual(store.allTasks.first { $0.id == id }!.focusSessions.map(\.seconds), [600])
    }
}
