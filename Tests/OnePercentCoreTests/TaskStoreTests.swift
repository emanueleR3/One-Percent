import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

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

    func testReactivatingDeferredTaskDeletesTomorrowOccurrenceIfStillTodo() {
        let task = store.addTask(title: "Finish report")!
        store.updateTaskStatus(id: task.id, newStatus: .deferred)

        let tomorrow = dateService.nextDay(after: store.selectedDate)
        let tomorrowTasksBefore = store.tasks(for: tomorrow)
        XCTAssertEqual(tomorrowTasksBefore.count, 1)
        XCTAssertEqual(tomorrowTasksBefore.first?.title, "Finish report")
        XCTAssertEqual(tomorrowTasksBefore.first?.status, .todo)

        // Reactivate back to .todo for today
        store.updateTaskStatus(id: task.id, newStatus: .todo)

        // Tomorrow's occurrence must be deleted
        let tomorrowTasksAfter = store.tasks(for: tomorrow)
        XCTAssertEqual(tomorrowTasksAfter.count, 0)
        XCTAssertEqual(store.selectedDateTasks.first?.status, .todo)
    }

    func testReactivatingDeferredTaskPreservesTomorrowOccurrenceIfAlreadyCompleted() {
        let task = store.addTask(title: "Check emails")!
        store.updateTaskStatus(id: task.id, newStatus: .deferred)

        let tomorrow = dateService.nextDay(after: store.selectedDate)
        guard let tomorrowTask = store.tasks(for: tomorrow).first else {
            XCTFail("Tomorrow task missing")
            return
        }

        // Mark tomorrow's task as done
        store.updateTaskStatus(id: tomorrowTask.id, newStatus: .done)

        // Reactivate today's task back to .todo
        store.updateTaskStatus(id: task.id, newStatus: .todo)

        // Tomorrow's occurrence must NOT be deleted because it was already completed
        let tomorrowTasksAfter = store.tasks(for: tomorrow)
        XCTAssertEqual(tomorrowTasksAfter.count, 1)
        XCTAssertEqual(tomorrowTasksAfter.first?.status, .done)
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

    // MARK: - Reordering Tasks

    func testNewlyAddedTasksGetIncrementedSortOrder() {
        let t1 = store.addTask(title: "Task 1")!
        let t2 = store.addTask(title: "Task 2")!
        let t3 = store.addTask(title: "Task 3")!

        XCTAssertEqual(t1.sortOrder, 0)
        XCTAssertEqual(t2.sortOrder, 1)
        XCTAssertEqual(t3.sortOrder, 2)

        let dayTasks = store.selectedDateTasks
        XCTAssertEqual(dayTasks.map(\.title), ["Task 1", "Task 2", "Task 3"])
    }

    func testTaskReorderingByIDs() {
        let t1 = store.addTask(title: "Alpha")!
        let t2 = store.addTask(title: "Beta")!
        let t3 = store.addTask(title: "Gamma")!

        // Move Gamma to Alpha: [Gamma, Alpha, Beta]
        store.moveTask(from: t3.id, to: t1.id)
        let reordered1 = store.selectedDateTasks
        XCTAssertEqual(reordered1.map(\.title), ["Gamma", "Alpha", "Beta"])
        XCTAssertEqual(reordered1.map(\.sortOrder), [0, 1, 2])

        // Verify persistence also saved the updated sort order
        XCTAssertEqual(mockPersistence.storedTasks.first(where: { $0.title == "Gamma" })?.sortOrder, 0)
        XCTAssertEqual(mockPersistence.storedTasks.first(where: { $0.title == "Alpha" })?.sortOrder, 1)
        XCTAssertEqual(mockPersistence.storedTasks.first(where: { $0.title == "Beta" })?.sortOrder, 2)

        // Move Gamma to Beta: [Alpha, Beta, Gamma]
        store.moveTask(from: t3.id, to: t2.id)
        let reordered2 = store.selectedDateTasks
        XCTAssertEqual(reordered2.map(\.title), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(reordered2.map(\.sortOrder), [0, 1, 2])
    }

    func testTaskReorderingByIndices() {
        _ = store.addTask(title: "First")!
        _ = store.addTask(title: "Second")!
        _ = store.addTask(title: "Third")!

        // Move index 0 to index 2
        store.moveTask(from: 0, to: 2)
        let reordered = store.selectedDateTasks
        XCTAssertEqual(reordered.map(\.title), ["Second", "Third", "First"])
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1, 2])
    }

    // MARK: - Update Task Title

    func testUpdateTaskTitleTrimsAndPersists() {
        let task = store.addTask(title: "Initial title")!
        let success = store.updateTaskTitle(id: task.id, newTitle: "  Updated title  ")

        XCTAssertTrue(success)
        XCTAssertEqual(store.selectedDateTasks.first?.title, "Updated title")
        XCTAssertEqual(mockPersistence.storedTasks.first?.title, "Updated title")
    }

    func testUpdateTaskTitleRejectsEmptyOrWhitespace() {
        let task = store.addTask(title: "Valid title")!
        let successEmpty = store.updateTaskTitle(id: task.id, newTitle: "")
        let successSpaces = store.updateTaskTitle(id: task.id, newTitle: "   \n\t  ")

        XCTAssertFalse(successEmpty)
        XCTAssertFalse(successSpaces)
        XCTAssertEqual(store.selectedDateTasks.first?.title, "Valid title")
    }

    // MARK: - Auto-Demote and Move to Bottom

    func testMoveTaskToBottomMovesItemToEndAndPersistsOrder() {
        let t1 = store.addTask(title: "First")!
        _ = store.addTask(title: "Second")!
        _ = store.addTask(title: "Third")!

        store.moveTaskToBottom(id: t1.id)

        let reordered = store.selectedDateTasks
        XCTAssertEqual(reordered.map(\.title), ["Second", "Third", "First"])
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(mockPersistence.storedTasks.first(where: { $0.id == t1.id })?.sortOrder, 2)
    }

    func testMoveTaskToBottomWhenAlreadyAtBottomIsNoOp() {
        _ = store.addTask(title: "First")!
        let t2 = store.addTask(title: "Second")!

        store.moveTaskToBottom(id: t2.id)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["First", "Second"])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1])
    }

    func testAutoDemoteSchedulesAndMovesCompletedTask() async throws {
        let t1 = store.addTask(title: "Task to complete")!
        _ = store.addTask(title: "Second task")!

        // Marking as done schedules auto-demote with 1.5s delay by default,
        // but we can schedule with 0.1s for test speed
        store.scheduleAutoDemote(for: t1.id, delay: 0.1)
        store.updateTaskStatus(id: t1.id, newStatus: .done)
        // re-schedule with short delay for fast test execution
        store.scheduleAutoDemote(for: t1.id, delay: 0.05)

        try await Task.sleep(nanoseconds: 150_000_000) // 150ms

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Second task", "Task to complete"])
        XCTAssertEqual(tasks.last?.id, t1.id)
    }

    func testAutoDemoteCancelledIfStatusChangedBeforeDelay() async throws {
        let t1 = store.addTask(title: "Task to complete")!
        _ = store.addTask(title: "Second task")!

        store.updateTaskStatus(id: t1.id, newStatus: .done)
        // Schedule with 0.2s
        store.scheduleAutoDemote(for: t1.id, delay: 0.2)

        // Cancel within 50ms by changing status back to inProgress
        try await Task.sleep(nanoseconds: 50_000_000)
        store.updateTaskStatus(id: t1.id, newStatus: .inProgress)

        // Wait beyond original delay
        try await Task.sleep(nanoseconds: 200_000_000)

        // Must still be first!
        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Task to complete", "Second task"])
    }

    func testReactivatingDeferredTaskRemovesTomorrowPendingClone() {
        let task = store.addTask(title: "Original goal")!
        store.updateTaskStatus(id: task.id, newStatus: .deferred)

        let nextDay = dateService.nextDay(after: store.selectedDate)
        XCTAssertEqual(store.tasks(for: nextDay).count, 1)

        // Reactivate back to .todo
        store.updateTaskStatus(id: task.id, newStatus: .todo)

        // The tomorrow clone must have been removed
        XCTAssertEqual(store.tasks(for: nextDay).count, 0)
        XCTAssertEqual(store.selectedDateTasks.first?.status, .todo)
        XCTAssertNil(store.selectedDateTasks.first?.deferredToTaskID)
    }

    // MARK: - Auto-Promote In-Progress Section

    func testMoveTaskToInProgressSectionMovesToTopWhenNoOtherInProgress() {
        _ = store.addTask(title: "First Todo")!
        _ = store.addTask(title: "Second Todo")!
        let t3 = store.addTask(title: "Third Todo")!

        store.updateTaskStatus(id: t3.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t3.id)
        store.moveTaskToInProgressSection(id: t3.id)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Third Todo", "First Todo", "Second Todo"])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(mockPersistence.storedTasks.first(where: { $0.id == t3.id })?.sortOrder, 0)
    }

    func testMoveTaskToInProgressSectionPositionsBelowExistingInProgressTasks() {
        let t1 = store.addTask(title: "Existing InProgress 1")!
        let t2 = store.addTask(title: "Existing InProgress 2")!
        _ = store.addTask(title: "Todo A")!
        let t4 = store.addTask(title: "Target Task")!
        _ = store.addTask(title: "Todo B")!

        // Setup t1 and t2 as already inProgress
        store.updateTaskStatus(id: t1.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t1.id)
        store.updateTaskStatus(id: t2.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t2.id)

        // Target task becomes in progress
        store.updateTaskStatus(id: t4.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t4.id)
        store.moveTaskToInProgressSection(id: t4.id)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), [
            "Existing InProgress 1",
            "Existing InProgress 2",
            "Target Task",
            "Todo A",
            "Todo B"
        ])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1, 2, 3, 4])
    }

    func testMoveTaskToInProgressSectionWhenAlreadyInCorrectPositionIsNoOp() {
        let t1 = store.addTask(title: "Task 1")!
        _ = store.addTask(title: "Task 2")!

        store.updateTaskStatus(id: t1.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t1.id)
        store.moveTaskToInProgressSection(id: t1.id)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Task 1", "Task 2"])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1])
    }

    func testAutoPromoteSchedulesAndMovesInProgressTask() async throws {
        _ = store.addTask(title: "Existing Todo 1")!
        _ = store.addTask(title: "Existing Todo 2")!
        let t3 = store.addTask(title: "Task to start")!

        // Marking as inProgress triggers scheduleAutoPromote
        store.updateTaskStatus(id: t3.id, newStatus: .inProgress)
        // re-schedule with short delay for fast test execution
        store.scheduleAutoPromote(for: t3.id, delay: 0.05)

        try await Task.sleep(nanoseconds: 150_000_000) // 150ms

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Task to start", "Existing Todo 1", "Existing Todo 2"])
        XCTAssertEqual(tasks.first?.id, t3.id)
    }

    func testAutoPromoteCancelledIfStatusChangedBeforeDelay() async throws {
        _ = store.addTask(title: "Existing Todo")!
        let t2 = store.addTask(title: "Task to start")!

        store.updateTaskStatus(id: t2.id, newStatus: .inProgress)
        store.scheduleAutoPromote(for: t2.id, delay: 0.2)

        // Cancel within 50ms by changing status back to todo
        try await Task.sleep(nanoseconds: 50_000_000)
        store.updateTaskStatus(id: t2.id, newStatus: .todo)

        // Wait beyond original delay
        try await Task.sleep(nanoseconds: 200_000_000)

        // Must still be in original order!
        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Existing Todo", "Task to start"])
    }

    // MARK: - In-Progress to To Do Positioning

    func testMoveTaskBelowLastInProgressWhenInProgressTasksExistBelow() {
        let t1 = store.addTask(title: "Task A")!
        let t2 = store.addTask(title: "Task B")!
        let t3 = store.addTask(title: "Task C")!
        _ = store.addTask(title: "Task D")!

        store.updateTaskStatus(id: t2.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t2.id)
        store.updateTaskStatus(id: t3.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t3.id)

        // Currently: t1 (todo), t2 (inProgress), t3 (inProgress), t4 (todo)
        store.moveTaskBelowLastInProgress(id: t1.id)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Task B", "Task C", "Task A", "Task D"])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(mockPersistence.storedTasks.first(where: { $0.id == t1.id })?.sortOrder, 2)
    }

    func testMoveTaskBelowLastInProgressWhenNoInProgressTasksBelowIsNoOp() {
        let t1 = store.addTask(title: "Task A")!
        let t2 = store.addTask(title: "Task B")!

        store.updateTaskStatus(id: t1.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t1.id)

        // Currently: t1 (inProgress), t2 (todo)
        store.moveTaskBelowLastInProgress(id: t2.id)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Task A", "Task B"])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1])
    }

    func testUpdatingStatusFromInProgressToTodoAutomaticallyMovesTaskBelowLastInProgress() {
        let t1 = store.addTask(title: "Task 1")!
        let t2 = store.addTask(title: "Task 2")!
        _ = store.addTask(title: "Task 3")!

        // Make both t1 and t2 inProgress
        store.updateTaskStatus(id: t1.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t1.id)
        store.updateTaskStatus(id: t2.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t2.id)

        // Now move t1 back to todo: since t2 is inProgress below t1, t1 must move below t2!
        store.updateTaskStatus(id: t1.id, newStatus: .todo)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Task 2", "Task 1", "Task 3"])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(tasks[1].status, .todo)
        XCTAssertEqual(tasks[0].status, .inProgress)
    }

    func testUpdatingStatusFromInProgressToTodoWhenNoInProgressBelowPreservesPosition() {
        let t1 = store.addTask(title: "Task 1")!
        _ = store.addTask(title: "Task 2")!

        store.updateTaskStatus(id: t1.id, newStatus: .inProgress)
        store.cancelAutoPromote(for: t1.id)

        // t1 is at top (index 0). Move t1 back to todo. No inProgress tasks below it -> stays at index 0.
        store.updateTaskStatus(id: t1.id, newStatus: .todo)

        let tasks = store.selectedDateTasks
        XCTAssertEqual(tasks.map(\.title), ["Task 1", "Task 2"])
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1])
    }
}

// MARK: - Tracking integration

@MainActor
final class TaskStoreTrackingTests: XCTestCase {
    private var store: TaskStore!

    override func setUp() async throws {
        store = TaskStore(
            persistence: MockTaskPersistence(),
            dateService: DateService(calendar: Calendar(identifier: .gregorian))
        )
    }

    func testTrackingStartsEmpty() {
        XCTAssertEqual(store.tracking.currentStreak, 0)
        XCTAssertFalse(store.tracking.isTodayCounted)
        XCTAssertEqual(store.tracking.week.count, 7)
    }

    func testCompletingAGoalBanksTodayInTheStreak() {
        guard let task = store.addTask(title: "Read") else { return XCTFail("add failed") }
        XCTAssertEqual(store.tracking.currentStreak, 0)

        store.updateTaskStatus(id: task.id, newStatus: .done)

        XCTAssertEqual(store.tracking.currentStreak, 1)
        XCTAssertTrue(store.tracking.isTodayCounted)
        XCTAssertEqual(store.tracking.perfectDays, 1)
        XCTAssertEqual(store.tracking.week.last?.completed, 1)
    }

    func testTrackingCacheInvalidatesWhenTasksChange() {
        guard let task = store.addTask(title: "Read") else { return XCTFail("add failed") }
        store.updateTaskStatus(id: task.id, newStatus: .done)
        XCTAssertEqual(store.tracking.currentStreak, 1)

        store.updateTaskStatus(id: task.id, newStatus: .todo)
        XCTAssertEqual(store.tracking.currentStreak, 0)

        store.deleteTask(id: task.id)
        XCTAssertEqual(store.tracking.week.last?.total, 0)
    }

    func testDeferralCountGrowsEachTimeAGoalIsPushedForward() {
        guard let first = store.addTask(title: "Call accountant") else { return XCTFail("add failed") }
        XCTAssertEqual(store.deferralCount(for: first.id), 0)

        store.deferTask(id: first.id)
        let second = store.allTasks.first { $0.sourceTaskID == first.id }
        XCTAssertNotNil(second)
        XCTAssertEqual(store.deferralCount(for: second!.id), 1)

        store.deferTask(id: second!.id)
        let third = store.allTasks.first { $0.sourceTaskID == second!.id }
        XCTAssertNotNil(third)
        XCTAssertEqual(store.deferralCount(for: third!.id), 2)
    }
}
