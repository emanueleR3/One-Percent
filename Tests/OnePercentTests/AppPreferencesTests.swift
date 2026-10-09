import XCTest
@testable import OnePercent

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "OnePercentTests.prefs"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertTrue(prefs.wrapUp.isEnabled)
        XCTAssertEqual(prefs.wrapUp.minutes, 21 * 60)
        XCTAssertFalse(prefs.morning.isEnabled)
        XCTAssertEqual(prefs.morning.minutes, 9 * 60)
        XCTAssertFalse(prefs.afternoon.isEnabled)
        XCTAssertEqual(prefs.afternoon.minutes, 15 * 60)
        XCTAssertTrue(prefs.openOnHover)
        XCTAssertTrue(prefs.smartAddEnabled)
    }

    func testChangesPersistAcrossInstances() {
        let first = AppPreferences(defaults: defaults)
        first.morning = .init(isEnabled: true, minutes: 8 * 60 + 15)
        first.openOnHover = false
        first.setTagColor("work", index: 3)

        let second = AppPreferences(defaults: defaults)
        XCTAssertTrue(second.morning.isEnabled)
        XCTAssertEqual(second.morning.minutes, 8 * 60 + 15)
        XCTAssertFalse(second.openOnHover)
        XCTAssertEqual(second.tagColorIndex(for: "work"), 3)
    }

    func testWrapUpDismissalIsPerDay() {
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertFalse(prefs.isWrapUpDismissed(dayKey: "2026-10-09"))
        prefs.dismissWrapUp(dayKey: "2026-10-09")
        XCTAssertTrue(prefs.isWrapUpDismissed(dayKey: "2026-10-09"))
        XCTAssertFalse(prefs.isWrapUpDismissed(dayKey: "2026-10-10"))
        XCTAssertTrue(AppPreferences(defaults: defaults).isWrapUpDismissed(dayKey: "2026-10-09"))
    }

    func testCyclingTagColorWrapsAroundThePalette() {
        let prefs = AppPreferences(defaults: defaults)
        let start = prefs.tagColorIndex(for: "work")
        prefs.cycleTagColor("work")
        XCTAssertEqual(prefs.tagColorIndex(for: "work"), (start + 1) % TagPalette.count)
        for _ in 0..<TagPalette.count { prefs.cycleTagColor("work") }
        XCTAssertEqual(prefs.tagColorIndex(for: "work"), (start + 1) % TagPalette.count)
    }

    func testDefaultTagColorIsStablePerName() {
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.tagColorIndex(for: "family"), prefs.tagColorIndex(for: "family"))
        XCTAssertEqual(AppPreferences(defaults: defaults).tagColorIndex(for: "family"), prefs.tagColorIndex(for: "family"))
    }

    func testCorruptStoredValuesFallBackToDefaults() {
        defaults.set(Data([0x00, 0x01]), forKey: "wrapUp")
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.wrapUp.minutes, 21 * 60)
    }
}

@MainActor
final class AppPreferencesNotificationTests: XCTestCase {
    func testNotificationsAreOffUntilTheUserEnablesThem() {
        let defaults = UserDefaults(suiteName: "OnePercentTests.prefs.notifications")!
        defaults.removePersistentDomain(forName: "OnePercentTests.prefs.notifications")
        let prefs = AppPreferences(defaults: defaults)

        XCTAssertFalse(prefs.notificationsEnabled)
        XCTAssertFalse(prefs.anyReminderEnabled, "wrap-up is on by default but must not notify without the master switch")

        prefs.notificationsEnabled = true
        XCTAssertTrue(prefs.anyReminderEnabled)

        prefs.wrapUp.isEnabled = false
        XCTAssertFalse(prefs.anyReminderEnabled)
        prefs.morning.isEnabled = true
        XCTAssertTrue(prefs.anyReminderEnabled)
        defaults.removePersistentDomain(forName: "OnePercentTests.prefs.notifications")
    }
}
