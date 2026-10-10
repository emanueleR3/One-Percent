import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

/// What a running timer does when an app starts again, and who is allowed to stop it.
///
/// A timer is a start time, not a ticking counter, so it keeps counting while a phone app is
/// suspended or closed. These tests pin the two reports that started this: closing the phone app
/// stopped its own timer, and reopening it stopped a timer that had been started on the Mac.
@MainActor
final class TimerRelaunchTests: XCTestCase {
    private var dateService: DateService!

    override func setUp() async throws {
        dateService = DateService(calendar: Calendar(identifier: .gregorian))
    }

    private func store(
        _ persistence: MockTaskPersistence,
        policy: TimerRelaunchPolicy,
        origin: TimerOriginStoring?
    ) -> TaskStore {
        TaskStore(
            persistence: persistence, dateService: dateService, habitPersistence: InMemoryHabitPersistence(),
            timerRelaunch: policy, timerOrigin: origin
        )
    }

    private func ago(_ seconds: TimeInterval) -> Date { Date().addingTimeInterval(-seconds) }

    // MARK: - The phone's own timer

    func testAPhoneTimerKeepsRunningAcrossARelaunch() {
        let disk = MockTaskPersistence()
        let origin = InMemoryTimerOrigin()
        let first = store(disk, policy: .keepRunning, origin: origin)
        let goal = first.addTask(title: "Study")!
        first.startTimer(id: goal.id, at: ago(3_600))   // an hour with the app closed

        let reopened = store(disk, policy: .keepRunning, origin: origin)

        XCTAssertEqual(reopened.runningTimerTaskID, goal.id)
        let revived = reopened.allTasks.first { $0.id == goal.id }!
        XCTAssertEqual(revived.timerStartedAt!.timeIntervalSince(ago(3_600)), 0, accuracy: 1)
        XCTAssertTrue(revived.focusSessions.isEmpty)
        XCTAssertEqual(revived.timeSpent(at: Date()), 3_600, accuracy: 2)
    }

    func testAMacTimerIsStillCreditedOnlyUntilTheLastCheckpoint() {
        let disk = MockTaskPersistence()
        let origin = InMemoryTimerOrigin()
        let first = store(disk, policy: .creditToLastCheckpoint, origin: origin)
        let goal = first.addTask(title: "Study")!
        first.startTimer(id: goal.id, at: ago(7_200))
        first.timerHeartbeat(at: ago(7_200 - 900))   // the app was last seen 15 minutes in

        let reopened = store(disk, policy: .creditToLastCheckpoint, origin: origin)

        XCTAssertNil(reopened.runningTimerTaskID)
        XCTAssertEqual(reopened.allTasks.first!.focusSessions.map(\.seconds).first ?? 0, 900, accuracy: 1)
        XCTAssertEqual(reopened.allTasks.first!.focusSessions.count, 1)
    }

    // MARK: - Somebody else's timer

    func testATimerStartedOnAnotherDeviceIsLeftAloneOnRelaunch() {
        // The Mac started it; it reached this device through sync, so there is no local marker.
        let goal = TaskItem(
            title: "Study", status: .inProgress, scheduledDate: dateService.today,
            createdAt: ago(4_000), updatedAt: ago(1_800), timerStartedAt: ago(1_800)
        )
        for policy in [TimerRelaunchPolicy.keepRunning, .creditToLastCheckpoint] {
            let disk = MockTaskPersistence()
            disk.storedTasks = [goal]

            let reopened = store(disk, policy: policy, origin: InMemoryTimerOrigin())

            XCTAssertEqual(reopened.runningTimerTaskID, goal.id, "\(policy) must not stop another device's timer")
            XCTAssertTrue(reopened.allTasks.first!.focusSessions.isEmpty)
        }
    }

    func testOnlyTheDeviceThatStartedATimerWritesItsHeartbeat() {
        let goal = TaskItem(
            title: "Study", status: .inProgress, scheduledDate: dateService.today,
            createdAt: ago(4_000), updatedAt: ago(1_800), timerStartedAt: ago(1_800)
        )
        let disk = MockTaskPersistence()
        disk.storedTasks = [goal]
        let reopened = store(disk, policy: .keepRunning, origin: InMemoryTimerOrigin())

        reopened.timerHeartbeat(at: Date())

        XCTAssertEqual(reopened.allTasks.first!.updatedAt.timeIntervalSince(ago(1_800)), 0, accuracy: 1,
                       "a timer that is not ours is not ours to stamp")
    }

    // MARK: - Forgotten timers

    func testATimerOlderThanTwelveHoursIsTreatedAsForgotten() {
        let disk = MockTaskPersistence()
        let origin = InMemoryTimerOrigin()
        let first = store(disk, policy: .keepRunning, origin: origin)
        let goal = first.addTask(title: "Study")!
        first.startTimer(id: goal.id, at: ago(13 * 3_600))
        first.timerHeartbeat(at: ago(13 * 3_600 - 600))

        let reopened = store(disk, policy: .keepRunning, origin: origin)

        XCTAssertNil(reopened.runningTimerTaskID)
        XCTAssertEqual(reopened.allTasks.first!.focusSessions.map(\.seconds).first ?? 0, 600, accuracy: 1)
        XCTAssertEqual(reopened.allTasks.first!.focusSessions.count, 1)
    }

    func testAnOpenAppStopsAForgottenTimerToo() {
        let first = store(MockTaskPersistence(), policy: .keepRunning, origin: InMemoryTimerOrigin())
        let goal = first.addTask(title: "Study")!
        first.startTimer(id: goal.id, at: ago(11 * 3_600))
        first.expireForgottenTimers(at: Date())
        XCTAssertEqual(first.runningTimerTaskID, goal.id, "11 hours is long, but not forgotten")

        first.expireForgottenTimers(at: Date().addingTimeInterval(2 * 3_600))
        XCTAssertNil(first.runningTimerTaskID)
    }

    // MARK: - Across devices

    func testClosingThePhoneAppDoesNotStopTheTimerStartedOnTheMac() async {
        let server = FakeSyncServer()
        let macDisk = MockTaskPersistence(), phoneDisk = MockTaskPersistence()
        let macOrigin = InMemoryTimerOrigin(), phoneOrigin = InMemoryTimerOrigin()
        let mac = store(macDisk, policy: .creditToLastCheckpoint, origin: macOrigin)
        var phone = store(phoneDisk, policy: .keepRunning, origin: phoneOrigin)
        let macSync = SyncEngine(store: mac, transport: server, persistence: InMemorySyncStatePersistence(SyncState(deviceID: "mac")))
        let phoneState = InMemorySyncStatePersistence(SyncState(deviceID: "phone"))
        var phoneSync = SyncEngine(store: phone, transport: server, persistence: phoneState)

        let goal = mac.addTask(title: "Study")!
        await macSync.syncNow(); await phoneSync.syncNow()
        mac.startTimer(id: goal.id, at: ago(600))
        mac.timerHeartbeat(at: ago(60))             // the Mac keeps checkpointing while it runs
        await macSync.syncNow(); await phoneSync.syncNow()
        XCTAssertEqual(phone.runningTimerTaskID, goal.id, "the phone sees the Mac's timer")

        // The phone app is closed and opened again: a cold start, reading what it saved.
        phone = store(phoneDisk, policy: .keepRunning, origin: phoneOrigin)
        phoneSync = SyncEngine(store: phone, transport: server, persistence: phoneState)
        await phoneSync.syncNow(); await macSync.syncNow(); await phoneSync.syncNow()

        XCTAssertEqual(mac.runningTimerTaskID, goal.id, "the Mac's timer must still be running")
        XCTAssertEqual(phone.runningTimerTaskID, goal.id)
        XCTAssertTrue(mac.allTasks.first!.focusSessions.isEmpty)
    }

    func testClosingThePhoneAppDoesNotStopItsOwnTimerOnTheMacEither() async {
        let server = FakeSyncServer()
        let macDisk = MockTaskPersistence(), phoneDisk = MockTaskPersistence()
        let macOrigin = InMemoryTimerOrigin(), phoneOrigin = InMemoryTimerOrigin()
        let mac = store(macDisk, policy: .creditToLastCheckpoint, origin: macOrigin)
        var phone = store(phoneDisk, policy: .keepRunning, origin: phoneOrigin)
        let macSync = SyncEngine(store: mac, transport: server, persistence: InMemorySyncStatePersistence(SyncState(deviceID: "mac")))
        let phoneState = InMemorySyncStatePersistence(SyncState(deviceID: "phone"))
        var phoneSync = SyncEngine(store: phone, transport: server, persistence: phoneState)

        let goal = phone.addTask(title: "Study")!
        phone.startTimer(id: goal.id, at: ago(900))
        await phoneSync.syncNow(); await macSync.syncNow()
        XCTAssertEqual(mac.runningTimerTaskID, goal.id)

        // Phone app closed for a while, then opened; the Mac app is relaunched meanwhile too.
        phone = store(phoneDisk, policy: .keepRunning, origin: phoneOrigin)
        phoneSync = SyncEngine(store: phone, transport: server, persistence: phoneState)
        let macAgain = store(macDisk, policy: .creditToLastCheckpoint, origin: macOrigin)
        let macAgainSync = SyncEngine(store: macAgain, transport: server, persistence: InMemorySyncStatePersistence(SyncState(deviceID: "mac")))
        await phoneSync.syncNow(); await macAgainSync.syncNow(); await phoneSync.syncNow()

        XCTAssertEqual(phone.runningTimerTaskID, goal.id)
        XCTAssertEqual(macAgain.runningTimerTaskID, goal.id)
    }

    /// The report, as it used to behave: a device that recovers every timer it finds at launch
    /// sends a stop that wins over the timer another device is genuinely running.
    func testWithoutOriginTrackingARelaunchStopsTheOtherDevicesTimer() async {
        let server = FakeSyncServer()
        let macDisk = MockTaskPersistence(), phoneDisk = MockTaskPersistence()
        let mac = store(macDisk, policy: .creditToLastCheckpoint, origin: InMemoryTimerOrigin())
        var phone = store(phoneDisk, policy: .creditToLastCheckpoint, origin: nil)   // the old behaviour
        let macSync = SyncEngine(store: mac, transport: server, persistence: InMemorySyncStatePersistence(SyncState(deviceID: "mac")))
        let phoneState = InMemorySyncStatePersistence(SyncState(deviceID: "phone"))
        var phoneSync = SyncEngine(store: phone, transport: server, persistence: phoneState)

        let goal = mac.addTask(title: "Study")!
        await macSync.syncNow(); await phoneSync.syncNow()
        mac.startTimer(id: goal.id, at: ago(600))
        await macSync.syncNow(); await phoneSync.syncNow()

        phone = store(phoneDisk, policy: .creditToLastCheckpoint, origin: nil)
        phoneSync = SyncEngine(store: phone, transport: server, persistence: phoneState)
        await phoneSync.syncNow(); await macSync.syncNow()

        XCTAssertNil(mac.runningTimerTaskID, "this is the bug the origin marker removes")
    }

    /// The Mac pauses a timer the phone started while the phone app is closed. Nothing can reach a
    /// suspended app, but the moment it syncs again it must agree, and the time must be the Mac's.
    func testAPauseOnTheMacReachesThePhoneWhenItSyncsAgain() async {
        let server = FakeSyncServer()
        let mac = store(MockTaskPersistence(), policy: .creditToLastCheckpoint, origin: InMemoryTimerOrigin())
        let phone = store(MockTaskPersistence(), policy: .keepRunning, origin: InMemoryTimerOrigin())
        let macSync = SyncEngine(store: mac, transport: server, persistence: InMemorySyncStatePersistence(SyncState(deviceID: "mac")))
        let phoneSync = SyncEngine(store: phone, transport: server, persistence: InMemorySyncStatePersistence(SyncState(deviceID: "phone")))

        let goal = phone.addTask(title: "Study")!
        phone.startTimer(id: goal.id, at: ago(1_800))
        await phoneSync.syncNow(); await macSync.syncNow()
        XCTAssertEqual(mac.runningTimerTaskID, goal.id, "the Mac sees the phone's timer")

        // The phone app is closed. The Mac stops the timer.
        mac.pauseTimer(id: goal.id, at: Date())
        await macSync.syncNow()

        // The phone app opens: one sync and it knows.
        await phoneSync.syncNow()

        XCTAssertNil(phone.runningTimerTaskID)
        let banked = phone.allTasks.first!.focusSessions.map(\.seconds).reduce(0, +)
        XCTAssertEqual(banked, 1_800, accuracy: 2)
    }
}
