import XCTest
@testable import OnePercentCore

final class SigningExpiryTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        calendar = cal
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Reading the profile

    /// A real profile is a binary CMS envelope with the XML list somewhere in the middle.
    private func profile(expiring expires: Date?) throws -> Data {
        var list: [String: Any] = ["Name": "iOS Team Provisioning Profile", "TeamName": "Personal Team"]
        if let expires { list["ExpirationDate"] = expires }
        let xml = try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
        var data = Data([0x30, 0x82, 0x0A, 0xFF, 0x06, 0x09, 0x2A, 0x86, 0x48])
        data.append(xml)
        data.append(Data([0x00, 0x31, 0x82, 0x01, 0x7F, 0xA0, 0x03]))
        return data
    }

    func testReadsTheExpiryOutOfAnEnvelope() throws {
        let expires = date(16, 21, 24)
        XCTAssertEqual(ProvisioningProfile.expirationDate(in: try profile(expiring: expires)), expires)
    }

    func testAProfileWithoutAnExpiryGivesNil() throws {
        XCTAssertNil(ProvisioningProfile.expirationDate(in: try profile(expiring: nil)))
    }

    func testGarbageGivesNil() {
        XCTAssertNil(ProvisioningProfile.expirationDate(in: Data([1, 2, 3, 4])))
        XCTAssertNil(ProvisioningProfile.expirationDate(in: Data("<?xml not a plist".utf8)))
        XCTAssertNil(ProvisioningProfile.expirationDate(in: Data()))
    }

    func testABundleWithoutAProfileGivesNil() {
        XCTAssertNil(ProvisioningProfile.expirationDate(bundle: Bundle(for: SigningExpiryTests.self)))
    }

    // MARK: - Days left

    func testDaysLeftCountsCalendarDays() {
        let expires = date(16, 23, 24)
        XCTAssertEqual(SigningExpiryPlanner.daysLeft(expires: expires, now: date(10, 8), calendar: calendar), 6)
        XCTAssertEqual(SigningExpiryPlanner.daysLeft(expires: expires, now: date(15, 23, 59), calendar: calendar), 1)
        XCTAssertEqual(SigningExpiryPlanner.daysLeft(expires: expires, now: date(16, 0, 1), calendar: calendar), 0)
        XCTAssertEqual(SigningExpiryPlanner.daysLeft(expires: expires, now: date(17, 9), calendar: calendar), -1)
    }

    func testHasExpired() {
        XCTAssertFalse(SigningExpiryPlanner.hasExpired(expires: date(16, 21), now: date(16, 20)))
        XCTAssertTrue(SigningExpiryPlanner.hasExpired(expires: date(16, 21), now: date(16, 21)))
    }

    // MARK: - Warning

    func testTheWarningIsTheEveningBeforeTheExpiry() {
        let fire = SigningExpiryPlanner.warningDate(expires: date(16, 21, 24), now: date(10, 8), calendar: calendar)
        XCTAssertEqual(fire, date(15, 18))
    }

    func testAnExpiryEarlyInTheMorningStillWarnsTheEveningBefore() {
        let fire = SigningExpiryPlanner.warningDate(expires: date(16, 3, 10), now: date(10, 8), calendar: calendar)
        XCTAssertEqual(fire, date(15, 18))
    }

    func testNoWarningOnceThatEveningHasPassed() {
        XCTAssertNil(SigningExpiryPlanner.warningDate(expires: date(16, 21), now: date(15, 18, 30), calendar: calendar))
        XCTAssertNil(SigningExpiryPlanner.warningDate(expires: date(16, 21), now: date(16, 9), calendar: calendar))
    }

    func testNoWarningForAnExpiryThatHasPassed() {
        XCTAssertNil(SigningExpiryPlanner.warningDate(expires: date(10, 8), now: date(10, 9), calendar: calendar))
    }

    func testNoWarningAMomentBeforeItWouldFire() {
        XCTAssertNil(SigningExpiryPlanner.warningDate(expires: date(16, 21), now: date(15, 17, 59), calendar: calendar, leadTime: 120))
    }
}
