import XCTest
@testable import OnePercent

@MainActor
final class TaskStoreDailyFlowTests: XCTestCase {
    private var tasksPersistence: MockTaskPersistence!
    private var habitPersistence: InMemoryHabitPersistence!
    private var dateService: DateService!
    private var calendar: Calendar!
    private var store: TaskStore!

    override func setUp() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        calendar = cal
        tasksPersistence = MockTaskPersistence()
        habitPersistence = InMemoryHabitPersistence()
        dateService = DateService(calendar: cal)
        store = TaskStore(persistence: tasksPersistence, dateService: dateService, habitPersistence: habitPersistence)
    }

    private func day(_ offset: Int) -> Date {
        dateService.normalize(calendar.date(byAdding: .day, value: offset, to: dateService.today)!)
    }

    private func add(_ title: String, offset: Int = 0, status: TaskStatus = .todo) -> TaskItem {
        let task = store.addTask(title: title, for: day(offset))!
        if status != .todo { store.updateTaskStatus(id: task.id, newStatus: status) }
        return store.allTasks.first { $0.id == task.id }!
    }

    private func task(_ id: UUID) -> TaskItem {
        store.allTasks.first { $0.id == id }!
    }

    // MARK: - Tags

    func testAddTaskNormalizesAndDeduplicatesTags() {
        let t = store.addTask(title: "Write", tags: ["#Work", "work", " Deep Work "])!
        XCTAssertEqual(t.tags, ["work", "deep-work"])
    }

    func testAddAndRemoveTagOnExistingGoal() {
        let t = add("Write")
        store.addTag("#Family", to: t.id)
        store.addTag("family", to: t.id)
        XCTAssertEqual(task(t.id).tags, ["family"])
        store.removeTag("family", from: t.id)
        XCTAssertTrue(task(t.id).tags.isEmpty)
    }

    func testInvalidTagIsIgnored() {
        let t = add("Write")
        store.addTag("   ", to: t.id)
        XCTAssertTrue(task(t.id).tags.isEmpty)
    }

    func testAllTagNamesAreOrderedByUsage() {
        let a = add("a"), b = add("b"), c = add("c")
        store.addTag("home", to: a.id)
        store.addTag("work", to: a.id)
        store.addTag("work", to: b.id)
        store.addTag("work", to: c.id)
        store.addTag("home", to: b.id)
        store.addTag("zen", to: c.id)
        XCTAssertEqual(store.allTagNames, ["work", "home", "zen"])
    }

    func testDeleteTagEverywhereStripsGoalsAndHabits() {
        let a = add("a")
        store.addTag("work", to: a.id)
        store.addHabit(title: "Gym", schedule: .daily, tags: ["work"], startDate: day(0))
        store.deleteTagEverywhere("work")
        XCTAssertTrue(store.allTasks.allSatisfy { !$0.tags.contains("work") })
        XCTAssertTrue(store.habits.allSatisfy { !$0.tags.contains("work") })
    }

    // MARK: - Notes

    func testNoteIsTrimmedAndClearedWhenEmpty() {
        let t = add("a")
        store.updateNote(id: t.id, note: "  call before 5pm  ")
        XCTAssertEqual(task(t.id).note, "call before 5pm")
        store.updateNote(id: t.id, note: "   ")
        XCTAssertNil(task(t.id).note)
    }

    // MARK: - Subtasks

    func testSubtaskLifecycle() {
        let t = add("Trip")
        store.addSubtask(to: t.id, title: " Book flights ")
        store.addSubtask(to: t.id, title: "   ")
        XCTAssertEqual(task(t.id).subtasks.map(\.title), ["Book flights"])

        let sid = task(t.id).subtasks[0].id
        store.toggleSubtask(taskID: t.id, subtaskID: sid)
        XCTAssertEqual(task(t.id).subtaskProgress.done, 1)

        store.renameSubtask(taskID: t.id, subtaskID: sid, title: "Book trains")
        XCTAssertEqual(task(t.id).subtasks[0].title, "Book trains")

        store.deleteSubtask(taskID: t.id, subtaskID: sid)
        XCTAssertTrue(task(t.id).subtasks.isEmpty)
    }

    func testSubtasksDoNotChangeDayProgress() {
        let t = add("Trip")
        store.addSubtask(to: t.id, title: "x")
        XCTAssertEqual(store.currentProgress.totalCount, 1)
    }

    // MARK: - The One

    func testSettingTheOneClearsThePreviousOneOnTheSameDay() {
        let a = add("a"), b = add("b")
        store.setTheOne(id: a.id)
        store.setTheOne(id: b.id)
        XCTAssertFalse(task(a.id).isTheOne)
        XCTAssertTrue(task(b.id).isTheOne)
        XCTAssertEqual(store.theOne(for: day(0))?.id, b.id)
    }

    func testTheOneMovesToTheTopOfTheList() {
        _ = add("a"); _ = add("b")
        let c = add("c")
        store.setTheOne(id: c.id)
        XCTAssertEqual(store.selectedDateTasks.first?.id, c.id)
    }

    func testTheOneOnDifferentDaysIsIndependent() {
        let today = add("today", offset: 0)
        let tomorrow = add("tomorrow", offset: 1)
        store.setTheOne(id: today.id)
        store.setTheOne(id: tomorrow.id)
        XCTAssertTrue(task(today.id).isTheOne)
        XCTAssertTrue(task(tomorrow.id).isTheOne)
    }

    func testToggleTheOneOffAndOn() {
        let a = add("a")
        store.toggleTheOne(id: a.id)
        XCTAssertTrue(task(a.id).isTheOne)
        store.toggleTheOne(id: a.id)
        XCTAssertFalse(task(a.id).isTheOne)
        XCTAssertNil(store.theOne(for: day(0)))
    }

    func testDeferredGoalCannotBeTheOne() {
        let a = add("a", status: .deferred)
        store.setTheOne(id: a.id)
        XCTAssertFalse(task(a.id).isTheOne)
    }

    func testDeferringTheOneDoesNotCarryTheFlagButCarriesDetails() {
        let a = add("a")
        store.addTag("work", to: a.id)
        store.updateNote(id: a.id, note: "details")
        store.addSubtask(to: a.id, title: "step")
        store.setTheOne(id: a.id)

        store.deferTask(id: a.id)

        XCTAssertNil(store.theOne(for: day(0)))
        let copy = store.allTasks.first { $0.sourceTaskID == a.id }!
        XCTAssertFalse(copy.isTheOne)
        XCTAssertEqual(copy.tags, ["work"])
        XCTAssertEqual(copy.note, "details")
        XCTAssertEqual(copy.subtasks.map(\.title), ["step"])
    }

    // MARK: - Habits

    func testAddingAHabitCreatesTodayAndUpcomingOccurrences() {
        let habit = store.addHabit(title: "Read", schedule: .daily, tags: ["mind"], startDate: day(0))!
        let occurrences = store.allTasks.filter { $0.habitID == habit.id }
        XCTAssertEqual(occurrences.count, 8) // today + 7 days ahead
        XCTAssertTrue(occurrences.allSatisfy { $0.status == .todo && $0.tags == ["mind"] })
        XCTAssertEqual(habitPersistence.stored.count, 1)
    }

    func testEnsureOccurrencesIsIdempotent() {
        store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(0))
        let before = store.allTasks.count
        store.ensureHabitOccurrences()
        store.ensureHabitOccurrences()
        XCTAssertEqual(store.allTasks.count, before)
    }

    func testWeekdayHabitSkipsTheWeekend() {
        store.addHabit(title: "Standup", schedule: .weekdays, tags: [], startDate: day(0))
        for occurrence in store.allTasks where occurrence.habitID != nil {
            let weekday = calendar.component(.weekday, from: occurrence.scheduledDate)
            XCTAssertTrue((2...6).contains(weekday), "weekday \(weekday)")
        }
    }

    func testWeeklyHabitAppearsOncePerWeek() {
        let weekday = calendar.component(.weekday, from: day(0))
        store.addHabit(title: "Review", schedule: .weekly(on: weekday), tags: [], startDate: day(0))
        let count = store.allTasks.filter { $0.habitID != nil }.count
        XCTAssertEqual(count, 2) // today and +7
    }

    func testHabitDoesNotCreateOccurrencesBeforeItsStartDate() {
        store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(3))
        XCTAssertTrue(store.allTasks.allSatisfy { $0.scheduledDate >= day(3) })
    }

    func testDeletingAnOccurrenceSkipsThatDayInsteadOfRecreatingIt() {
        let habit = store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(0))!
        let tomorrow = store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == day(1) }!
        store.deleteTask(id: tomorrow.id)
        store.ensureHabitOccurrences()
        XCTAssertNil(store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == day(1) })
        XCTAssertEqual(store.habits.first?.skippedDays.map { dateService.normalize($0) }, [day(1)])
    }

    func testDeletingAHabitRemovesOpenOccurrencesButKeepsDoneOnes() {
        let habit = store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(0))!
        let today = store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == day(0) }!
        store.updateTaskStatus(id: today.id, newStatus: .done)

        store.deleteHabit(id: habit.id)

        XCTAssertTrue(store.habits.isEmpty)
        XCTAssertEqual(store.allTasks.filter { $0.title == "Read" }.count, 1)
        XCTAssertNil(store.allTasks.first { $0.title == "Read" }?.habitID)
        XCTAssertEqual(habitPersistence.stored.count, 0)
    }

    func testHabitStatsReflectCompletedOccurrences() {
        let habit = store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(-2))!
        for offset in [-2, -1, 0] {
            if let t = store.allTasks.first(where: { $0.habitID == habit.id && $0.scheduledDate == day(offset) }) {
                store.updateTaskStatus(id: t.id, newStatus: .done)
            }
        }
        XCTAssertEqual(store.habitStats(for: habit.id).currentStreak, 3)
    }

    func testHabitsAreRestoredAndMaterializedOnLaunch() {
        let habit = store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(0))!
        let reopened = TaskStore(persistence: tasksPersistence, dateService: dateService, habitPersistence: habitPersistence)
        XCTAssertEqual(reopened.habits.map(\.id), [habit.id])
        XCTAssertEqual(reopened.allTasks.filter { $0.habitID == habit.id }.count, 8)
    }

    // MARK: - Wrap-up

    func testWrapUpCandidatesAreOpenGoalsWithoutHabits() {
        _ = add("todo"); _ = add("doing", status: .inProgress); _ = add("done", status: .done)
        _ = add("later", status: .deferred)
        store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(0))
        XCTAssertEqual(Set(store.wrapUpCandidates().map(\.title)), ["todo", "doing"])
    }

    func testDeferRemainingMovesOpenGoalsToTomorrowAndCanBeUndone() {
        let a = add("a"), b = add("b", status: .inProgress), done = add("done", status: .done)

        let moved = store.deferRemaining()

        XCTAssertEqual(Set(moved), [a.id, b.id])
        XCTAssertEqual(task(a.id).status, .deferred)
        XCTAssertEqual(task(done.id).status, .done)
        XCTAssertEqual(store.tasks(for: day(1)).map(\.title).sorted(), ["a", "b"])

        store.undoDeferral(ids: moved)

        XCTAssertEqual(task(a.id).status, .todo)
        XCTAssertTrue(store.tasks(for: day(1)).isEmpty)
    }

    func testDaySummaryCounts() {
        _ = add("a"); _ = add("b", status: .done)
        let c = add("c")
        store.setTheOne(id: c.id)
        store.addHabit(title: "Read", schedule: .daily, tags: [], startDate: day(0))

        let summary = store.daySummary(for: day(0))

        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.remainingGoals, 2)
        XCTAssertEqual(summary.remainingHabits, 1)
        XCTAssertEqual(summary.theOneTitle, "c")
        XCTAssertFalse(summary.theOneDone)
        XCTAssertEqual(summary.streak, 1)
        XCTAssertTrue(summary.isStreakCountedToday)
    }

    // MARK: - Backward compatibility

    func testTasksSavedByOlderVersionsStillDecode() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","title":"Old","status":"todo","scheduledDate":"2026-10-09T00:00:00Z",
          "createdAt":"2026-10-09T00:00:00Z","updatedAt":"2026-10-09T00:00:00Z","sortOrder":2}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tasks = try decoder.decode([TaskItem].self, from: Data(json.utf8))
        XCTAssertEqual(tasks.first?.title, "Old")
        XCTAssertEqual(tasks.first?.tags, [])
        XCTAssertNil(tasks.first?.note)
        XCTAssertEqual(tasks.first?.subtasks, [])
        XCTAssertEqual(tasks.first?.isTheOne, false)
        XCTAssertNil(tasks.first?.habitID)
    }

    // MARK: - Custom repeat days

    /// Weekday number of the day `offset` days from today. Tests use these instead of fixed
    /// weekdays so they pass whichever day they run on.
    private func weekday(_ offset: Int) -> Int {
        calendar.component(.weekday, from: day(offset))
    }

    func testCustomHabitOnlyCreatesOccurrencesOnItsDays() {
        let days = [weekday(0), weekday(2), weekday(4)]
        let habit = store.addHabit(title: "Gym", schedule: .custom(days: days), startDate: day(0))!
        let weekdays = store.allTasks.filter { $0.habitID == habit.id }
            .map { calendar.component(.weekday, from: $0.scheduledDate) }
        XCTAssertFalse(weekdays.isEmpty)
        XCTAssertTrue(weekdays.allSatisfy { days.contains($0) })
    }

    func testChangingTheDaysRebuildsFutureOccurrencesButKeepsHistory() {
        let habit = store.addHabit(title: "Gym", schedule: .custom(days: [weekday(0), weekday(2), weekday(4)]), startDate: day(0))!
        let todayOccurrence = store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == day(0) }!
        let newDays = [weekday(1), weekday(3)]

        store.updateHabitSchedule(id: habit.id, schedule: .custom(days: newDays))

        let weekdays = Set(store.allTasks.filter { $0.habitID == habit.id }
            .map { calendar.component(.weekday, from: $0.scheduledDate) })
        XCTAssertEqual(weekdays, Set(newDays), "open occurrences on the old days are gone, the new days exist")
        XCTAssertNil(store.allTasks.first { $0.id == todayOccurrence.id }, "today's untouched occurrence no longer applies")
        XCTAssertEqual(store.habits.first?.schedule, .custom(days: newDays))
    }

    func testChangingTheDaysKeepsDoneOccurrences() {
        let habit = store.addHabit(title: "Gym", schedule: .custom(days: [weekday(0), weekday(2)]), startDate: day(0))!
        let today = store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == day(0) }!
        store.updateTaskStatus(id: today.id, newStatus: .done)

        store.updateHabitSchedule(id: habit.id, schedule: .custom(days: [weekday(1)]))

        XCTAssertEqual(store.allTasks.first { $0.id == today.id }?.status, .done)
    }

    func testChangingTheDaysKeepsOccurrencesTheUserInvestedIn() {
        let habit = store.addHabit(title: "Gym", schedule: .custom(days: [weekday(0), weekday(2)]), startDate: day(0))!
        let today = store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == day(0) }!
        store.updateNote(id: today.id, note: "bring the red shoes")

        store.updateHabitSchedule(id: habit.id, schedule: .custom(days: [weekday(1)]))

        XCTAssertNotNil(store.allTasks.first { $0.id == today.id })
    }

    func testChangingTheDaysKeepsAMovedExceptionCopy() {
        let habit = store.addHabit(title: "Gym", schedule: .custom(days: [weekday(0), weekday(2)]), startDate: day(0))!
        let today = store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == day(0) }!
        store.updateTaskStatus(id: today.id, newStatus: .deferred)
        let copy = store.allTasks.first { $0.sourceTaskID == today.id }!

        store.updateHabitSchedule(id: habit.id, schedule: .custom(days: [weekday(3)]))

        XCTAssertNotNil(store.allTasks.first { $0.id == copy.id }, "a one-off exception is not part of the schedule")
    }

    func testSettingTheSameScheduleChangesNothing() {
        let days = [weekday(0), weekday(2), weekday(4)]
        let habit = store.addHabit(title: "Gym", schedule: .custom(days: days), startDate: day(0))!
        let before = store.allTasks.map(\.id)
        store.updateHabitSchedule(id: habit.id, schedule: .custom(days: days.reversed()))
        XCTAssertEqual(store.allTasks.map(\.id), before)
    }
}
