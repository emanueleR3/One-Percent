import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

@MainActor
final class SyncEngineTests: XCTestCase {
    private var server: FakeSyncServer!
    private var mac: Device!
    private var phone: Device!

    override func setUp() async throws {
        server = FakeSyncServer()
        mac = Device("mac", server: server)
        phone = Device("phone", server: server)
    }

    // MARK: Basics

    func testFirstSyncUploadsEverythingAndTheOtherDeviceDownloadsIt() async {
        mac.add("Write report", tags: ["lavoro"])
        mac.add("Call mom", offset: 1)
        _ = mac.store.addHabit(title: "Gym", schedule: .daily, startDate: mac.day(0))

        await mac.sync()
        XCTAssertEqual(mac.engine.status.isSynced, true)
        XCTAssertGreaterThanOrEqual(server.storedRecords.count, 3)

        await phone.sync()
        XCTAssertEqual(phone.titles(on: 0).sorted(), ["Gym", "Write report"])
        XCTAssertEqual(phone.titles(on: 1).sorted(), ["Call mom", "Gym"], "the daily habit shows up tomorrow too")
        XCTAssertEqual(phone.store.habits.map(\.title), ["Gym"])
        XCTAssertEqual(phone.store.allTasks.first { $0.title == "Write report" }?.tags, ["lavoro"])
        assertSameState(mac, phone)
    }

    func testNothingChangedMeansNothingIsSent() async {
        mac.add("A")
        await settle(mac, phone)
        server.resetCounters()

        await mac.sync()
        await phone.sync()
        XCTAssertEqual(server.pushedRecords, 0, "an idle sync pushes nothing")
    }

    func testEditsReachTheOtherDevice() async {
        let task = mac.add("Draft")
        await settle(mac, phone)

        mac.store.updateTaskStatus(id: task.id, newStatus: .done)
        _ = mac.store.updateTaskTitle(id: task.id, newTitle: "Draft v2")
        await settle(mac, phone)

        XCTAssertEqual(phone.task(task.id)?.title, "Draft v2")
        XCTAssertEqual(phone.task(task.id)?.status, .done)
    }

    func testDeletionsReachTheOtherDevice() async {
        let keep = mac.add("Keep")
        let drop = mac.add("Drop")
        await settle(mac, phone)
        XCTAssertNotNil(phone.task(drop.id))

        mac.store.deleteTask(id: drop.id)
        await settle(mac, phone)

        XCTAssertNil(phone.task(drop.id))
        XCTAssertNotNil(phone.task(keep.id))
        let tombstone = server.storedRecords.first { $0.id == drop.id }
        XCTAssertEqual(tombstone?.deleted, true, "the server remembers the deletion")
    }

    func testDeletingTwiceOrReSyncingDoesNotResurrectAnything() async {
        let task = mac.add("Once")
        await settle(mac, phone)
        mac.store.deleteTask(id: task.id)
        await settle(mac, phone, rounds: 3)
        XCTAssertNil(mac.task(task.id))
        XCTAssertNil(phone.task(task.id))
    }

    // MARK: Conflicts

    func testWhenBothEditOfflineTheLaterEditWins() async throws {
        let task = mac.add("Plan")
        await settle(mac, phone)

        _ = mac.store.updateTaskTitle(id: task.id, newTitle: "Mac title")
        try await Task.sleep(nanoseconds: 5_000_000)
        _ = phone.store.updateTaskTitle(id: task.id, newTitle: "Phone title")

        await settle(mac, phone)
        XCTAssertEqual(mac.task(task.id)?.title, "Phone title")
        XCTAssertEqual(phone.task(task.id)?.title, "Phone title")
        assertSameState(mac, phone)
    }

    func testAnOlderRemoteEditDoesNotOverwriteANewerLocalOne() async throws {
        let task = mac.add("Plan")
        await settle(mac, phone)

        _ = phone.store.updateTaskTitle(id: task.id, newTitle: "Phone title")
        await phone.sync()
        try await Task.sleep(nanoseconds: 5_000_000)
        _ = mac.store.updateTaskTitle(id: task.id, newTitle: "Mac title, later")

        await settle(mac, phone)
        XCTAssertEqual(mac.task(task.id)?.title, "Mac title, later")
        XCTAssertEqual(phone.task(task.id)?.title, "Mac title, later")
    }

    func testEditsToDifferentGoalsBothSurvive() async {
        let a = mac.add("A")
        let b = mac.add("B")
        await settle(mac, phone)

        _ = mac.store.updateTaskTitle(id: a.id, newTitle: "A (mac)")
        phone.store.updateTaskStatus(id: b.id, newStatus: .done)
        await settle(mac, phone)

        for device in [mac!, phone!] {
            XCTAssertEqual(device.task(a.id)?.title, "A (mac)")
            XCTAssertEqual(device.task(b.id)?.status, .done)
        }
    }

    func testADeletionBeatsAnOlderEditAndALaterEditBeatsADeletion() async throws {
        let gone = mac.add("Will be deleted")
        let kept = mac.add("Will be edited later")
        await settle(mac, phone)

        _ = phone.store.updateTaskTitle(id: gone.id, newTitle: "edited first")
        try await Task.sleep(nanoseconds: 5_000_000)
        mac.store.deleteTask(id: gone.id)

        mac.store.deleteTask(id: kept.id)
        try await Task.sleep(nanoseconds: 5_000_000)
        _ = phone.store.updateTaskTitle(id: kept.id, newTitle: "edited after the delete")

        await settle(mac, phone)
        XCTAssertNil(mac.task(gone.id)); XCTAssertNil(phone.task(gone.id))
        XCTAssertEqual(mac.task(kept.id)?.title, "edited after the delete")
        XCTAssertEqual(phone.task(kept.id)?.title, "edited after the delete")
    }

    func testTheOneStaysUniquePerDayAcrossDevices() async throws {
        let a = mac.add("A")
        let b = mac.add("B")
        await settle(mac, phone)

        mac.store.setTheOne(id: a.id)
        try await Task.sleep(nanoseconds: 5_000_000)
        phone.store.setTheOne(id: b.id)
        await settle(mac, phone)

        for device in [mac!, phone!] {
            XCTAssertEqual(device.store.allTasks.filter(\.isTheOne).map(\.title), ["B"], "\(device.name): only the latest choice is The One")
        }
        assertSameState(mac, phone)
    }

    func testOnlyOneTimerKeepsRunningAcrossDevices() async throws {
        let a = mac.add("A")
        let b = mac.add("B")
        await settle(mac, phone)

        XCTAssertTrue(mac.store.startTimer(id: a.id))
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(phone.store.startTimer(id: b.id))
        await settle(mac, phone)

        for device in [mac!, phone!] {
            XCTAssertEqual(device.store.allTasks.filter(\.isTimerRunning).map(\.title), ["B"], "\(device.name)")
        }
        assertSameState(mac, phone)
    }

    // MARK: Habits

    func testTheSameHabitDayNeverAppearsTwice() async {
        let habit = mac.store.addHabit(title: "Gym", schedule: .daily, startDate: mac.day(0))!
        await mac.sync()
        // The phone has not heard of the habit yet, so it cannot have its own occurrences.
        await phone.sync()
        mac.store.ensureHabitOccurrences()
        phone.store.ensureHabitOccurrences()
        await settle(mac, phone)

        for offset in 0...3 {
            XCTAssertEqual(mac.store.tasks(for: mac.day(offset)).filter { $0.habitID == habit.id }.count, 1, "mac day \(offset)")
            XCTAssertEqual(phone.store.tasks(for: phone.day(offset)).filter { $0.habitID == habit.id }.count, 1, "phone day \(offset)")
        }
        assertSameState(mac, phone)
    }

    func testOccurrencesBornOnBothSidesShareOneId() async {
        // Both devices know the habit but not each other's occurrences (as if they created them offline).
        let habit = mac.store.addHabit(title: "Gym", schedule: .daily, startDate: mac.day(0))!
        await mac.sync()
        await phone.sync()
        // Wipe what the pull brought in, then let each side generate its own again.
        phone.store.applyRemote(.init(deletedTaskIDs: Set(phone.store.allTasks.map(\.id))))
        phone.store.ensureHabitOccurrences()
        let macIDs = Set(mac.store.allTasks.filter { $0.habitID == habit.id }.map(\.id))
        let phoneIDs = Set(phone.store.allTasks.filter { $0.habitID == habit.id }.map(\.id))
        XCTAssertEqual(macIDs, phoneIDs, "derived ids make both copies the same goal")
    }

    func testAnOldRandomIdOccurrenceAndANewDerivedOneMergeIntoOne() async {
        let habit = mac.store.addHabit(title: "Gym", schedule: .daily, startDate: mac.day(0))!
        await settle(mac, phone)

        // Today's copy on the phone is replaced by one with a random id that has progress.
        let derived = phone.store.allTasks.first { $0.habitID == habit.id && $0.scheduledDate == phone.day(0) }!
        phone.store.deleteTask(id: derived.id)
        var legacy = derived
        legacy = TaskItem(title: derived.title, status: .done, scheduledDate: derived.scheduledDate, habitID: habit.id)
        phone.store.applyRemote(.init(tasks: [legacy]))
        await settle(mac, phone)

        for device in [mac!, phone!] {
            let today = device.store.tasks(for: device.day(0)).filter { $0.habitID == habit.id }
            XCTAssertEqual(today.count, 1, "\(device.name) has exactly one")
            XCTAssertEqual(today.first?.status, .done, "the copy with progress survives")
        }
        assertSameState(mac, phone)
    }

    func testStoppingAHabitStopsItEverywhere() async {
        let habit = mac.store.addHabit(title: "Gym", schedule: .daily, startDate: mac.day(0))!
        await settle(mac, phone)
        XCTAssertFalse(phone.store.allTasks.filter { $0.habitID == habit.id }.isEmpty)

        mac.store.deleteHabit(id: habit.id)
        await settle(mac, phone)

        XCTAssertTrue(phone.store.habits.isEmpty)
        XCTAssertTrue(phone.store.allTasks.filter { $0.habitID == habit.id }.isEmpty, "open occurrences go with the habit")
        assertSameState(mac, phone)
    }

    func testSkippingAHabitDayStaysSkipped() async {
        let habit = mac.store.addHabit(title: "Gym", schedule: .daily, startDate: mac.day(0))!
        await settle(mac, phone)
        let tomorrow = mac.store.tasks(for: mac.day(1)).first { $0.habitID == habit.id }!

        mac.store.deleteTask(id: tomorrow.id)
        await settle(mac, phone)

        XCTAssertTrue(phone.store.tasks(for: phone.day(1)).filter { $0.habitID == habit.id }.isEmpty)
        phone.store.ensureHabitOccurrences()
        XCTAssertTrue(phone.store.tasks(for: phone.day(1)).filter { $0.habitID == habit.id }.isEmpty, "not recreated on the other device")
    }

    // MARK: Failures and robustness

    func testAFailedPushKeepsTheChangesForNextTime() async {
        mac.add("Offline work")
        server.failure = .offline
        await mac.sync()
        XCTAssertEqual(mac.engine.status, .offline)
        XCTAssertTrue(server.storedRecords.isEmpty)

        server.failure = nil
        await mac.sync()
        XCTAssertEqual(server.storedRecords.count, 1)
        XCTAssertEqual(mac.engine.status.isSynced, true)
    }

    func testBeingSignedOutIsReportedNotTreatedAsAnError() async {
        server.failure = .notSignedIn
        await mac.sync()
        XCTAssertEqual(mac.engine.status, .signedOut)
    }

    func testAServerErrorIsReported() async {
        server.failure = .server(status: 500, message: "boom")
        await mac.sync()
        XCTAssertEqual(mac.engine.status, .failed("500: boom"))
    }

    func testWhatWasSyncedIsRememberedAcrossRestarts() async {
        mac.add("A")
        mac.add("B")
        await settle(mac, phone)
        server.resetCounters()

        // Same files on disk, new process.
        let reborn = Device("mac", server: server, state: mac.statePersistence)
        for task in mac.store.allTasks { reborn.store.applyRemote(.init(tasks: [task])) }
        await reborn.sync()
        XCTAssertEqual(server.pushedRecords, 0, "nothing is sent again after a restart")
    }

    func testLargeBacklogsArePulledInPages() async throws {
        let day = mac.day(0)
        for index in 0..<(SyncEngine.pageSize * 2 + 37) {
            let task = TaskItem(title: "T\(index)", scheduledDate: day, sortOrder: index)
            server.plant(SyncRecord(id: task.id, kind: .task, data: try SyncCodec.encode(task),
                                    clientUpdatedAt: WireDate.normalized(Date().addingTimeInterval(-3600)), deviceID: "other"))
        }
        await phone.sync()
        XCTAssertEqual(phone.store.allTasks.count, SyncEngine.pageSize * 2 + 37)
    }

    func testARowThatBecameVisibleLateIsStillPicked() async throws {
        mac.add("First")
        await mac.sync()
        await phone.sync()

        // A row whose server time is a little older than what the phone already saw.
        let late = TaskItem(title: "Late arrival", scheduledDate: phone.day(0))
        let newest = server.storedRecords.last!.serverUpdatedAt!
        server.plant(SyncRecord(id: late.id, kind: .task, data: try SyncCodec.encode(late),
                                clientUpdatedAt: WireDate.normalized(Date()), deviceID: "other"),
                     serverUpdatedAt: newest.addingTimeInterval(-2))
        await phone.sync()
        XCTAssertNotNil(phone.task(late.id), "the pull overlap catches rows that surface out of order")
    }

    func testRecordsThisAppCannotReadAreSkippedAndCounted() async throws {
        let good = TaskItem(title: "Readable", scheduledDate: phone.day(0))
        server.plant(SyncRecord(id: good.id, kind: .task, data: try SyncCodec.encode(good),
                                clientUpdatedAt: WireDate.normalized(Date()), deviceID: "other"))
        server.plant(SyncRecord(id: UUID(), kind: .task, data: Data("{\"from\":\"the future\"}".utf8),
                                clientUpdatedAt: WireDate.normalized(Date()), deviceID: "other"))
        await phone.sync()
        XCTAssertNotNil(phone.task(good.id))
        XCTAssertEqual(phone.engine.unreadableRecords, 1)
        XCTAssertEqual(phone.engine.status.isSynced, true)
    }

    func testResetForgetsTheServerButKeepsTheGoals() async {
        mac.add("Mine")
        await mac.sync()
        mac.engine.reset()
        XCTAssertEqual(mac.statePersistence.stored?.known.count, 0)
        XCTAssertEqual(mac.statePersistence.stored?.deviceID, "mac", "the device keeps its identity")
        XCTAssertEqual(mac.titles(), ["Mine"])

        server.resetCounters()
        await mac.sync()
        XCTAssertEqual(mac.titles(), ["Mine"], "signing in again merges, it does not duplicate")
        XCTAssertEqual(mac.store.allTasks.count, 1)
    }

    func testTwoDevicesDeletingTheSameGoalAtOnceSettleInsteadOfArguing() async throws {
        // The stored version carries a time just ahead of both devices' clocks, so both tombstones
        // get the very same floor time and only the device id can break the tie.
        var rng = SeededGenerator(seed: 7)
        for step in 0..<20 {
            let server = FakeSyncServer()
            let mac = Device("mac", server: server)
            let phone = Device("phone", server: server)
            let task = TaskItem(title: "Deleted twice", scheduledDate: mac.day(0))
            let ahead = WireDate.normalized(Date().addingTimeInterval(5 + Double.random(in: 0..<0.001, using: &rng)))
            server.plant(SyncRecord(id: task.id, kind: .task, data: try SyncCodec.encode(task), clientUpdatedAt: ahead, deviceID: "other"))
            await settle(mac, phone)
            XCTAssertNotNil(mac.task(task.id)); XCTAssertNotNil(phone.task(task.id))

            mac.store.deleteTask(id: task.id)
            phone.store.deleteTask(id: task.id)
            await settle(mac, phone, rounds: 3)

            server.resetCounters()
            await settle(mac, phone, rounds: 2)
            XCTAssertEqual(server.pushedRecords, 0, "step \(step): once the tie is decided nobody keeps re-sending")
            XCTAssertEqual(server.storedRecords.first { $0.id == task.id }?.deleted, true)
            XCTAssertNil(mac.task(task.id)); XCTAssertNil(phone.task(task.id))
        }
    }

    func testTwoDevicesStartingFromTheSameFileEndUpWithOneCopy() async {
        // Both installs once imported the same goals (same ids) before syncing existed.
        let shared = TaskItem(title: "Shared", scheduledDate: mac.day(0))
        mac.store.applyRemote(.init(tasks: [shared]))
        phone.store.applyRemote(.init(tasks: [shared]))
        await settle(mac, phone)
        XCTAssertEqual(mac.store.allTasks.count, 1)
        XCTAssertEqual(phone.store.allTasks.count, 1)
    }
}

extension SyncEngine.Status {
    var isSynced: Bool { if case .synced = self { return true } else { return false } }
}
