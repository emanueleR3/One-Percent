import XCTest
@testable import OnePercent

/// New goals land after the last open goal, never underneath the finished ones.
@MainActor
final class TaskInsertionOrderTests: XCTestCase {
    private var store: TaskStore!
    private var dateService: DateService!

    override func setUp() async throws {
        dateService = DateService(calendar: Calendar(identifier: .gregorian))
        store = TaskStore(
            persistence: MockTaskPersistence(),
            dateService: dateService,
            habitPersistence: InMemoryHabitPersistence()
        )
    }

    private func add(_ title: String) -> TaskItem {
        store.addTask(title: title)!
    }

    /// Builds a day in the given order, then applies the statuses. Setting them afterwards matters:
    /// creating a goal that is already done would itself be placed by the rule under test.
    @discardableResult
    private func seed(_ items: [(String, TaskStatus)]) -> [TaskItem] {
        let created = items.map { store.addTask(title: $0.0)! }
        for (task, item) in zip(created, items) where item.1 != .todo {
            store.updateTaskStatus(id: task.id, newStatus: item.1)
        }
        return created
    }

    private var titles: [String] { store.selectedDateTasks.map(\.title) }
    private var orders: [Int] { store.selectedDateTasks.map(\.sortOrder) }

    func testNewGoalGoesAboveDoneGoals() {
        seed([("A", .todo), ("B", .done), ("C", .done)])

        _ = add("N")

        XCTAssertEqual(titles, ["A", "N", "B", "C"])
        XCTAssertEqual(orders, [0, 1, 2, 3])
    }

    func testNewGoalGoesAfterTheLastTodoWhenInProgressComesFirst() {
        seed([("Doing", .inProgress), ("Todo", .todo), ("Done", .done)])

        _ = add("N")

        XCTAssertEqual(titles, ["Doing", "Todo", "N", "Done"])
    }

    func testGoalsAddedInARowKeepTheirOrder() {
        seed([("A", .todo), ("Done", .done)])
        _ = add("N1")
        _ = add("N2")

        XCTAssertEqual(titles, ["A", "N1", "N2", "Done"])
    }

    func testWithNothingOpenTheNewGoalGoesFirst() {
        seed([("Done", .done), ("Moved", .deferred)])

        _ = add("N")

        XCTAssertEqual(titles, ["N", "Done", "Moved"])
        XCTAssertEqual(orders, [0, 1, 2])
    }

    func testDeferredGoalsBetweenOpenAndDoneStayBelowTheNewOne() {
        seed([("Todo", .todo), ("Moved", .deferred), ("Done", .done)])

        _ = add("N")

        XCTAssertEqual(titles, ["Todo", "N", "Moved", "Done"])
    }

    func testOnAnEmptyDayItStartsAtZero() {
        let first = add("N")
        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(titles, ["N"])
    }

    func testTheOneStaysOnTopWhenGoalsAreAdded() {
        let one = seed([("One", .todo), ("Other", .todo), ("Done", .done)])[0]
        store.setTheOne(id: one.id)

        _ = add("N")

        XCTAssertEqual(titles.first, "One")
        XCTAssertEqual(titles, ["One", "Other", "N", "Done"])
    }

    func testReturnedTaskCarriesItsFinalPosition() {
        seed([("A", .todo), ("Done", .done)])
        let n = add("N")
        XCTAssertEqual(n.sortOrder, 1)
        XCTAssertEqual(store.allTasks.first { $0.id == n.id }?.sortOrder, 1)
    }

    func testOtherDaysAreNotTouched() {
        let tomorrow = dateService.nextDay(after: dateService.today)
        store.addTask(title: "Tomorrow A", for: tomorrow)
        seed([("Today A", .todo), ("Today Done", .done)])

        _ = add("N")

        XCTAssertEqual(store.tasks(for: tomorrow).map(\.sortOrder), [0])
    }

    func testHabitOccurrencesAlsoLandAboveDoneGoals() {
        seed([("A", .todo), ("Done", .done)])

        store.addHabit(title: "Read", schedule: .daily, startDate: dateService.today)

        XCTAssertEqual(titles, ["A", "Read", "Done"])
    }

    func testOrderIsPersisted() {
        let persistence = MockTaskPersistence()
        let local = TaskStore(persistence: persistence, dateService: dateService, habitPersistence: InMemoryHabitPersistence())
        let a = local.addTask(title: "A")!
        let done = local.addTask(title: "Done")!
        local.updateTaskStatus(id: done.id, newStatus: .done)
        let n = local.addTask(title: "N")!

        let stored = persistence.storedTasks
        XCTAssertEqual(stored.first { $0.id == a.id }?.sortOrder, 0)
        XCTAssertEqual(stored.first { $0.id == n.id }?.sortOrder, 1)
        XCTAssertEqual(stored.first { $0.id == done.id }?.sortOrder, 2)
    }
}
