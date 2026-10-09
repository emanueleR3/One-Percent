import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

final class TrackingCalculatorTests: XCTestCase {
    private var calendar: Calendar!
    private var today: Date!

    override func setUp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday
        calendar = cal
        // Friday, 9 Oct 2026
        today = cal.date(from: DateComponents(year: 2026, month: 10, day: 9))!
    }

    // MARK: - Helpers

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func task(
        _ offset: Int,
        _ status: TaskStatus,
        id: UUID = UUID(),
        source: UUID? = nil
    ) -> TaskItem {
        TaskItem(id: id, title: "t", status: status, scheduledDate: day(offset), sourceTaskID: source)
    }

    private func summary(_ tasks: [TaskItem]) -> TrackingSummary {
        let stats = TrackingCalculator.dayStats(for: tasks, calendar: calendar)
        return TrackingCalculator.summary(dayStats: stats, today: today, calendar: calendar)
    }

    // MARK: - Day stats

    func testDayStatsExcludeDeferredFromTotalButCountThem() {
        let stats = TrackingCalculator.dayStats(
            for: [task(0, .done), task(0, .todo), task(0, .deferred)],
            calendar: calendar
        )
        let d = stats[day(0)]
        XCTAssertEqual(d?.completed, 1)
        XCTAssertEqual(d?.total, 2)
        XCTAssertEqual(d?.deferred, 1)
        XCTAssertEqual(d?.ratio ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertTrue(d?.isActive ?? false)
        XCTAssertFalse(d?.isPerfect ?? true)
    }

    func testDayWithOnlyDeferredGoalsIsNeitherActiveNorPerfect() {
        let stats = TrackingCalculator.dayStats(for: [task(0, .deferred)], calendar: calendar)
        XCTAssertFalse(stats[day(0)]?.isActive ?? true)
        XCTAssertFalse(stats[day(0)]?.isPerfect ?? true)
        XCTAssertTrue(stats[day(0)]?.hasGoals ?? false)
    }

    func testPerfectDayNeedsAtLeastOneNonDeferredGoalAllDone() {
        let stats = TrackingCalculator.dayStats(for: [task(0, .done), task(0, .done), task(0, .deferred)], calendar: calendar)
        XCTAssertTrue(stats[day(0)]?.isPerfect ?? false)
    }

    // MARK: - Streaks

    func testCurrentStreakCountsConsecutiveActiveDaysEndingToday() {
        let s = summary([task(0, .done), task(-1, .done), task(-2, .done), task(-4, .done)])
        XCTAssertEqual(s.currentStreak, 3)
        XCTAssertTrue(s.isTodayCounted)
    }

    func testStreakStaysAliveWhenTodayHasNoCompletionYet() {
        let s = summary([task(0, .todo), task(-1, .done), task(-2, .done)])
        XCTAssertEqual(s.currentStreak, 2)
        XCTAssertFalse(s.isTodayCounted)
    }

    func testStreakIsZeroWhenYesterdayAndTodayAreInactive() {
        let s = summary([task(-2, .done), task(-3, .done)])
        XCTAssertEqual(s.currentStreak, 0)
    }

    func testStreakIgnoresFutureDays() {
        let s = summary([task(0, .done), task(1, .done), task(2, .done)])
        XCTAssertEqual(s.currentStreak, 1)
    }

    func testBestStreakFindsLongestRunAcrossGaps() {
        let s = summary([
            task(0, .done),
            task(-3, .done), task(-4, .done), task(-5, .done), task(-6, .done),
            task(-10, .done), task(-11, .done)
        ])
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertEqual(s.bestStreak, 4)
    }

    func testBestStreakNeverLowerThanCurrent() {
        let s = summary([task(0, .done), task(-1, .done)])
        XCTAssertEqual(s.bestStreak, 2)
    }

    // MARK: - Rates and averages

    func testRatesAreCompletedOverNonDeferredGoalsInWindow() {
        // Last 7 days: 3 done of 4. A day 20 days ago adds 1 of 4 to the 30-day window only.
        let s = summary([
            task(0, .done), task(0, .done), task(-1, .done), task(-1, .todo),
            task(-20, .done), task(-20, .todo), task(-20, .todo), task(-20, .todo)
        ])
        XCTAssertEqual(s.rate7 ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(s.rate30 ?? -1, 4.0 / 8.0, accuracy: 0.0001)
    }

    func testRateIsNilWithoutGoalsInWindow() {
        let s = summary([task(-20, .done)])
        XCTAssertNil(s.rate7)
        XCTAssertNotNil(s.rate30)
    }

    func testAveragePerDayUsesHistoryLengthWhenShorterThanThirtyDays() {
        // History starts 3 days ago (4 days inclusive); 8 goals done across them.
        var tasks: [TaskItem] = []
        for offset in [-3, -2, -1, 0] { tasks += [task(offset, .done), task(offset, .done)] }
        let s = summary(tasks)
        XCTAssertEqual(s.averagePerDay, 2.0, accuracy: 0.0001)
    }

    func testAveragePerDayIsZeroWithoutHistory() {
        XCTAssertEqual(summary([]).averagePerDay, 0, accuracy: 0.0001)
    }

    // MARK: - Best weekday

    func testBestWeekdayPicksHighestAverageRatioWithAtLeastTwoSamples() {
        // today = Friday. Fridays: today (-0) and -7. Thursdays: -1 and -8.
        let s = summary([
            task(0, .done), task(-7, .done),                 // Fridays: 100%
            task(-1, .done), task(-1, .todo),                // Thursday: 50%
            task(-8, .todo), task(-8, .todo)                 // Thursday: 0%
        ])
        XCTAssertEqual(s.bestWeekday?.weekday, 6) // Friday
        XCTAssertEqual(s.bestWeekday?.averageRatio ?? 0, 1.0, accuracy: 0.0001)
    }

    func testBestWeekdayIsNilWithoutTwoSamplesOnAnyWeekday() {
        let s = summary([task(0, .done), task(-1, .done)])
        XCTAssertNil(s.bestWeekday)
    }

    // MARK: - 1% score

    func testScoreGrowsOnePercentPerPerfectDay() {
        let s = summary([
            task(0, .done),                       // perfect
            task(-1, .done), task(-1, .todo),     // not perfect
            task(-2, .done), task(-2, .done)      // perfect
        ])
        XCTAssertEqual(s.perfectDays, 2)
        XCTAssertEqual(s.score, pow(1.01, 2), accuracy: 0.000001)
    }

    func testScoreIsOneWithNoPerfectDays() {
        XCTAssertEqual(summary([task(0, .todo)]).score, 1.0, accuracy: 0.000001)
    }

    func testScoreCurveIsCumulativeAndEndsAtScore() {
        let s = summary([task(-2, .done), task(0, .done)])
        XCTAssertEqual(s.scoreCurve.count, 60)
        XCTAssertEqual(s.scoreCurve.last ?? 0, s.score, accuracy: 0.000001)
        XCTAssertEqual(s.scoreCurve.first ?? 0, 1.0, accuracy: 0.000001)
        XCTAssertEqual(s.scoreCurve[57], 1.01, accuracy: 0.000001) // -2 days
        XCTAssertEqual(s.scoreCurve[58], 1.01, accuracy: 0.000001) // -1 day (no new perfect day)
        XCTAssertEqual(s.scoreCurve[59], pow(1.01, 2), accuracy: 0.000001)
    }

    func testPerfectDaysBeforeTheCurveWindowStillCount() {
        let s = summary([task(-100, .done), task(0, .todo)])
        XCTAssertEqual(s.perfectDays, 1)
        XCTAssertEqual(s.scoreCurve.first ?? 0, 1.01, accuracy: 0.000001)
    }

    // MARK: - Week strip & heatmap

    func testWeekStripCoversSevenDaysEndingToday() {
        let s = summary([task(-6, .done), task(0, .todo)])
        XCTAssertEqual(s.week.count, 7)
        XCTAssertEqual(s.week.first?.date, day(-6))
        XCTAssertEqual(s.week.last?.date, day(0))
        XCTAssertEqual(s.week.first?.completed, 1)
        XCTAssertEqual(s.week[3].hasGoals, false)
    }

    func testHeatmapHasTwelveWeekColumnsOfSevenRowsAlignedToFirstWeekday() {
        let s = summary([task(0, .done)])
        XCTAssertEqual(s.heatmap.count, 12)
        XCTAssertTrue(s.heatmap.allSatisfy { $0.count == 7 })
        // Monday-first: today is Friday => row 4 of the last column; Sat/Sun rows are future.
        XCTAssertEqual(s.heatmap[11][4]?.date, day(0))
        XCTAssertNil(s.heatmap[11][5])
        XCTAssertNil(s.heatmap[11][6])
        XCTAssertEqual(s.heatmap[11][0]?.date, day(-4)) // Monday of this week
        XCTAssertEqual(s.heatmap[0][0]?.date, day(-4 - 77))
    }

    func testHeatmapCarriesDayStats() {
        let s = summary([task(-1, .done), task(-1, .todo)])
        XCTAssertEqual(s.heatmap[11][3]?.completed, 1)
        XCTAssertEqual(s.heatmap[11][3]?.total, 2)
    }

    // MARK: - Deferral counts

    func testDeferralCountsFollowSourceChain() {
        let a = UUID(), b = UUID(), c = UUID(), lone = UUID()
        let tasks = [
            task(-3, .deferred, id: a),
            task(-2, .deferred, id: b, source: a),
            task(-1, .todo, id: c, source: b),
            task(0, .todo, id: lone)
        ]
        let counts = TrackingCalculator.deferralCounts(for: tasks)
        XCTAssertEqual(counts[a] ?? 0, 0)
        XCTAssertEqual(counts[b], 1)
        XCTAssertEqual(counts[c], 2)
        XCTAssertEqual(counts[lone] ?? 0, 0)
    }

    func testDeferralCountsSurviveCyclesAndMissingAncestors() {
        let x = UUID(), y = UUID(), orphan = UUID()
        let tasks = [
            task(0, .todo, id: x, source: y),
            task(0, .todo, id: y, source: x),
            task(0, .todo, id: orphan, source: UUID())
        ]
        let counts = TrackingCalculator.deferralCounts(for: tasks)
        XCTAssertNotNil(counts[x])
        XCTAssertEqual(counts[orphan], 1)
    }
}
