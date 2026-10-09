import XCTest
@testable import OnePercent

/// "Gym every Friday" cannot happen today, so it is moved to tomorrow as a one-off exception.
@MainActor
final class HabitDeferralTests: XCTestCase {
    private var store: TaskStore!
    private var dateService: DateService!
    private var calendar: Calendar!

    override func setUp() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        calendar = cal
        dateService = DateService(calendar: cal)
    }

    private func day(_ offset: Int) -> Date {
        dateService.normalize(calendar.date(byAdding: .day, value: offset, to: dateService.today)!)
    }

    /// Builds a store around one habit with some past occurrences already on disk.
    /// `history` entries: (day offset, status). Past days are not auto-created beyond a week,
    /// so older occurrences have to be preloaded.
    @discardableResult
    private func makeStore(
        schedule: HabitSchedule? = nil,
        startOffset: Int = -21,
        history: [TaskItem] = [],
        habitID: UUID = UUID()
    ) -> Habit {
        let weekday = calendar.component(.weekday, from: dateService.today)
        let habit = Habit(
            id: habitID,
            title: "Gym",
            schedule: schedule ?? .weekly(on: weekday),
            startDate: day(startOffset)
        )
        let tasks = MockTaskPersistence()
        tasks.storedTasks = history
        let habits = InMemoryHabitPersistence()
        try? habits.saveHabits([habit])
        store = TaskStore(persistence: tasks, dateService: dateService, habitPersistence: habits)
        return habit
    }

    private func past(_ habit: Habit, _ offset: Int, _ status: TaskStatus, id: UUID = UUID(),
                      movedTo: UUID? = nil, from: UUID? = nil) -> TaskItem {
        TaskItem(
            id: id, title: habit.title, status: status, scheduledDate: day(offset),
            sourceTaskID: from, deferredToTaskID: movedTo, habitID: habit.id
        )
    }

    private func occurrence(_ habit: Habit, _ offset: Int) -> TaskItem? {
        store.allTasks.first { $0.habitID == habit.id && dateService.normalize($0.scheduledDate) == day(offset) }
    }

    // MARK: - Moving

    func testMovingTodaysOccurrenceCreatesOneCopyTomorrowLinkedToTheHabit() {
        let habit = makeStore()
        let today = occurrence(habit, 0)!

        store.updateTaskStatus(id: today.id, newStatus: .deferred)

        XCTAssertEqual(occurrence(habit, 0)?.status, .deferred)
        let copy = occurrence(habit, 1)
        XCTAssertNotNil(copy, "the exception should exist tomorrow")
        XCTAssertEqual(copy?.status, .todo)
        XCTAssertEqual(copy?.title, "Gym")
        XCTAssertEqual(copy?.sourceTaskID, today.id)
        XCTAssertEqual(store.allTasks.filter { $0.habitID == habit.id && dateService.normalize($0.scheduledDate) == day(1) }.count, 1)
    }

    func testTheMoveIsAOneOffAndNeverRepeatsOnTheNewWeekday() {
        let habit = makeStore()
        store.updateTaskStatus(id: occurrence(habit, 0)!.id, newStatus: .deferred)

        store.ensureHabitOccurrences()
        store.ensureHabitOccurrences()

        XCTAssertEqual(store.tasks(for: day(1)).filter { $0.habitID == habit.id }.count, 1)
        XCTAssertNil(occurrence(habit, 8), "the following Saturday must stay empty")
        XCTAssertNotNil(occurrence(habit, 7), "next Friday is still scheduled")
        XCTAssertEqual(store.habits.first?.schedule, habit.schedule)
    }

    func testTheMovedCopyCarriesTagsAndCanBeMovedAgain() {
        let habit = makeStore()
        store.addTag("health", to: occurrence(habit, 0)!.id)
        store.updateTaskStatus(id: occurrence(habit, 0)!.id, newStatus: .deferred)
        let copy = occurrence(habit, 1)!
        XCTAssertEqual(copy.tags, ["health"])

        store.updateTaskStatus(id: copy.id, newStatus: .deferred)
        XCTAssertNotNil(occurrence(habit, 2))
    }

    func testBringingItBackRemovesTheUntouchedCopy() {
        let habit = makeStore()
        let today = occurrence(habit, 0)!
        store.updateTaskStatus(id: today.id, newStatus: .deferred)

        store.updateTaskStatus(id: today.id, newStatus: .todo)

        XCTAssertEqual(occurrence(habit, 0)?.status, .todo)
        XCTAssertNil(occurrence(habit, 1))
    }

    func testDailyHabitThatAlreadyHasTomorrowIsSkippedWithoutADuplicate() {
        let habit = makeStore(schedule: .daily, startOffset: -5)
        let today = occurrence(habit, 0)!

        store.updateTaskStatus(id: today.id, newStatus: .deferred)

        XCTAssertEqual(occurrence(habit, 0)?.status, .deferred)
        XCTAssertEqual(store.tasks(for: day(1)).filter { $0.habitID == habit.id }.count, 1,
                       "tomorrow keeps its own single occurrence")
    }

    func testDoneHabitCannotBeMoved() {
        let habit = makeStore()
        let today = occurrence(habit, 0)!
        store.updateTaskStatus(id: today.id, newStatus: .done)
        store.deferTask(id: today.id)
        XCTAssertEqual(occurrence(habit, 0)?.status, .done)
        XCTAssertNil(occurrence(habit, 1))
    }

    // MARK: - Streak

    func testDoingTheMovedCopyKeepsTheStreakAlive() {
        let id = UUID()
        let habit = makeStore(history: [], habitID: id)
        store.updateTaskStatus(id: occurrence(habit, 0)!.id, newStatus: .deferred)
        store.updateTaskStatus(id: occurrence(habit, 1)!.id, newStatus: .done)

        // Friday moved to Saturday and done there: that Friday counts.
        XCTAssertEqual(store.habitStats(for: habit.id).currentStreak, 1)
        XCTAssertEqual(store.habitStats(for: habit.id).completedCount, 1)
    }

    func testAnOpenMovedCopyNeitherBreaksNorCountsYet() {
        let habitID = UUID()
        let probe = Habit(id: habitID, title: "Gym", schedule: .weekly(on: 1), startDate: day(0))
        let weekly = makeStore(history: [
            past(probe, -14, .done), past(probe, -7, .done)
        ], habitID: habitID)
        store.updateTaskStatus(id: occurrence(weekly, 0)!.id, newStatus: .deferred)

        XCTAssertEqual(store.habitStats(for: weekly.id).currentStreak, 2,
                       "the two earlier Fridays stand; the moved one is pending")
    }

    func testAMovedDayFromAWeekAgoCountsOnceItsCopyWasDone() {
        let habitID = UUID()
        let original = UUID(), copy = UUID()
        let probe = Habit(id: habitID, title: "Gym", schedule: .daily, startDate: day(0))
        let habit = makeStore(history: [
            past(probe, -14, .done),
            past(probe, -7, .deferred, id: original, movedTo: copy),
            past(probe, -6, .done, id: copy, from: original)   // done the next day
        ], habitID: habitID)
        // makeStore uses a weekly Friday schedule: the Friday a week ago is a scheduled day.
        XCTAssertEqual(store.habitStats(for: habit.id).currentStreak, 2)
    }

    func testAMovedDayWhoseCopyWasMissedBreaksTheStreak() {
        let habitID = UUID()
        let original = UUID(), copy = UUID()
        let probe = Habit(id: habitID, title: "Gym", schedule: .daily, startDate: day(0))
        let habit = makeStore(history: [
            past(probe, -14, .done),
            past(probe, -7, .deferred, id: original, movedTo: copy),
            past(probe, -6, .todo, id: copy, from: original)   // never done, now in the past
        ], habitID: habitID)
        XCTAssertEqual(store.habitStats(for: habit.id).currentStreak, 0)
        XCTAssertEqual(store.habitStats(for: habit.id).bestStreak, 1)
    }

    func testASkippedDayWithoutACopyIsAMiss() {
        let habitID = UUID()
        let probe = Habit(id: habitID, title: "Stretch", schedule: .daily, startDate: day(0))
        let habit = makeStore(schedule: .daily, startOffset: -3, history: [
            past(probe, -3, .done), past(probe, -2, .done), past(probe, -1, .deferred)
        ], habitID: habitID)
        XCTAssertEqual(store.habitStats(for: habit.id).currentStreak, 0)
        XCTAssertEqual(store.habitStats(for: habit.id).bestStreak, 2)
    }

    // MARK: - Wrap-up

    func testWrapUpStillLeavesHabitsAlone() {
        let habit = makeStore()
        XCTAssertTrue(store.wrapUpCandidates().isEmpty)
        XCTAssertEqual(occurrence(habit, 0)?.status, .todo)
    }
}
