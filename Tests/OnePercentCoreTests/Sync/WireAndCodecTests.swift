import XCTest
@testable import OnePercentCore

final class WireAndCodecTests: XCTestCase {
    func testWireDateRoundTripsToTheMicrosecond() {
        let date = Date(timeIntervalSince1970: 1_800_000_123.456789)
        let text = WireDate.string(date)
        XCTAssertEqual(text, "2027-01-15T08:02:03.456789Z")
        XCTAssertEqual(WireDate.parse(text)!.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.000001)
    }

    func testWireDateParsesWhatPostgresReturns() {
        let reference = WireDate.parse("2026-10-09T11:22:33.123456Z")!
        XCTAssertEqual(WireDate.parse("2026-10-09T11:22:33.123456+00:00"), reference)
        XCTAssertEqual(WireDate.parse("2026-10-09T13:22:33.123456+02:00"), reference)
        XCTAssertEqual(WireDate.parse("2026-10-09T11:22:33.12345+00:00")!.timeIntervalSince(reference), -0.000006, accuracy: 0.0000001)
        XCTAssertEqual(WireDate.parse("2026-10-09T11:22:33+00:00")!.timeIntervalSince1970, reference.timeIntervalSince1970.rounded(.down), accuracy: 0.000001)
        XCTAssertEqual(WireDate.parse("2026-10-09 11:22:33.123456+00"), reference)
        XCTAssertNil(WireDate.parse("not a date"))
        XCTAssertNil(WireDate.parse("2026-10-09"))
    }

    func testNormalizedDatesCompareEqualAfterATripThroughTheServer() {
        let stamp = WireDate.normalized(Date(timeIntervalSince1970: 1_800_000_000.1234567))
        XCTAssertEqual(WireDate.parse(WireDate.string(stamp)), stamp)
        XCTAssertEqual(WireDate.parse(WireDate.string(stamp).replacingOccurrences(of: "Z", with: "+00:00")), stamp)
    }

    func testFingerprintIsStableAndSensitiveToContent() throws {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let a = TaskItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Gym", scheduledDate: day, createdAt: day, updatedAt: day)
        var b = a
        let first = SyncCodec.fingerprint(try SyncCodec.encode(a))
        XCTAssertEqual(first, SyncCodec.fingerprint(try SyncCodec.encode(b)))
        b.title = "Gym!"
        XCTAssertNotEqual(first, SyncCodec.fingerprint(try SyncCodec.encode(b)))
    }

    func testRoundTripKeepsEverythingTheStoreWrites() throws {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        var task = TaskItem(title: "Read", status: .inProgress, scheduledDate: day, createdAt: day, updatedAt: day,
                            tags: ["lavoro"], note: "n", subtasks: [SubTask(title: "s")], isTheOne: true,
                            habitID: UUID(), focusSessions: [FocusSession(start: day, seconds: 90, isPomodoro: true)])
        task.timerStartedAt = day
        let back = try SyncCodec.decodeTask(try SyncCodec.encode(task))
        XCTAssertEqual(back, task)
        let habit = Habit(title: "Gym", schedule: .daily, startDate: day, createdAt: day, skippedDays: [day])
        XCTAssertEqual(try SyncCodec.decodeHabit(try SyncCodec.encode(habit)), habit)
    }

    func testOccurrenceIDsAreDerivedFromHabitAndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let habit = UUID(), other = UUID()
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let tuesday = monday.addingTimeInterval(86_400)

        let id = HabitOccurrenceID.make(habitID: habit, day: monday, calendar: calendar)
        XCTAssertEqual(id, HabitOccurrenceID.make(habitID: habit, day: monday, calendar: calendar), "same input, same id")
        XCTAssertEqual(id, HabitOccurrenceID.make(habitID: habit, day: monday.addingTimeInterval(3600), calendar: calendar), "any moment of the day")
        XCTAssertNotEqual(id, HabitOccurrenceID.make(habitID: habit, day: tuesday, calendar: calendar))
        XCTAssertNotEqual(id, HabitOccurrenceID.make(habitID: other, day: monday, calendar: calendar))
        let hex = id.uuidString
        XCTAssertEqual(hex[hex.index(hex.startIndex, offsetBy: 14)], "5", "version nibble")
        XCTAssertTrue("89AB".contains(hex[hex.index(hex.startIndex, offsetBy: 19)]), "variant bits")
    }
}
