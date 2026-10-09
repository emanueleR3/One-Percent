import XCTest
@testable import OnePercent

final class FocusStatsTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!      // Friday 9 Oct 2026, 15:00 UTC

    override func setUp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US")
        calendar = cal
        now = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 15))!
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let start = calendar.startOfDay(for: now)
        let d = calendar.date(byAdding: .day, value: offset, to: start)!
        return calendar.date(byAdding: .hour, value: hour, to: d)!
    }

    private func task(_ title: String, sessions: [(Int, TimeInterval)], id: UUID = UUID(),
                      source: UUID? = nil, habit: UUID? = nil, running: Date? = nil) -> TaskItem {
        TaskItem(
            id: id, title: title, status: .inProgress, scheduledDate: day(0), sourceTaskID: source,
            habitID: habit,
            focusSessions: sessions.map { FocusSession(start: day($0.0), seconds: $0.1) },
            timerStartedAt: running
        )
    }

    private func summary(_ tasks: [TaskItem]) -> FocusSummary {
        FocusCalculator.summary(tasks: tasks, now: now, calendar: calendar)
    }

    func testSessionsAreBucketedByTheDayTheyStarted() {
        let s = summary([task("A", sessions: [(0, 600), (0, 300), (-1, 1_200)])])
        XCTAssertEqual(s.days.count, 7)
        XCTAssertEqual(s.days.last?.seconds, 900)
        XCTAssertEqual(s.days[5].seconds, 1_200)
        XCTAssertEqual(s.todaySeconds, 900)
        XCTAssertEqual(s.weekSeconds, 2_100)
    }

    func testOlderThanAWeekIsIgnored() {
        let s = summary([task("A", sessions: [(-7, 5_000), (-30, 5_000), (-6, 100)])])
        XCTAssertEqual(s.weekSeconds, 100)
        XCTAssertEqual(s.days.first?.seconds, 100)
    }

    func testARunningTimerCountsForItsStartDay() {
        let started = now.addingTimeInterval(-600)
        let s = summary([task("A", sessions: [], running: started)])
        XCTAssertEqual(s.todaySeconds, 600, accuracy: 0.001)
    }

    func testMovedGoalsAreMergedAlongTheirSourceChain() {
        let first = UUID(), second = UUID()
        let s = summary([
            task("Write report", sessions: [(-2, 600)], id: first),
            task("Write report", sessions: [(-1, 900)], id: second, source: first),
            task("Other", sessions: [(0, 300)])
        ])
        XCTAssertEqual(s.topGoals.first?.title, "Write report")
        XCTAssertEqual(s.topGoals.first?.seconds, 1_500)
        XCTAssertEqual(s.topGoals.count, 2)
    }

    func testHabitOccurrencesAreMergedByHabit() {
        let habit = UUID()
        let s = summary([
            task("Gym", sessions: [(-2, 1_800)], habit: habit),
            task("Gym", sessions: [(0, 1_800)], habit: habit)
        ])
        XCTAssertEqual(s.topGoals.count, 1)
        XCTAssertEqual(s.topGoals.first?.seconds, 3_600)
    }

    func testTopGoalsAreSortedAndLimited() {
        let tasks = (1...6).map { task("G\($0)", sessions: [(0, TimeInterval($0) * 100)]) }
        let s = summary(tasks)
        XCTAssertEqual(s.topGoals.count, FocusCalculator.topGoalLimit)
        XCTAssertEqual(s.topGoals.map(\.title), ["G6", "G5", "G4", "G3"])
    }

    func testAveragePerGoalIsWeekTimeOverGoalsWorkedOn() {
        let s = summary([task("A", sessions: [(0, 600)]), task("B", sessions: [(-1, 1_800)]), task("None", sessions: [])])
        XCTAssertEqual(s.averagePerGoal ?? -1, 1_200, accuracy: 0.001)
    }

    func testNothingTrackedYieldsAnEmptySummary() {
        let s = summary([task("A", sessions: [])])
        XCTAssertEqual(s.weekSeconds, 0)
        XCTAssertNil(s.averagePerGoal)
        XCTAssertTrue(s.topGoals.isEmpty)
        XCTAssertEqual(s.sessionCount, 0)
    }

    func testSessionCountCoversTheWeekOnly() {
        let s = summary([task("A", sessions: [(0, 60), (-1, 60), (-20, 60)])])
        XCTAssertEqual(s.sessionCount, 2)
    }

    // MARK: - Formatting

    func testClockFormat() {
        XCTAssertEqual(FocusFormat.clock(0), "0:00")
        XCTAssertEqual(FocusFormat.clock(65), "1:05")
        XCTAssertEqual(FocusFormat.clock(25 * 60), "25:00")
        XCTAssertEqual(FocusFormat.clock(3_725), "1:02:05")
        XCTAssertEqual(FocusFormat.clock(-5), "0:00")
    }

    func testCompactFormat() {
        XCTAssertEqual(FocusFormat.compact(20), "<1m")
        XCTAssertEqual(FocusFormat.compact(60), "1m")
        XCTAssertEqual(FocusFormat.compact(45 * 60 + 30), "45m")
        XCTAssertEqual(FocusFormat.compact(3_600), "1h")
        XCTAssertEqual(FocusFormat.compact(3_600 + 5 * 60), "1h 05m")
        XCTAssertEqual(FocusFormat.compact(0), "0m")
    }
}
