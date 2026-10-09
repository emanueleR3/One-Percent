import XCTest
@testable import OnePercent

@MainActor
private final class FakeScheduler: NotificationScheduling {
    var onMoveToTomorrow: (() -> Void)?
    var onOpenRequested: (() -> Void)?
    var status: NotificationAuthorization = .authorized
    private(set) var scheduled: [ReminderRequest] = []
    private(set) var removedBatches: [[String]] = []
    private(set) var started = false

    func start() { started = true }
    func authorizationStatus() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool { status == .authorized }
    func removePending(ids: [String]) { removedBatches.append(ids); scheduled.removeAll { ids.contains($0.id) } }
    func schedule(_ request: ReminderRequest, calendar: Calendar) async { scheduled.append(request) }
}

@MainActor
final class ReminderCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var prefs: AppPreferences!
    private var scheduler: FakeScheduler!
    private var dateService: DateService!
    private var store: TaskStore!
    private var calendar: Calendar!
    private var coordinator: ReminderCoordinator!
    private var clock: Date!

    override func setUp() async throws {
        let suite = "OnePercentTests.reminders"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        prefs = AppPreferences(defaults: defaults)
        scheduler = FakeScheduler()
        dateService = DateService(calendar: Calendar(identifier: .gregorian))
        calendar = dateService.currentCalendar
        store = TaskStore(persistence: MockTaskPersistence(), dateService: dateService, habitPersistence: InMemoryHabitPersistence())
        clock = at(hour: 8, minute: 0)
        coordinator = ReminderCoordinator(store: store, preferences: prefs, scheduler: scheduler, now: { [unowned self] in self.clock })
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "OnePercentTests.reminders")
    }

    private func at(hour: Int, minute: Int, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: dateService.today)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func enableAll() {
        prefs.notificationsEnabled = true
        prefs.morning = .init(isEnabled: true, minutes: 9 * 60)
        prefs.afternoon = .init(isEnabled: true, minutes: 15 * 60)
        prefs.wrapUp = .init(isEnabled: true, minutes: 21 * 60)
    }

    func testNothingIsScheduledWhileTheMasterSwitchIsOff() async {
        _ = store.addTask(title: "a")
        prefs.wrapUp = .init(isEnabled: true, minutes: 21 * 60)
        await coordinator.refresh()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testNothingIsScheduledWithoutPermission() async {
        enableAll()
        scheduler.status = .denied
        _ = store.addTask(title: "a")
        await coordinator.refresh()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(coordinator.authorization, .denied)
    }

    func testWrapUpTonightMentionsHowManyGoalsAreLeft() async {
        enableAll()
        _ = store.addTask(title: "a"); _ = store.addTask(title: "b")
        let done = store.addTask(title: "c")!
        store.updateTaskStatus(id: done.id, newStatus: .done)

        await coordinator.refresh()

        let wrap = scheduler.scheduled.first { $0.id.contains(".wrapUp.") && calendar.isDate($0.fireDate, inSameDayAs: dateService.today) }
        XCTAssertEqual(wrap?.title, "2 goals left")
        XCTAssertEqual(wrap?.isWrapUp, true)
        XCTAssertEqual(calendar.component(.hour, from: wrap!.fireDate), 21)
    }

    func testSilentContentIsNotScheduled() async {
        enableAll()
        let t = store.addTask(title: "a")!
        store.updateTaskStatus(id: t.id, newStatus: .done)
        await coordinator.refresh()
        XCTAssertFalse(scheduler.scheduled.contains { $0.id.contains(".wrapUp.") })
        XCTAssertFalse(scheduler.scheduled.contains { $0.id.contains(".afternoon.") })
    }

    func testMorningAndAfternoonUseTheirOwnTimes() async {
        enableAll()
        _ = store.addTask(title: "a")
        await coordinator.refresh()
        let hours = Dictionary(uniqueKeysWithValues: scheduler.scheduled
            .filter { calendar.isDate($0.fireDate, inSameDayAs: dateService.today) }
            .map { ($0.id.components(separatedBy: ".")[2], calendar.component(.hour, from: $0.fireDate)) })
        XCTAssertEqual(hours["morning"], 9)
        XCTAssertEqual(hours["afternoon"], 15)
        XCTAssertEqual(hours["wrapUp"], 21)
    }

    func testPastTimesRollToTomorrow() async {
        enableAll()
        clock = at(hour: 22, minute: 0)
        _ = store.addTask(title: "a")                                 // today
        _ = store.addTask(title: "b", for: at(hour: 12, minute: 0, dayOffset: 1)) // tomorrow
        await coordinator.refresh()
        XCTAssertFalse(scheduler.scheduled.contains { calendar.isDate($0.fireDate, inSameDayAs: dateService.today) })
        XCTAssertTrue(scheduler.scheduled.contains { calendar.isDate($0.fireDate, inSameDayAs: at(hour: 0, minute: 0, dayOffset: 1)) })
    }

    func testRefreshReplacesWhatWasPendingBefore() async {
        enableAll()
        _ = store.addTask(title: "a")
        await coordinator.refresh()
        let first = scheduler.scheduled.count
        await coordinator.refresh()
        XCTAssertEqual(scheduler.scheduled.count, first, "second refresh must not duplicate requests")
        XCTAssertEqual(scheduler.removedBatches.count, 2)
    }

    func testDisablingEverythingClearsPending() async {
        enableAll()
        _ = store.addTask(title: "a")
        await coordinator.refresh()
        XCTAssertFalse(scheduler.scheduled.isEmpty)
        prefs.notificationsEnabled = false
        await coordinator.refresh()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testMoveToTomorrowActionDefersTheOpenGoals() {
        coordinator.start()
        let task = store.addTask(title: "a")!
        scheduler.onMoveToTomorrow?()
        XCTAssertEqual(store.allTasks.first { $0.id == task.id }?.status, .deferred)
        XCTAssertTrue(scheduler.started)
    }
}
