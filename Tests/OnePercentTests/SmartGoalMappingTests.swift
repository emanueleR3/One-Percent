import XCTest
@testable import OnePercent

final class SmartGoalMappingTests: XCTestCase {
    private var calendar: Calendar!
    private var today: Date! // Friday, 9 Oct 2026

    override func setUp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        calendar = cal
        today = cal.date(from: DateComponents(year: 2026, month: 10, day: 9))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func resolve(_ reference: DayReference) -> Date? {
        SmartDateResolver.resolve(reference, today: today, calendar: calendar)
    }

    // MARK: - Dates

    func testNoReferenceMeansNoDate() {
        XCTAssertNil(resolve(DayReference(kind: .none)))
    }

    func testRelativeWords() {
        XCTAssertEqual(resolve(DayReference(kind: .today)), day(0))
        XCTAssertEqual(resolve(DayReference(kind: .tomorrow)), day(1))
        XCTAssertEqual(resolve(DayReference(kind: .dayAfterTomorrow)), day(2))
    }

    func testInSomeDaysUsesTheCountAndStaysInRange() {
        XCTAssertEqual(resolve(DayReference(kind: .inSomeDays, daysAhead: 3)), day(3))
        XCTAssertEqual(resolve(DayReference(kind: .inSomeDays, daysAhead: 40)), day(7))
        XCTAssertEqual(resolve(DayReference(kind: .inSomeDays, daysAhead: -2)), day(0))
    }

    func testWeekdayNameResolvesToTheNextOccurrenceIncludingToday() {
        // Today is Friday (6).
        XCTAssertEqual(resolve(DayReference(kind: .onWeekday, weekday: 6)), day(0))
        XCTAssertEqual(resolve(DayReference(kind: .onWeekday, weekday: 2)), day(3)) // Monday
        XCTAssertEqual(resolve(DayReference(kind: .onWeekday, weekday: 5)), day(6)) // Thursday
    }

    func testWeekdayKindWithoutAWeekdayFallsBackToNoDate() {
        XCTAssertNil(resolve(DayReference(kind: .onWeekday, weekday: nil)))
    }

    /// The regression behind "domani devo..." landing on today: the model also filled in a weekday,
    /// which must be ignored unless the reference says it is a weekday date.
    func testStrayFieldsAreIgnoredForOtherKinds() {
        XCTAssertEqual(resolve(DayReference(kind: .tomorrow, daysAhead: 5, weekday: 6)), day(1))
        XCTAssertEqual(resolve(DayReference(kind: .dayAfterTomorrow, daysAhead: 0, weekday: 6)), day(2))
        XCTAssertNil(resolve(DayReference(kind: .none, daysAhead: 3, weekday: 6)))
    }

    // MARK: - Tags

    func testOnlyKnownTagsSurviveAndAreNormalized() {
        let known: Set<String> = ["lavoro", "brain", "famiglia"]
        let picked = SmartTagFilter.filter(["Lavoro", "#brain", "calcio", "lavoro"], known: known)
        XCTAssertEqual(picked, ["lavoro", "brain"])
    }

    func testAtMostTwoTags() {
        let known: Set<String> = ["a", "b", "c"]
        XCTAssertEqual(SmartTagFilter.filter(["a", "b", "c"], known: known), ["a", "b"])
    }

    func testNothingKnownMeansNoTags() {
        XCTAssertEqual(SmartTagFilter.filter(["lavoro"], known: []), [])
    }
}
