import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

@MainActor
final class FocusTimerTests: XCTestCase {
    private var store: TaskStore!
    private var persistence: MockTaskPersistence!
    private var dateService: DateService!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        persistence = MockTaskPersistence()
        dateService = DateService(calendar: Calendar(identifier: .gregorian))
        store = TaskStore(persistence: persistence, dateService: dateService, habitPersistence: InMemoryHabitPersistence())
    }

    private func add(_ title: String) -> TaskItem { store.addTask(title: title)! }
    private func task(_ id: UUID) -> TaskItem { store.allTasks.first { $0.id == id }! }
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - Starting

    func testStartingMarksTheGoalInProgressAndRunning() {
        let a = add("A")
        XCTAssertTrue(store.startTimer(id: a.id, at: at(0)))
        XCTAssertEqual(task(a.id).status, .inProgress)
        XCTAssertEqual(task(a.id).timerStartedAt, at(0))
        XCTAssertEqual(store.runningTimerTaskID, a.id)
    }

    func testOnlyOneTimerRunsAndTheOtherIsBanked() {
        let a = add("A"), b = add("B")
        store.startTimer(id: a.id, at: at(0))
        store.startTimer(id: b.id, at: at(600))

        XCTAssertEqual(store.runningTimerTaskID, b.id)
        XCTAssertNil(task(a.id).timerStartedAt)
        XCTAssertEqual(task(a.id).timeSpent(at: at(9_999)), 600, accuracy: 0.001)
        XCTAssertEqual(task(a.id).focusSessions.count, 1)
    }

    func testStartingTheRunningGoalAgainChangesNothing() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        XCTAssertTrue(store.startTimer(id: a.id, at: at(300)))
        XCTAssertEqual(task(a.id).timerStartedAt, at(0))
    }

    func testFinishedOrMovedGoalsCannotBeTimed() {
        let done = add("Done")
        store.updateTaskStatus(id: done.id, newStatus: .done)
        XCTAssertFalse(store.startTimer(id: done.id, at: at(0)))

        let moved = add("Moved")
        store.updateTaskStatus(id: moved.id, newStatus: .deferred)
        XCTAssertFalse(store.startTimer(id: moved.id, at: at(0)))
        XCTAssertNil(store.runningTimerTaskID)
    }

    // MARK: - Pausing and totals

    func testPausingBanksTheElapsedTimeAsASession() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.pauseTimer(id: a.id, at: at(1_500))

        XCTAssertNil(task(a.id).timerStartedAt)
        XCTAssertEqual(task(a.id).focusSessions.map(\.seconds), [1_500])
        XCTAssertEqual(task(a.id).focusSessions.first?.start, at(0))
    }

    func testTimeSpentIncludesTheRunningSegment() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.pauseTimer(id: a.id, at: at(100))
        store.startTimer(id: a.id, at: at(500))

        XCTAssertEqual(task(a.id).timeSpent(at: at(560)), 160, accuracy: 0.001)
        XCTAssertTrue(task(a.id).isTimerRunning)
    }

    func testSegmentsUnderASecondAreDropped() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.pauseTimer(id: a.id, at: at(0.4))
        XCTAssertTrue(task(a.id).focusSessions.isEmpty)
    }

    func testPomodoroSessionsAreMarked() {
        let a = add("A")
        store.startTimer(id: a.id, isPomodoro: true, at: at(0))
        store.pauseTimer(id: a.id, at: at(1_500))
        XCTAssertEqual(task(a.id).focusSessions.first?.isPomodoro, true)

        store.startTimer(id: a.id, at: at(2_000))
        store.pauseTimer(id: a.id, at: at(2_100))
        XCTAssertEqual(task(a.id).focusSessions.last?.isPomodoro, false)
    }

    func testPausingAnIdleGoalChangesNothing() {
        let a = add("A")
        store.pauseTimer(id: a.id, at: at(10))
        XCTAssertTrue(task(a.id).focusSessions.isEmpty)
    }

    // MARK: - Status changes stop the clock

    func testCompletingTheGoalStopsAndBanksTheTimer() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.updateTaskStatus(id: a.id, newStatus: .done)
        // The store stamps "now" itself here, so only the shape of the result is checked.
        XCTAssertNil(task(a.id).timerStartedAt)
        XCTAssertNil(store.runningTimerTaskID)
    }

    func testMovingBackToToDoOrTomorrowStopsTheTimer() {
        let a = add("A"), b = add("B")
        store.startTimer(id: a.id, at: at(0))
        store.updateTaskStatus(id: a.id, newStatus: .todo)
        XCTAssertNil(task(a.id).timerStartedAt)

        store.startTimer(id: b.id, at: at(0))
        store.updateTaskStatus(id: b.id, newStatus: .deferred)
        XCTAssertNil(task(b.id).timerStartedAt)
    }

    func testStayingInProgressKeepsTheTimerRunning() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.updateTaskStatus(id: a.id, newStatus: .inProgress)
        XCTAssertNotNil(task(a.id).timerStartedAt)
    }

    func testDeletingTheRunningGoalClearsTheRunningTimer() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.deleteTask(id: a.id)
        XCTAssertNil(store.runningTimerTaskID)
    }

    // MARK: - Relaunch

    func testAnInterruptedTimerIsCreditedOnlyUntilTheLastSave() {
        let a = TaskItem(
            title: "A", status: .inProgress, scheduledDate: dateService.today,
            createdAt: at(0), updatedAt: at(900), timerStartedAt: at(0)
        )
        let stored = MockTaskPersistence()
        stored.storedTasks = [a]

        let reopened = TaskStore(persistence: stored, dateService: dateService, habitPersistence: InMemoryHabitPersistence())

        let revived = reopened.allTasks.first!
        XCTAssertNil(revived.timerStartedAt)
        XCTAssertEqual(revived.focusSessions.map(\.seconds), [900])
        XCTAssertNil(reopened.runningTimerTaskID)
    }

    func testHeartbeatAdvancesTheCheckpointOfTheRunningTimer() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.timerHeartbeat(at: at(30))
        XCTAssertEqual(task(a.id).updatedAt, at(30))
    }

    // MARK: - Maintenance

    func testResetTimeClearsSessionsAndStopsTheClock() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.pauseTimer(id: a.id, at: at(100))
        store.startTimer(id: a.id, at: at(200))

        store.resetFocusTime(id: a.id)

        XCTAssertTrue(task(a.id).focusSessions.isEmpty)
        XCTAssertNil(task(a.id).timerStartedAt)
        XCTAssertEqual(task(a.id).timeSpent(at: at(9_999)), 0)
    }

    func testRolloverDoesNotCopyFocusTime() {
        let a = add("A")
        store.startTimer(id: a.id, at: at(0))
        store.pauseTimer(id: a.id, at: at(600))
        store.deferTask(id: a.id)
        let copy = store.allTasks.first { $0.sourceTaskID == a.id }!
        XCTAssertTrue(copy.focusSessions.isEmpty)
        XCTAssertNil(copy.timerStartedAt)
    }

    func testOlderFilesWithoutFocusFieldsStillDecode() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","title":"Old","status":"todo","scheduledDate":"2026-10-09T00:00:00Z",
          "createdAt":"2026-10-09T00:00:00Z","updatedAt":"2026-10-09T00:00:00Z","sortOrder":0}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode([TaskItem].self, from: Data(json.utf8))[0]
        XCTAssertTrue(task.focusSessions.isEmpty)
        XCTAssertNil(task.timerStartedAt)
        XCTAssertEqual(task.timeSpent(at: Date()), 0)
    }
}
