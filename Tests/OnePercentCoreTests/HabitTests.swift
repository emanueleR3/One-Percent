import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

final class HabitTests: XCTestCase {
    private var calendar: Calendar!
    private var today: Date! // Friday, 9 Oct 2026

    override func setUp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        cal.locale = Locale(identifier: "en_US")
        calendar = cal
        today = cal.date(from: DateComponents(year: 2026, month: 10, day: 9))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func habit(_ schedule: HabitSchedule, start: Int, skipped: [Int] = []) -> Habit {
        Habit(title: "Read", schedule: schedule, startDate: day(start), skippedDays: skipped.map(day))
    }

    // MARK: - Schedule

    func testDailyScheduleMatchesEveryDay() {
        for offset in -3...3 { XCTAssertTrue(HabitSchedule.daily.isScheduled(on: day(offset), calendar: calendar)) }
    }

    func testWeekdaysScheduleSkipsSaturdayAndSunday() {
        XCTAssertTrue(HabitSchedule.weekdays.isScheduled(on: day(0), calendar: calendar))   // Fri
        XCTAssertFalse(HabitSchedule.weekdays.isScheduled(on: day(1), calendar: calendar))  // Sat
        XCTAssertFalse(HabitSchedule.weekdays.isScheduled(on: day(2), calendar: calendar))  // Sun
        XCTAssertTrue(HabitSchedule.weekdays.isScheduled(on: day(3), calendar: calendar))   // Mon
    }

    func testWeeklyScheduleMatchesOnlyItsWeekday() {
        let fridays = HabitSchedule.weekly(on: 6)
        XCTAssertTrue(fridays.isScheduled(on: day(0), calendar: calendar))
        XCTAssertTrue(fridays.isScheduled(on: day(-7), calendar: calendar))
        XCTAssertFalse(fridays.isScheduled(on: day(-1), calendar: calendar))
    }

    func testScheduleLabels() {
        XCTAssertEqual(HabitSchedule.daily.label(calendar: calendar), "Every day")
        XCTAssertEqual(HabitSchedule.weekdays.label(calendar: calendar), "Weekdays")
        XCTAssertEqual(HabitSchedule.weekly(on: 6).label(calendar: calendar), "Every Friday")
    }

    func testHabitSchedulesRoundTripThroughJSON() throws {
        let original = Habit(title: "Gym", schedule: .weekly(on: 3), startDate: today)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Habit.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Streaks

    func testStreakCountsConsecutiveDoneScheduledDays() {
        let h = habit(.daily, start: -10)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-1): .done, day(-2): .done, day(-3): .todo],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 3)
    }

    func testPendingTodayDoesNotBreakTheStreak() {
        let h = habit(.daily, start: -10)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .todo, day(-1): .done, day(-2): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 2)
    }

    func testMissedYesterdayResetsTheStreak() {
        let h = habit(.daily, start: -10)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-1): .todo, day(-2): .done, day(-3): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.bestStreak, 2)
    }

    func testMissingOccurrenceCountsAsMissed() {
        let h = habit(.daily, start: -10)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-2): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 1)
    }

    func testWeekdayHabitIgnoresTheWeekendInItsStreak() {
        // Today is Friday. Scheduled days going back: Fri, Thu, Wed, Tue, Mon, then Fri (-7): the weekend
        // (-5, -6) is not scheduled so it cannot break the run; Thu (-8) is not done and ends it.
        let h = habit(.weekdays, start: -14)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-1): .done, day(-2): .done, day(-3): .done, day(-4): .done, day(-7): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 6)
    }

    func testWeeklyHabitStreakCountsWeeks() {
        let h = habit(.weekly(on: 6), start: -30) // Fridays
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-7): .done, day(-14): .done, day(-21): .todo],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 3)
    }

    func testSkippedDaysNeitherCountNorBreak() {
        let h = habit(.daily, start: -10, skipped: [-1])
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-2): .done, day(-3): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 3)
    }

    func testDaysBeforeStartDoNotBreakTheStreak() {
        let h = habit(.daily, start: -2)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-1): .done, day(-2): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 3)
        XCTAssertEqual(stats.bestStreak, 3)
    }

    func testBestStreakAcrossHistory() {
        let h = habit(.daily, start: -20)
        var occ: [Date: TaskStatus] = [:]
        for offset in -12...(-5) { occ[day(offset)] = .done } // 8 in a row
        occ[day(0)] = .done
        let stats = HabitCalculator.stats(for: h, occurrences: occ, today: today, calendar: calendar)
        XCTAssertEqual(stats.bestStreak, 8)
        XCTAssertEqual(stats.currentStreak, 1)
    }

    func testCompletionRateOverLastThirtyDaysIgnoresPendingToday() {
        let h = habit(.daily, start: -3)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .todo, day(-1): .done, day(-2): .todo, day(-3): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.rate30 ?? -1, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testRateIsNilWhenNothingWasDueYet() {
        let h = habit(.daily, start: 0)
        let stats = HabitCalculator.stats(for: h, occurrences: [day(0): .todo], today: today, calendar: calendar)
        XCTAssertNil(stats.rate30)
        XCTAssertEqual(stats.currentStreak, 0)
    }

    // MARK: - Moved occurrences

    func testMovedDayIsNeutralAndNeitherBreaksNorExtendsTheStreak() {
        // Friday (today) done, Thursday moved elsewhere, Wednesday and Tuesday done.
        let h = habit(.daily, start: -10)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-1): .deferred, day(-2): .done, day(-3): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 3)
        XCTAssertEqual(stats.bestStreak, 3)
    }

    func testMovedDayDoesNotCountTowardsTheRate() {
        let h = habit(.daily, start: -3)
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(-1): .deferred, day(-2): .done, day(-3): .todo],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.rate30 ?? -1, 0.5, accuracy: 0.0001)
    }

    // MARK: - Custom days

    func testCustomScheduleMatchesOnlyTheChosenWeekdays() {
        let mwf = HabitSchedule.custom(days: [2, 4, 6])
        XCTAssertEqual(mwf.kind, .custom)
        XCTAssertTrue(mwf.isScheduled(on: day(0), calendar: calendar))    // Fri
        XCTAssertFalse(mwf.isScheduled(on: day(1), calendar: calendar))   // Sat
        XCTAssertTrue(mwf.isScheduled(on: day(3), calendar: calendar))    // Mon
        XCTAssertFalse(mwf.isScheduled(on: day(4), calendar: calendar))   // Tue
        XCTAssertTrue(mwf.isScheduled(on: day(5), calendar: calendar))    // Wed
    }

    func testCustomDaysAreCanonicalised() {
        XCTAssertEqual(HabitSchedule.custom(days: [1, 2, 3, 4, 5, 6, 7]), .daily)
        XCTAssertEqual(HabitSchedule.custom(days: [6, 5, 4, 3, 2, 2]), .weekdays)
        XCTAssertEqual(HabitSchedule.custom(days: [6]), .weekly(on: 6))
        XCTAssertEqual(HabitSchedule.custom(days: [6, 9, 0, -1]), .weekly(on: 6), "out-of-range days are dropped")
        XCTAssertEqual(HabitSchedule.custom(days: [6, 2, 4]).days, [2, 4, 6], "sorted and de-duplicated")
        XCTAssertEqual(HabitSchedule.custom(days: []), .daily, "nothing chosen falls back to every day")
    }

    func testSelectedDaysDescribeEveryKind() {
        XCTAssertEqual(HabitSchedule.daily.selectedDays, Set(1...7))
        XCTAssertEqual(HabitSchedule.weekdays.selectedDays, Set(2...6))
        XCTAssertEqual(HabitSchedule.weekly(on: 3).selectedDays, [3])
        XCTAssertEqual(HabitSchedule.custom(days: [2, 4, 6]).selectedDays, [2, 4, 6])
    }

    func testCustomLabelListsDaysFromTheCalendarsFirstWeekday() {
        // firstWeekday is Monday in this test calendar, so Sunday (1) sorts last.
        XCTAssertEqual(HabitSchedule.custom(days: [2, 4, 6]).label(calendar: calendar), "Mon, Wed, Fri")
        XCTAssertEqual(HabitSchedule.custom(days: [1, 2, 4]).label(calendar: calendar), "Mon, Wed, Sun")
    }

    func testCustomScheduleRoundTripsAndOldFilesStillDecode() throws {
        let original = Habit(title: "Gym", schedule: .custom(days: [2, 4, 6]), startDate: today)
        let decoded = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.schedule, original.schedule)
        XCTAssertEqual(decoded.schedule.days, [2, 4, 6])

        // A habit saved by v0.0.2-era code: no `days` key at all.
        let old = """
        {"id":"\(UUID().uuidString)","title":"Read","schedule":{"kind":"weekly","weekday":6},
         "startDate":"2026-10-09T00:00:00Z","createdAt":"2026-10-09T00:00:00Z","tags":[],"skippedDays":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let habit = try decoder.decode(Habit.self, from: Data(old.utf8))
        XCTAssertEqual(habit.schedule, .weekly(on: 6))
    }

    func testCustomHabitStreakFollowsOnlyItsDays() {
        // Mon/Wed/Fri habit, today is Friday. Fri, Wed, Mon done; the Tuesday/Thursday gaps are irrelevant.
        let h = Habit(title: "Gym", schedule: .custom(days: [2, 4, 6]), startDate: day(-10))
        let stats = HabitCalculator.stats(
            for: h,
            occurrences: [day(0): .done, day(-2): .done, day(-4): .done],
            today: today, calendar: calendar
        )
        XCTAssertEqual(stats.currentStreak, 3)
    }
}
