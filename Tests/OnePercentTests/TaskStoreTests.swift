import XCTest
@testable import OnePercent

@MainActor
final class TaskStoreTests: XCTestCase {
    private var mockPersistence: MockTaskPersistence!
    private var dateService: DateService!
    private var store: TaskStore!

    override func setUp() async throws {
        mockPersistence = MockTaskPersistence()
        dateService = DateService(calendar: Calendar(identifier: .gregorian))
        store = TaskStore(persistence: mockPersistence, dateService: dateService)
    }

    // MARK: - Adding Tasks

    func testAddTaskSavesAndTrimsWhitespace() {
        let task = store.addTask(title: "  Buy groceries  ")

        XCTAssertNotNil(task)
        XCTAssertEqual(task?.title, "Buy groceries")
        XCTAssertEqual(task?.status, .todo)
        XCTAssertEqual(store.allTasks.count, 1)
        XCTAssertEqual(mockPersistence.storedTasks.count, 1)
        XCTAssertEqual(mockPersistence.storedTasks.first?.title, "Buy groceries")
    }

    func testAddEmptyOrWhitespaceOnlyTaskIsRejected() {
        let taskEmpty = store.addTask(title: "")
        let taskSpaces = store.addTask(title: "   \n\t  ")

        XCTAssertNil(taskEmpty)
        XCTAssertNil(taskSpaces)
        XCTAssertEqual(store.allTasks.count, 0)
        XCTAssertEqual(mockPersistence.storedTasks.count, 0)
    }

    func testIdenticalTitlesArePreservedAsDistinctEntities() {
        let task1 = store.addTask(title: "Study Swift")
        let task2 = store.addTask(title: "Study Swift")

        XCTAssertNotNil(task1)
        XCTAssertNotNil(task2)
        XCTAssertNotEqual(task1?.id, task2?.id)
        XCTAssertEqual(store.allTasks.count, 2)
        XCTAssertEqual(store.selectedDateTasks.count, 2)
    }

    // MARK: - Status Updates & Deferral

    func testUpdateTaskStatusTransitions() {
        guard let task = store.addTask(title: "Code review") else {
            XCTFail("Failed to add task")
            return
        }

        XCTAssertEqual(task.status, .todo)

        store.updateTaskStatus(id: task.id, newStatus: .inProgress)
        XCTAssertEqual(store.allTasks.first(where: { $0.id == task.id })?.status, .inProgress)
        XCTAssertEqual(mockPersistence.storedTasks.first?.status, .inProgress)

        store.updateTaskStatus(id: task.id, newStatus: .done)
        XCTAssertEqual(store.allTasks.first(where: { $0.id == task.id })?.status, .done)
        XCTAssertEqual(mockPersistence.storedTasks.first?.status, .done)
    }

    func testUpdateTaskStatusToDeferredTriggersRollover() {
        guard let task = store.addTask(title: "Prepare presentation") else {
            XCTFail("Failed to add task")
            return
        }

        store.updateTaskStatus(id: task.id, newStatus: .deferred)

        let original = store.allTasks.first(where: { $0.id == task.id })
        XCTAssertEqual(original?.status, .deferred)
        XCTAssertNotNil(original?.deferredToTaskID)

        // Verifies the new task for tomorrow was added
        let nextDay = dateService.nextDay(after: store.selectedDate)
        let tomorrowTasks = store.tasks(for: nextDay)
        XCTAssertEqual(tomorrowTasks.count, 1)
        XCTAssertEqual(tomorrowTasks.first?.title, "Prepare presentation")
        XCTAssertEqual(tomorrowTasks.first?.status, .todo)
        XCTAssertEqual(tomorrowTasks.first?.sourceTaskID, task.id)
    }

    // MARK: - Progress Calculations

    func testProgressCalculationFormula() {
        // Spec Section 8:
        // completedCount = count(done)
        // totalCount = count(status != deferred)
        // progress = completedCount / totalCount
        XCTAssertEqual(store.currentProgress.completedCount, 0)
        XCTAssertEqual(store.currentProgress.totalCount, 0)
        XCTAssertEqual(store.currentProgress.ratio, 0.0)
        XCTAssertEqual(store.currentProgress.summaryText, "NO GOALS YET")

        let t1 = store.addTask(title: "Task 1")!
        let t2 = store.addTask(title: "Task 2")!
        let t3 = store.addTask(title: "Task 3")!
        let t4 = store.addTask(title: "Task 4")!
        let t5 = store.addTask(title: "Task 5")!

        store.updateTaskStatus(id: t1.id, newStatus: .done)
        store.updateTaskStatus(id: t2.id, newStatus: .done)
        store.updateTaskStatus(id: t3.id, newStatus: .inProgress)
        store.updateTaskStatus(id: t4.id, newStatus: .todo)
        store.updateTaskStatus(id: t5.id, newStatus: .deferred)

        // 2 done out of 4 non-deferred (50%)
        let progress = store.currentProgress
        XCTAssertEqual(progress.completedCount, 2)
        XCTAssertEqual(progress.totalCount, 4)
        XCTAssertEqual(progress.ratio, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.percentageInt, 50)
        XCTAssertEqual(progress.summaryText, "2 OF 4 DONE • 50%")
    }

    // MARK: - Deletion

    func testDeleteTaskRemovesFromStoreAndPersistence() {
        let task = store.addTask(title: "Temporary task")!
        XCTAssertEqual(store.allTasks.count, 1)

        store.deleteTask(id: task.id)
        XCTAssertEqual(store.allTasks.count, 0)
        XCTAssertEqual(mockPersistence.storedTasks.count, 0)
    }

    // MARK: - Date Navigation

    func testDateSelectionAndFiltering() {
        let today = store.selectedDate
        let tomorrow = dateService.nextDay(after: today)

        let taskToday = store.addTask(title: "Today task", for: today)!
        let taskTomorrow = store.addTask(title: "Tomorrow task", for: tomorrow)!

        XCTAssertEqual(store.selectedDateTasks.count, 1)
        XCTAssertEqual(store.selectedDateTasks.first?.id, taskToday.id)

        store.selectTomorrow()
        XCTAssertEqual(store.selectedDate, tomorrow)
        XCTAssertEqual(store.selectedDateTasks.count, 1)
        XCTAssertEqual(store.selectedDateTasks.first?.id, taskTomorrow.id)

        store.selectToday()
        XCTAssertEqual(store.selectedDate, today)
        XCTAssertEqual(store.selectedDateTasks.first?.id, taskToday.id)
    }

    // MARK: - Persistence Reload

    func testPersistenceReloadRestoresTasks() throws {
        _ = store.addTask(title: "Persisted task 1")
        _ = store.addTask(title: "Persisted task 2")

        let newStore = TaskStore(persistence: mockPersistence, dateService: dateService)
        XCTAssertEqual(newStore.allTasks.count, 2)
        XCTAssertEqual(newStore.allTasks.map(\.title), ["Persisted task 1", "Persisted task 2"])
    }

    // MARK: - Deferred Reactivation & Subsequent Deferral

    func testReactivatingDeferredTaskClearsDeferralAndAllowsSubsequentDeferral() {
        let task = store.addTask(title: "Task to defer")!
        store.updateTaskStatus(id: task.id, newStatus: .deferred)

        let deferred = store.allTasks.first(where: { $0.id == task.id })!
        XCTAssertEqual(deferred.status, .deferred)
        XCTAssertNotNil(deferred.deferredToTaskID)

        // Reactivate for today
        store.updateTaskStatus(id: task.id, newStatus: .todo)
        let reactivated = store.allTasks.first(where: { $0.id == task.id })!
        XCTAssertEqual(reactivated.status, .todo)
        XCTAssertNil(reactivated.deferredToTaskID)
        XCTAssertNil(reactivated.deferredAt)

        // Defer again
        store.updateTaskStatus(id: task.id, newStatus: .deferred)
        let redeferred = store.allTasks.first(where: { $0.id == task.id })!
        XCTAssertEqual(redeferred.status, .deferred)
        XCTAssertNotNil(redeferred.deferredToTaskID)
    }

    func testProgressSummaryWhenAllTasksAreDeferred() {
        let t1 = store.addTask(title: "Task 1")!
        let t2 = store.addTask(title: "Task 2")!

        store.updateTaskStatus(id: t1.id, newStatus: .deferred)
        store.updateTaskStatus(id: t2.id, newStatus: .deferred)

        XCTAssertEqual(store.currentProgress.totalCount, 0)
        XCTAssertEqual(store.currentProgress.summaryText, "ALL DEFERRED TO TOMORROW")
    }

    func testErrorMessageHandlingAndClearing() {
        XCTAssertNil(store.lastErrorMessage)
        store.clearErrorMessage()
        XCTAssertNil(store.lastErrorMessage)
    }

    func testSevenDayNavigationClamping() {
        XCTAssertTrue(store.dateService.isToday(store.selectedDate))

        // Navigate 7 days forward
        for _ in 1...7 {
            XCTAssertTrue(store.canGoToNextDay)
            store.selectNextDay()
        }
        XCTAssertFalse(store.canGoToNextDay)
        let maxFutureDate = store.selectedDate

        // Attempting to go further forward does nothing
        store.selectNextDay()
        XCTAssertEqual(store.selectedDate, maxFutureDate)

        // Navigate 14 days back (7 to reach today, 7 to reach past)
        for _ in 1...14 {
            XCTAssertTrue(store.canGoToPreviousDay)
            store.selectPreviousDay()
        }
        XCTAssertFalse(store.canGoToPreviousDay)
        let maxPastDate = store.selectedDate

        // Attempting to go further back does nothing
        store.selectPreviousDay()
        XCTAssertEqual(store.selectedDate, maxPastDate)
    }
}

final class MockTaskPersistence: TaskPersisting, @unchecked Sendable {
    var storedTasks: [TaskItem] = []

    func loadTasks() throws -> [TaskItem] {
        storedTasks
    }

    func saveTasks(_ tasks: [TaskItem]) throws {
        storedTasks = tasks
    }
}
