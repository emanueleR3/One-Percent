import Foundation
import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

/// A stand-in for the Supabase table with the same rules as `push_records`: an incoming change
/// wins only if its (time, device) is larger than the stored one; the server stamps every applied change.
final class FakeSyncServer: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [UUID: SyncRecord] = [:]
    private var tick = 0
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    /// Every pushed record, in order, for diagnosing runs that do not settle.
    private(set) var pushLog: [(id: UUID, deleted: Bool, device: String, applied: Bool)] = []
    private(set) var pushCalls = 0
    private(set) var pulledRecords = 0
    private(set) var pushedRecords = 0
    /// Throw this from the next call(s).
    var failure: SyncError?
    var failPushOnly = false

    var storedRecords: [SyncRecord] { lock.withLock { rows.values.sorted { $0.serverUpdatedAt! < $1.serverUpdatedAt! } } }

    func stamp() -> Date {
        tick += 1
        return epoch.addingTimeInterval(Double(tick) * 0.001)
    }

    func push(_ records: [SyncRecord]) async throws -> [PushOutcome] {
        try lock.withLock {
            if let failure { throw failure }
            pushCalls += 1
            pushedRecords += records.count
            return records.map { incoming in
                var applied = false
                if let existing = rows[incoming.id] {
                    applied = (incoming.clientUpdatedAt, incoming.deviceID) > (existing.clientUpdatedAt, existing.deviceID)
                } else {
                    applied = true
                }
                if applied {
                    var stored = incoming
                    stored.serverUpdatedAt = stamp()
                    rows[incoming.id] = stored
                }
                pushLog.append((incoming.id, incoming.deleted, incoming.deviceID, applied))
                return PushOutcome(id: incoming.id, applied: applied)
            }
        }
    }

    func pull(since: Date?, limit: Int) async throws -> [SyncRecord] {
        try lock.withLock {
            if let failure, !failPushOnly { throw failure }
            let page = rows.values
                .filter { since == nil || $0.serverUpdatedAt! > since! }
                .sorted { $0.serverUpdatedAt! < $1.serverUpdatedAt! }
                .prefix(limit)
            pulledRecords += page.count
            return Array(page)
        }
    }

    /// Plants a row directly, as another client would have left it.
    func plant(_ record: SyncRecord, serverUpdatedAt: Date? = nil) {
        lock.withLock {
            var stored = record
            stored.serverUpdatedAt = serverUpdatedAt ?? stamp()
            rows[record.id] = stored
        }
    }

    func resetCounters() { lock.withLock { pushCalls = 0; pulledRecords = 0; pushedRecords = 0; pushLog = [] } }
}

/// One install: its own store, its own sync state, a shared server.
@MainActor
final class Device {
    let name: String
    let store: TaskStore
    let engine: SyncEngine
    let statePersistence: InMemorySyncStatePersistence
    let calendar: Calendar
    let dateService: DateService

    init(_ name: String, server: SyncTransport, state: InMemorySyncStatePersistence? = nil) {
        self.name = name
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = cal
        self.dateService = DateService(calendar: cal)
        self.store = TaskStore(persistence: MockTaskPersistence(), dateService: dateService, habitPersistence: InMemoryHabitPersistence())
        self.statePersistence = state ?? InMemorySyncStatePersistence(SyncState(deviceID: name))
        self.engine = SyncEngine(store: store, transport: server, persistence: self.statePersistence)
    }

    func day(_ offset: Int = 0) -> Date {
        dateService.normalize(calendar.date(byAdding: .day, value: offset, to: dateService.today)!)
    }

    @discardableResult
    func add(_ title: String, offset: Int = 0, tags: [String] = []) -> TaskItem {
        store.addTask(title: title, for: day(offset), tags: tags)!
    }

    func task(_ id: UUID) -> TaskItem? { store.allTasks.first { $0.id == id } }
    func titles(on offset: Int = 0) -> [String] { store.tasks(for: day(offset)).map(\.title) }

    func sync() async { await engine.syncNow() }
}

/// Both devices up to date with each other.
@MainActor
func settle(_ devices: Device..., rounds: Int = 4) async {
    for _ in 0..<rounds {
        for device in devices { await device.sync() }
    }
}

@MainActor
func assertSameState(_ a: Device, _ b: Device, file: StaticString = #filePath, line: UInt = #line) {
    func fingerprints(_ d: Device) -> [UUID: String] {
        var out: [UUID: String] = [:]
        for t in d.store.allTasks { out[t.id] = SyncCodec.fingerprint(try! SyncCodec.encode(t)) }
        for h in d.store.habits { out[h.id] = SyncCodec.fingerprint(try! SyncCodec.encode(h)) }
        return out
    }
    let fa = fingerprints(a), fb = fingerprints(b)
    XCTAssertEqual(Set(fa.keys), Set(fb.keys), "\(a.name) and \(b.name) hold different items", file: file, line: line)
    for (id, f) in fa where fb[id] != nil && fb[id] != f {
        let ta = a.task(id), tb = b.task(id)
        XCTFail("item \(id) differs: \(a.name)=\(String(describing: ta?.title)) \(String(describing: ta?.status)) vs \(b.name)=\(String(describing: tb?.title)) \(String(describing: tb?.status))", file: file, line: line)
    }
}
