import XCTest
@testable import OnePercent
@testable import OnePercentCore
import OnePercentTestSupport

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

@MainActor
final class AppPreferencesNotchTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "OnePercentTests.prefs.notch")!
        defaults.removePersistentDomain(forName: "OnePercentTests.prefs.notch")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "OnePercentTests.prefs.notch")
    }

    func testNotchDefaults() {
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertTrue(prefs.indicatorEnabled)
        XCTAssertEqual(prefs.virtualNotchWidth, 0)
        XCTAssertEqual(prefs.virtualNotchHeight, 0)
        XCTAssertTrue(prefs.indicatorShowsTimer)
        XCTAssertEqual(prefs.screenSelection, .automatic)
        XCTAssertEqual(prefs.panelAnchor, .center)
        XCTAssertEqual(prefs.openDelay, 0, accuracy: 0.0001)
        XCTAssertEqual(prefs.closeDelay, 0.16, accuracy: 0.0001)
    }

    func testFocusDefaults() {
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertFalse(prefs.pomodoroEnabled)
        XCTAssertEqual(prefs.pomodoroConfig, PomodoroConfig())
        XCTAssertTrue(prefs.focusSound)
        XCTAssertFalse(prefs.focusNotifications)
    }

    func testNotchAndFocusSettingsPersist() {
        let first = AppPreferences(defaults: defaults)
        first.indicatorEnabled = false
        first.virtualNotchWidth = 280
        first.virtualNotchHeight = 36
        first.screenSelection = .display("UUID-1")
        first.panelAnchor = .trailing
        first.openDelay = 0.4
        first.closeDelay = 0.8
        first.pomodoroEnabled = true
        first.focusMinutes = 50
        first.shortBreakMinutes = 10
        first.longBreakMinutes = 20
        first.pomodoroRounds = 3

        let second = AppPreferences(defaults: defaults)
        XCTAssertFalse(second.indicatorEnabled)
        XCTAssertEqual(second.virtualNotchWidth, 280)
        XCTAssertEqual(second.virtualNotchHeight, 36)
        XCTAssertEqual(second.screenSelection, .display("UUID-1"))
        XCTAssertEqual(second.panelAnchor, .trailing)
        XCTAssertEqual(second.openDelay, 0.4, accuracy: 0.0001)
        XCTAssertEqual(second.closeDelay, 0.8, accuracy: 0.0001)
        XCTAssertEqual(second.pomodoroConfig, PomodoroConfig(focus: 50 * 60, shortBreak: 10 * 60, longBreak: 20 * 60, roundsBeforeLongBreak: 3))
    }

    func testUnknownStoredValuesFallBackToDefaults() {
        defaults.set("diagonal", forKey: "panelAnchor")
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.panelAnchor, .center)
    }

    func testNotchSizesStayAutomaticOrUsable() {
        defaults.set(-5.0, forKey: "virtualNotchWidth")
        defaults.set(99999.0, forKey: "virtualNotchHeight")
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.virtualNotchWidth, 0)
        XCTAssertEqual(prefs.virtualNotchHeight, 600)
        XCTAssertEqual(AppPreferences.clampNotchSize(.nan), 0)
        XCTAssertEqual(AppPreferences.clampNotchSize(5), 16)
    }

    func testDelaysAreClamped() {
        let prefs = AppPreferences(defaults: defaults)
        prefs.openDelay = -3
        XCTAssertEqual(prefs.openDelay, 0, accuracy: 0.0001)
        prefs.closeDelay = 99
        XCTAssertEqual(prefs.closeDelay, AppPreferences.maxDelay, accuracy: 0.0001)
    }
}

@MainActor
final class AppPreferencesLanguageTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "OnePercentTests.prefs.language")!
        defaults.removePersistentDomain(forName: "OnePercentTests.prefs.language")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "OnePercentTests.prefs.language")
    }

    func testDefaultsToFollowingTheSystem() {
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.language, .system)
    }

    func testLanguageChoicePersists() {
        let first = AppPreferences(defaults: defaults)
        first.language = .italian
        XCTAssertEqual(AppPreferences(defaults: defaults).language, .italian)
    }

    func testResolvedLanguageFollowsTheChoice() {
        let prefs = AppPreferences(defaults: defaults)
        prefs.language = .english
        XCTAssertEqual(prefs.resolvedLanguage(preferred: ["it-IT"]), .english)
        prefs.language = .italian
        XCTAssertEqual(prefs.resolvedLanguage(preferred: ["en-US"]), .italian)
        prefs.language = .system
        XCTAssertEqual(prefs.resolvedLanguage(preferred: ["it-IT"]), .italian)
    }

    func testAnUnknownStoredValueMeansSystem() {
        defaults.set("klingon", forKey: "language")
        XCTAssertEqual(AppPreferences(defaults: defaults).language, .system)
    }
}
