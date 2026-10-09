import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

final class TaskRolloverTests: XCTestCase {
    private var calendar: Calendar!
    private var monday: Date!
    private var tuesday: Date!
    private var wednesday: Date!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 12 // Monday
        components.hour = 9
        monday = calendar.date(from: components)!
        tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
    }

    func testDeferTaskCreatesNextDayOccurrence() {
        let taskA = TaskItem(
            title: "Study Swift",
            status: .inProgress,
            scheduledDate: monday
        )

        let result = TaskRolloverService.deferTask(taskA, to: tuesday)

        guard case .success(let updatedA, let newB) = result else {
            XCTFail("Expected rollover success")
            return
        }

        // Original task checks
        XCTAssertEqual(updatedA.id, taskA.id)
        XCTAssertEqual(updatedA.status, .deferred)
        XCTAssertEqual(updatedA.scheduledDate, monday)
        XCTAssertNotNil(updatedA.deferredAt)
        XCTAssertEqual(updatedA.deferredToTaskID, newB.id)

        // New task checks
        XCTAssertNotEqual(newB.id, taskA.id)
        XCTAssertEqual(newB.title, "Study Swift")
        XCTAssertEqual(newB.status, .todo)
        XCTAssertEqual(newB.scheduledDate, tuesday)
        XCTAssertEqual(newB.sourceTaskID, taskA.id)
        XCTAssertNil(newB.deferredToTaskID)
        XCTAssertNil(newB.deferredAt)
    }

    func testDeferIsIdempotentPreventingDuplicateOccurrences() {
        let taskA = TaskItem(
            title: "Finish Report",
            status: .todo,
            scheduledDate: monday
        )

        let firstResult = TaskRolloverService.deferTask(taskA, to: tuesday)
        guard case .success(let updatedA, let newB) = firstResult else {
            XCTFail("First deferral must succeed")
            return
        }

        // Second deferral on already deferred task
        let secondResult = TaskRolloverService.deferTask(updatedA, to: tuesday)
        guard case .ignoredAlreadyDeferred(let existingID) = secondResult else {
            XCTFail("Second deferral must be ignored as already deferred")
            return
        }

        XCTAssertEqual(existingID, newB.id)
    }

    func testCompletedTaskCannotBeDeferredDirectly() {
        let completedTask = TaskItem(
            title: "Write Specs",
            status: .done,
            scheduledDate: monday
        )

        let result = TaskRolloverService.deferTask(completedTask, to: tuesday)
        guard case .rejectedCompletedTask = result else {
            XCTFail("Completed task deferral must be rejected")
            return
        }
    }

    func testMultiDayRolloverChain() {
        // Monday: Task A
        let taskA = TaskItem(
            title: "Exercise",
            status: .inProgress,
            scheduledDate: monday
        )

        // Monday -> Tuesday: A -> B
        let result1 = TaskRolloverService.deferTask(taskA, to: tuesday)
        guard case .success(let updatedA, let taskB) = result1 else {
            XCTFail("A -> B failed")
            return
        }

        // Tuesday -> Wednesday: B -> C
        let result2 = TaskRolloverService.deferTask(taskB, to: wednesday)
        guard case .success(let updatedB, let taskC) = result2 else {
            XCTFail("B -> C failed")
            return
        }

        // Verify full chain integrity: A -> B -> C
        XCTAssertEqual(updatedA.status, .deferred)
        XCTAssertEqual(updatedA.deferredToTaskID, taskB.id)
        XCTAssertNil(updatedA.sourceTaskID)

        XCTAssertEqual(updatedB.status, .deferred)
        XCTAssertEqual(updatedB.sourceTaskID, taskA.id)
        XCTAssertEqual(updatedB.deferredToTaskID, taskC.id)

        XCTAssertEqual(taskC.status, .todo)
        XCTAssertEqual(taskC.sourceTaskID, taskB.id)
        XCTAssertNil(taskC.deferredToTaskID)
        XCTAssertEqual(taskC.scheduledDate, wednesday)
    }

    func testDeferWhenIdenticalTitleAlreadyExistsTomorrow() {
        let taskToday = TaskItem(title: "Study Swift", status: .todo, scheduledDate: monday)
        let result = TaskRolloverService.deferTask(taskToday, to: tuesday)

        guard case .success(_, let newDeferred) = result else {
            XCTFail("Deferral failed")
            return
        }

        let existingTomorrowTask = TaskItem(title: "Study Swift", status: .todo, scheduledDate: tuesday)

        XCTAssertNotEqual(newDeferred.id, existingTomorrowTask.id)
        XCTAssertEqual(newDeferred.title, existingTomorrowTask.title)
    }

    func testTwoTasksWithIdenticalTitleBothCanBeDeferred() {
        let task1 = TaskItem(title: "Check Email", status: .todo, scheduledDate: monday)
        let task2 = TaskItem(title: "Check Email", status: .inProgress, scheduledDate: monday)

        let result1 = TaskRolloverService.deferTask(task1, to: tuesday)
        let result2 = TaskRolloverService.deferTask(task2, to: tuesday)

        guard case .success(let updated1, let new1) = result1,
              case .success(let updated2, let new2) = result2 else {
            XCTFail("Both deferrals should succeed")
            return
        }

        XCTAssertNotEqual(updated1.id, updated2.id)
        XCTAssertNotEqual(new1.id, new2.id)
        XCTAssertEqual(new1.sourceTaskID, updated1.id)
        XCTAssertEqual(new2.sourceTaskID, updated2.id)
    }
}
