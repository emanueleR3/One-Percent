import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

@MainActor
final class DateServiceTests: XCTestCase {
    private var calendar: Calendar!
    private var dateService: DateService!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        dateService = DateService(calendar: calendar)
    }

    func testNormalizeReturnsStartOfDay() {
        let now = Date()
        let normalized = dateService.normalize(now)

        let comps = calendar.dateComponents([.hour, .minute, .second], from: normalized)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)
    }

    func testNextDayAndPreviousDay() {
        let today = dateService.today
        let tomorrow = dateService.nextDay(after: today)
        let yesterday = dateService.previousDay(before: today)

        let diffTomorrow = calendar.dateComponents([.day], from: today, to: tomorrow)
        let diffYesterday = calendar.dateComponents([.day], from: yesterday, to: today)

        XCTAssertEqual(diffTomorrow.day, 1)
        XCTAssertEqual(diffYesterday.day, 1)
    }

    func testIsTodayAndIsTomorrow() {
        let today = dateService.today
        let tomorrow = dateService.nextDay(after: today)
        let yesterday = dateService.previousDay(before: today)

        XCTAssertTrue(dateService.isToday(today))
        XCTAssertFalse(dateService.isToday(tomorrow))
        XCTAssertFalse(dateService.isToday(yesterday))

        XCTAssertTrue(dateService.isTomorrow(tomorrow))
        XCTAssertFalse(dateService.isTomorrow(today))
        XCTAssertFalse(dateService.isTomorrow(yesterday))
    }

    func testFormatDayTitleForTodayTomorrowAndOther() {
        let today = dateService.today
        let tomorrow = dateService.nextDay(after: today)
        let futureDay = calendar.date(byAdding: .day, value: 5, to: today)!

        let todayTitle = dateService.formatDayTitle(for: today)
        let tomorrowTitle = dateService.formatDayTitle(for: tomorrow)
        let futureTitle = dateService.formatDayTitle(for: futureDay)

        XCTAssertTrue(todayTitle.hasPrefix("Today,"), "Expected prefix 'Today,', got: \(todayTitle)")
        XCTAssertTrue(tomorrowTitle.hasPrefix("Tomorrow,"), "Expected prefix 'Tomorrow,', got: \(tomorrowTitle)")
        XCTAssertFalse(futureTitle.hasPrefix("Today,"))
        XCTAssertFalse(futureTitle.hasPrefix("Tomorrow,"))
    }

    func testFormatProgressHeaderForTodayTomorrowAndOther() {
        let today = dateService.today
        let tomorrow = dateService.nextDay(after: today)
        let futureDay = calendar.date(byAdding: .day, value: 5, to: today)!

        XCTAssertEqual(dateService.formatProgressHeader(for: today), "TODAY'S GOALS")
        XCTAssertEqual(dateService.formatProgressHeader(for: tomorrow), "TOMORROW'S GOALS")
        XCTAssertTrue(dateService.formatProgressHeader(for: futureDay).hasSuffix("'S GOALS"))
    }

    func testDayChangeCallbackTriggered() {
        var dayChangeFired = false
        dateService.onDayChanged = { _ in
            dayChangeFired = true
        }

        // Initially refreshToday does not fire if today didn't change
        dateService.refreshToday()
        XCTAssertFalse(dayChangeFired)
    }

    func testDaylightSavingTimeTransitionsInEuropeRome() {
        var romeCalendar = Calendar(identifier: .gregorian)
        guard let romeTimeZone = TimeZone(identifier: "Europe/Rome") else {
            return
        }
        romeCalendar.timeZone = romeTimeZone
        let service = DateService(calendar: romeCalendar)

        // Autumn DST transition: 25-hour day (Sunday, October 25, 2026)
        var autumnComps = DateComponents()
        autumnComps.year = 2026
        autumnComps.month = 10
        autumnComps.day = 25
        autumnComps.hour = 12
        let autumnDstDay = romeCalendar.date(from: autumnComps)!

        let dayAfterAutumn = service.nextDay(after: autumnDstDay)
        let dayBeforeAutumn = service.previousDay(before: autumnDstDay)

        let nextDayComps = romeCalendar.dateComponents([.year, .month, .day, .hour], from: dayAfterAutumn)
        XCTAssertEqual(nextDayComps.day, 26)
        XCTAssertEqual(nextDayComps.month, 10)
        XCTAssertEqual(nextDayComps.hour, 0)

        let prevDayComps = romeCalendar.dateComponents([.year, .month, .day, .hour], from: dayBeforeAutumn)
        XCTAssertEqual(prevDayComps.day, 24)
        XCTAssertEqual(prevDayComps.month, 10)
        XCTAssertEqual(prevDayComps.hour, 0)

        // Spring DST transition: 23-hour day (Sunday, March 29, 2026)
        var springComps = DateComponents()
        springComps.year = 2026
        springComps.month = 3
        springComps.day = 29
        springComps.hour = 12
        let springDstDay = romeCalendar.date(from: springComps)!

        let dayAfterSpring = service.nextDay(after: springDstDay)
        let springNextComps = romeCalendar.dateComponents([.year, .month, .day, .hour], from: dayAfterSpring)
        XCTAssertEqual(springNextComps.day, 30)
        XCTAssertEqual(springNextComps.month, 3)
        XCTAssertEqual(springNextComps.hour, 0)
    }

    func testSevenDayBoundaryLimits() {
        let today = dateService.today
        XCTAssertEqual(dateService.daysFromToday(to: today), 0)
        XCTAssertTrue(dateService.canNavigatePrevious(from: today))
        XCTAssertTrue(dateService.canNavigateNext(from: today))

        // 7 days past: cannot go further past
        let past7 = calendar.date(byAdding: .day, value: -7, to: today)!
        XCTAssertEqual(dateService.daysFromToday(to: past7), -7)
        XCTAssertFalse(dateService.canNavigatePrevious(from: past7))
        XCTAssertTrue(dateService.canNavigateNext(from: past7))

        // 6 days past: can go previous
        let past6 = calendar.date(byAdding: .day, value: -6, to: today)!
        XCTAssertTrue(dateService.canNavigatePrevious(from: past6))

        // 7 days future: cannot go further future
        let future7 = calendar.date(byAdding: .day, value: 7, to: today)!
        XCTAssertEqual(dateService.daysFromToday(to: future7), 7)
        XCTAssertFalse(dateService.canNavigateNext(from: future7))
        XCTAssertTrue(dateService.canNavigatePrevious(from: future7))

        // 6 days future: can go next
        let future6 = calendar.date(byAdding: .day, value: 6, to: today)!
        XCTAssertTrue(dateService.canNavigateNext(from: future6))
    }
}

@MainActor
final class DateServiceDayKeyTests: XCTestCase {
    func testDayKeyIsZeroPaddedAndLocal() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let service = DateService(calendar: cal)
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23, minute: 59))!
        XCTAssertEqual(service.dayKey(for: date), "2026-03-05")
    }
}
