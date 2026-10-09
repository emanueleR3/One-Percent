import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

final class ReminderPlannerTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        calendar = cal
    }

    private func summary(
        total: Int = 5, done: Int = 2, goals: Int = 3, habits: Int = 0,
        theOne: String? = nil, theOneDone: Bool = false, streak: Int = 0, counted: Bool = false
    ) -> DaySummary {
        DaySummary(
            total: total, done: done, remainingGoals: goals, remainingHabits: habits,
            theOneTitle: theOne, theOneDone: theOneDone, streak: streak, isStreakCountedToday: counted
        )
    }

    // MARK: - Wrap-up

    func testWrapUpMentionsHowManyGoalsAreLeft() {
        let content = ReminderPlanner.content(for: .wrapUp, summary: summary(goals: 3), variantSeed: 0)
        XCTAssertEqual(content?.title, "3 goals left")
        XCTAssertFalse(content?.body.isEmpty ?? true)
    }

    func testWrapUpSingularForOneGoal() {
        let content = ReminderPlanner.content(for: .wrapUp, summary: summary(goals: 1), variantSeed: 0)
        XCTAssertEqual(content?.title, "1 goal left")
    }

    func testWrapUpWarnsAboutAnEndangeredStreak() {
        let content = ReminderPlanner.content(
            for: .wrapUp,
            summary: summary(total: 3, done: 0, goals: 3, streak: 9, counted: false),
            variantSeed: 0
        )
        XCTAssertTrue(content?.body.contains("9-day streak") ?? false)
    }

    func testWrapUpFallsBackToHabitsWhenNoGoalsAreLeft() {
        let content = ReminderPlanner.content(for: .wrapUp, summary: summary(done: 4, goals: 0, habits: 2), variantSeed: 0)
        XCTAssertEqual(content?.title, "2 habits still open")
    }

    func testWrapUpIsSilentWhenEverythingIsDone() {
        XCTAssertNil(ReminderPlanner.content(for: .wrapUp, summary: summary(total: 4, done: 4, goals: 0), variantSeed: 0))
    }

    func testWrapUpIsSilentWhenNothingWasPlanned() {
        XCTAssertNil(ReminderPlanner.content(for: .wrapUp, summary: summary(total: 0, done: 0, goals: 0), variantSeed: 0))
    }

    // MARK: - Morning

    func testMorningNamesTheOneWhenSet() {
        let content = ReminderPlanner.content(for: .morning, summary: summary(theOne: "Ship the release"), variantSeed: 0)
        XCTAssertTrue(content?.body.contains("Ship the release") ?? false)
    }

    func testMorningAsksToPlanWhenNothingIsScheduled() {
        let content = ReminderPlanner.content(for: .morning, summary: summary(total: 0, done: 0, goals: 0), variantSeed: 0)
        XCTAssertNotNil(content)
        XCTAssertFalse(content?.body.contains("0 goals") ?? true)
    }

    func testMorningCountsGoalsOtherwise() {
        let content = ReminderPlanner.content(for: .morning, summary: summary(total: 4, done: 0, goals: 4), variantSeed: 0)
        XCTAssertTrue(content?.body.contains("4 goals") ?? false)
    }

    // MARK: - Afternoon

    func testAfternoonReportsProgress() {
        let content = ReminderPlanner.content(for: .afternoon, summary: summary(total: 5, done: 2, goals: 3), variantSeed: 0)
        XCTAssertTrue(content?.title.contains("2 of 5") ?? false)
    }

    func testAfternoonIsSilentWhenDayIsDoneOrEmpty() {
        XCTAssertNil(ReminderPlanner.content(for: .afternoon, summary: summary(total: 3, done: 3, goals: 0), variantSeed: 0))
        XCTAssertNil(ReminderPlanner.content(for: .afternoon, summary: summary(total: 0, done: 0, goals: 0), variantSeed: 0))
    }

    // MARK: - Variants

    func testVariantsRotateWithTheSeedButStayDeterministic() {
        let s = summary(total: 4, done: 0, goals: 4)
        let a = ReminderPlanner.content(for: .morning, summary: s, variantSeed: 0)
        let b = ReminderPlanner.content(for: .morning, summary: s, variantSeed: 1)
        let a2 = ReminderPlanner.content(for: .morning, summary: s, variantSeed: 0)
        XCTAssertEqual(a, a2)
        XCTAssertNotEqual(a?.body, b?.body)
    }

    // MARK: - Fire dates

    func testNextFireDatesStartTodayWhenTheTimeIsStillAhead() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8, minute: 30))!
        let dates = ReminderPlanner.fireDates(minutes: 9 * 60, now: now, calendar: calendar, days: 2)
        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 9)
        XCTAssertEqual(calendar.component(.hour, from: dates[0]), 9)
        XCTAssertEqual(calendar.component(.day, from: dates[1]), 10)
    }

    func testFireDatesSkipTodayWhenTheTimeHasPassed() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 21, minute: 30))!
        let dates = ReminderPlanner.fireDates(minutes: 21 * 60, now: now, calendar: calendar, days: 2)
        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 10)
        XCTAssertEqual(calendar.component(.day, from: dates[1]), 11)
    }

    func testMinutesFormattingAndClamping() {
        XCTAssertEqual(ReminderPlanner.clockString(minutes: 9 * 60 + 5), "09:05")
        XCTAssertEqual(ReminderPlanner.clockString(minutes: 21 * 60), "21:00")
        XCTAssertEqual(ReminderPlanner.clampMinutes(-30), 0)
        XCTAssertEqual(ReminderPlanner.clampMinutes(24 * 60 + 15), 24 * 60 - 1)
    }
}
