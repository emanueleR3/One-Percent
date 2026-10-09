import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

/// A seeded, reproducible stream of numbers.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Two devices, a shared server and a long run of random edits with syncs at random moments:
/// once everything has settled both must hold exactly the same data, and the rules a single
/// device keeps (one "The One" a day, one running timer, one copy of a habit day) must hold too.
@MainActor
final class SyncConvergenceTests: XCTestCase {
    func randomStepForReuse(on device: Device, using rng: inout SeededGenerator) { randomStep(on: device, using: &rng) }

    private func randomStep(on device: Device, using rng: inout SeededGenerator) {
        let store = device.store
        let tasks = store.allTasks
        func pick() -> TaskItem? { tasks.randomElement(using: &rng) }
        switch Int.random(in: 0..<100, using: &rng) {
        case 0..<22:
            device.add("Goal \(Int.random(in: 0..<10_000, using: &rng))", offset: Int.random(in: -2...3, using: &rng))
        case 22..<36:
            if let t = pick() { store.updateTaskStatus(id: t.id, newStatus: [.todo, .inProgress, .done].randomElement(using: &rng)!) }
        case 36..<46:
            if let t = pick() { _ = store.updateTaskTitle(id: t.id, newTitle: "Renamed \(Int.random(in: 0..<10_000, using: &rng))") }
        case 46..<56:
            if let t = pick() { store.deleteTask(id: t.id) }
        case 56..<64:
            if let t = pick() { store.setTheOne(id: t.id) }
        case 64..<70:
            if let t = pick() { store.addTag(["lavoro", "brain", "casa"].randomElement(using: &rng)!, to: t.id) }
        case 70..<75:
            if let t = pick() { store.addSubtask(to: t.id, title: "step \(Int.random(in: 0..<100, using: &rng))") }
        case 75..<81:
            if let t = pick() { _ = store.startTimer(id: t.id) }
        case 81..<85:
            store.pauseRunningTimer()
        case 85..<89:
            if let t = pick() { store.deferTask(id: t.id) }
        case 89..<93:
            _ = store.addHabit(title: "Habit \(Int.random(in: 0..<100, using: &rng))", schedule: .daily, startDate: device.day(0))
        case 93..<96:
            if let h = store.habits.randomElement(using: &rng) { store.deleteHabit(id: h.id) }
        case 96..<98:
            if let h = store.habits.randomElement(using: &rng) { store.updateHabitSchedule(id: h.id, schedule: .weekdays) }
        default:
            if let t = pick() { store.updateNote(id: t.id, note: "note \(Int.random(in: 0..<100, using: &rng))") }
        }
    }

    private func assertInvariants(_ device: Device, file: StaticString = #filePath, line: UInt = #line) {
        let tasks = device.store.allTasks
        XCTAssertLessThanOrEqual(tasks.filter(\.isTimerRunning).count, 1, "\(device.name): one running timer", file: file, line: line)
        let theOnes = Dictionary(grouping: tasks.filter { $0.isTheOne && $0.status != .deferred }) { device.dateService.normalize($0.scheduledDate) }
        for (day, ones) in theOnes {
            XCTAssertEqual(ones.count, 1, "\(device.name): one The One on \(day)", file: file, line: line)
        }
        let habitDays = Dictionary(grouping: tasks.filter { $0.habitID != nil }) { "\($0.habitID!)|\(device.dateService.normalize($0.scheduledDate))" }
        for (key, group) in habitDays {
            XCTAssertEqual(group.count, 1, "\(device.name): one copy of \(key)", file: file, line: line)
        }
    }

    private func run(seed: UInt64, steps: Int) async {
        var rng = SeededGenerator(seed: seed)
        let server = FakeSyncServer()
        let mac = Device("mac", server: server)
        let phone = Device("phone", server: server)

        for _ in 0..<steps {
            let device = Bool.random(using: &rng) ? mac : phone
            randomStep(on: device, using: &rng)
            if Int.random(in: 0..<100, using: &rng) < 35 {
                await (Bool.random(using: &rng) ? mac : phone).sync()
            }
        }

        await settle(mac, phone, rounds: 6)
        assertSameState(mac, phone)
        assertInvariants(mac)
        assertInvariants(phone)

        // The server's verdict is what both devices must show: deleted there means gone here.
        for record in server.storedRecords {
            for device in [mac, phone] {
                let present = device.task(record.id) != nil || device.store.habits.contains { $0.id == record.id }
                XCTAssertEqual(present, !record.deleted, "seed \(seed): \(device.name) disagrees with the server about \(record.id) (\(record.kind), deleted: \(record.deleted))")
            }
        }

        // Once settled, another full round must not move anything.
        server.resetCounters()
        await settle(mac, phone, rounds: 2)
        XCTAssertEqual(server.pushedRecords, 0, "seed \(seed): settled devices stay quiet")
    }

    func testRandomEditsConvergeAcrossManySeeds() async {
        for seed in 1...150 {
            await run(seed: UInt64(seed), steps: 70)
            if testRun?.hasBeenSkipped == true || (testRun?.failureCount ?? 0) > 0 {
                XCTFail("stopped at seed \(seed)")
                return
            }
        }
    }
}
