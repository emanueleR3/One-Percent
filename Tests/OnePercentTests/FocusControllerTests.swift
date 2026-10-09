import XCTest
@testable import OnePercent

@MainActor
final class FocusControllerTests: XCTestCase {
    private var store: TaskStore!
    private var prefs: AppPreferences!
    private var scheduler: FakeScheduler!
    private var controller: FocusController!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var sounds: [String] = []

    override func setUp() async throws {
        let suite = "OnePercentTests.focus"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        prefs = AppPreferences(defaults: defaults)
        store = TaskStore(
            persistence: MockTaskPersistence(),
            dateService: DateService(calendar: Calendar(identifier: .gregorian)),
            habitPersistence: InMemoryHabitPersistence()
        )
        scheduler = FakeScheduler()
        sounds = []
        controller = FocusController(
            store: store,
            preferences: prefs,
            scheduler: scheduler,
            now: { [unowned self] in self.clock },
            playSound: { [unowned self] in self.sounds.append($0) },
            autoTick: false
        )
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: "OnePercentTests.focus")?.removePersistentDomain(forName: "OnePercentTests.focus")
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }
    private func add(_ title: String) -> TaskItem { store.addTask(title: title)! }
    private func task(_ id: UUID) -> TaskItem { store.allTasks.first { $0.id == id }! }

    // MARK: - Free timer

    func testStartingWithoutPomodoroJustRunsTheStopwatch() {
        let a = add("A")
        controller.start(taskID: a.id)
        XCTAssertEqual(store.runningTimerTaskID, a.id)
        XCTAssertNil(controller.pomodoro)
        XCTAssertTrue(controller.isActive)
    }

    func testToggleStartsPausesAndResumes() {
        let a = add("A")
        controller.toggle(taskID: a.id)
        XCTAssertEqual(store.runningTimerTaskID, a.id)
        advance(120)
        controller.toggle(taskID: a.id)
        XCTAssertNil(store.runningTimerTaskID)
        XCTAssertEqual(task(a.id).focusSessions.map(\.seconds), [120])
        controller.toggle(taskID: a.id)
        XCTAssertEqual(store.runningTimerTaskID, a.id)
    }

    func testStopBanksTheTime() {
        let a = add("A")
        controller.start(taskID: a.id)
        advance(300)
        controller.stop()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(task(a.id).timeSpent(at: clock), 300, accuracy: 0.001)
    }

    func testTheStopwatchStopsWhenTheGoalIsCompleted() {
        let a = add("A")
        controller.start(taskID: a.id)
        store.updateTaskStatus(id: a.id, newStatus: .done)
        controller.tick()
        XCTAssertFalse(controller.isActive)
    }

    // MARK: - Pomodoro

    private func enablePomodoro(rounds: Int = 4) {
        prefs.pomodoroEnabled = true
        prefs.focusMinutes = 25
        prefs.shortBreakMinutes = 5
        prefs.longBreakMinutes = 15
        prefs.pomodoroRounds = rounds
    }

    func testStartingWithPomodoroBeginsAFocusBlock() {
        enablePomodoro()
        let a = add("A")
        controller.start(taskID: a.id)
        XCTAssertEqual(controller.pomodoro?.phase, .focus)
        XCTAssertEqual(controller.pomodoro?.taskID, a.id)
        XCTAssertEqual(store.runningTimerTaskID, a.id)
    }

    func testAFinishedFocusBlockIsBankedExactlyAndStartsABreak() async {
        enablePomodoro()
        prefs.focusNotifications = true
        let a = add("A")
        controller.start(taskID: a.id)

        advance(25 * 60 + 7)   // the tick arrives a few seconds late
        controller.tick()
        await controller.settle()

        XCTAssertEqual(controller.pomodoro?.phase, .shortBreak)
        XCTAssertNil(store.runningTimerTaskID, "the clock stops at the end of the block, not during the break")
        XCTAssertEqual(task(a.id).focusSessions.first?.seconds ?? 0, 25 * 60, accuracy: 0.001, "late ticks do not inflate the session")
        XCTAssertEqual(task(a.id).focusSessions.first?.isPomodoro, true)
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(scheduler.delivered.count, 1)
        XCTAssertTrue(scheduler.delivered[0].title.lowercased().contains("focus"))
    }

    func testNotificationsAreSkippedUnlessEnabledAndAllowed() async {
        enablePomodoro()
        let a = add("A")
        controller.start(taskID: a.id)
        advance(25 * 60)
        controller.tick()
        await controller.settle()
        XCTAssertTrue(scheduler.delivered.isEmpty, "off by default")

        prefs.focusNotifications = true
        scheduler.status = .denied
        advance(5 * 60)
        controller.tick()
        await controller.settle()
        XCTAssertTrue(scheduler.delivered.isEmpty, "no permission, no notification")
    }

    func testSoundCanBeSwitchedOff() {
        enablePomodoro()
        prefs.focusSound = false
        let a = add("A")
        controller.start(taskID: a.id)
        advance(25 * 60)
        controller.tick()
        XCTAssertTrue(sounds.isEmpty)
    }

    func testTheBreakEndsAndTheCycleWaitsForTheUser() async {
        enablePomodoro()
        let a = add("A")
        controller.start(taskID: a.id)
        advance(25 * 60)
        controller.tick()
        advance(5 * 60)
        controller.tick()
        await controller.settle()

        XCTAssertNil(controller.pomodoro)
        XCTAssertNil(store.runningTimerTaskID)
        XCTAssertEqual(sounds.count, 2)
    }

    func testTheNextBlockContinuesTheCycleCount() {
        enablePomodoro(rounds: 2)
        let a = add("A")
        controller.start(taskID: a.id)
        advance(25 * 60); controller.tick()          // block 1 -> short break
        advance(5 * 60); controller.tick()           // break over
        controller.start(taskID: a.id)               // block 2
        XCTAssertEqual(controller.pomodoro?.blockNumber(in: prefs.pomodoroConfig), 2)
        advance(25 * 60); controller.tick()
        XCTAssertEqual(controller.pomodoro?.phase, .longBreak, "every second block with rounds = 2")
    }

    func testPausingFreezesTheBlockAndResumingContinuesIt() {
        enablePomodoro()
        let a = add("A")
        controller.start(taskID: a.id)
        advance(600)
        controller.pause()
        XCTAssertTrue(controller.pomodoro?.isPaused ?? false)
        XCTAssertNil(store.runningTimerTaskID)
        XCTAssertEqual(task(a.id).timeSpent(at: clock), 600, accuracy: 0.001)

        advance(3_600)        // an hour away
        controller.tick()
        XCTAssertEqual(controller.pomodoro?.phase, .focus, "a paused block does not run out")

        controller.resume()
        XCTAssertEqual(store.runningTimerTaskID, a.id)
        XCTAssertEqual(controller.pomodoro?.remaining(at: clock) ?? 0, 900, accuracy: 0.001)
    }

    func testSkippingABreakReturnsToIdle() {
        enablePomodoro()
        let a = add("A")
        controller.start(taskID: a.id)
        advance(25 * 60); controller.tick()
        controller.skipBreak()
        XCTAssertNil(controller.pomodoro)
    }

    func testStoppingDuringAFocusBlockEndsTheCycleBlock() {
        enablePomodoro()
        let a = add("A")
        controller.start(taskID: a.id)
        advance(200)
        controller.stop()
        XCTAssertNil(controller.pomodoro)
        XCTAssertEqual(task(a.id).timeSpent(at: clock), 200, accuracy: 0.001)
    }

    func testCompletingTheGoalEndsItsFocusBlock() {
        enablePomodoro()
        let a = add("A")
        controller.start(taskID: a.id)
        store.updateTaskStatus(id: a.id, newStatus: .done)
        controller.tick()
        XCTAssertNil(controller.pomodoro)
    }

    // MARK: - Sleep

    func testGoingToSleepPausesWhateverIsRunning() {
        let a = add("A")
        controller.start(taskID: a.id)
        advance(90)
        controller.systemWillSleep()
        XCTAssertNil(store.runningTimerTaskID)
        XCTAssertEqual(task(a.id).timeSpent(at: clock), 90, accuracy: 0.001)
    }

    // MARK: - Heartbeat

    func testTheCheckpointAdvancesWhileRunning() {
        let a = add("A")
        controller.start(taskID: a.id)
        for _ in 0..<FocusController.heartbeatEvery {
            advance(1)
            controller.tick()
        }
        XCTAssertEqual(task(a.id).updatedAt, clock)
    }
}
