import Foundation
import Combine

/// Keeps a `TaskStore` in step with the server.
///
/// The store stays the source of truth and works offline. Each run does three things:
///   1. pull what other devices changed and fold it in (`TaskStore.applyRemote`);
///   2. find what changed locally by comparing every item's fingerprint with the one remembered
///      from the last sync (this also catches deletions: an item that is gone);
///   3. push those changes. The server keeps whichever version of an item is newer.
/// Nothing here needs a hook in the store's own operations, so every edit is picked up.
@MainActor
public final class SyncEngine: ObservableObject {
    public enum Status: Equatable, Sendable {
        case idle
        case syncing
        case synced(Date)
        case offline
        case signedOut
        case failed(String)
    }

    @Published public private(set) var status: Status = .idle
    /// Records the server sent that this version of the app could not read (a newer app wrote them).
    @Published public private(set) var unreadableRecords = 0

    public static let pageSize = 500
    public static let pushBatchSize = 200
    /// Pulls start this far before the newest record already seen, because rows can become
    /// visible out of order. Applying a record twice is harmless.
    public static let pullOverlap: TimeInterval = 10
    /// A device whose clock runs ahead cannot win every conflict forever.
    public static let maxClockSkew: TimeInterval = 300

    private let store: TaskStore
    private let transport: SyncTransport
    private let persistence: SyncStatePersisting
    private let now: () -> Date
    private var state: SyncState

    private var isSyncing = false
    private var syncAgain = false
    private var cancellables = Set<AnyCancellable>()
    private var loopTask: Task<Void, Never>?
    private var nudgeTask: Task<Void, Never>?
    private var failures = 0

    public var deviceID: String { state.deviceID }

    public init(
        store: TaskStore,
        transport: SyncTransport,
        persistence: SyncStatePersisting,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.transport = transport
        self.persistence = persistence
        self.now = now
        self.state = ((try? persistence.load()) ?? nil) ?? SyncState()
        try? persistence.save(state)
    }

    // MARK: - Running

    /// Syncs now and keeps syncing: shortly after every local change and on a slow timer, as a
    /// safety net for anything a live connection might miss.
    public func start(debounce: TimeInterval = 1.5, interval: TimeInterval = 60, nudges: AsyncStream<Void>? = nil) {
        stop()
        store.$allTasks.map { _ in () }
            .merge(with: store.$habits.map { _ in () })
            .dropFirst(2)
            .debounce(for: .seconds(debounce), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { await self.syncNow() }
            }
            .store(in: &cancellables)

        loopTask = Task { [weak self] in
            await self?.syncNow()
            while !Task.isCancelled {
                let wait = self?.nextWait(base: interval) ?? interval
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.syncNow()
            }
        }
        if let nudges {
            nudgeTask = Task { [weak self] in
                for await _ in nudges {
                    guard let self else { return }
                    await self.syncNow()
                }
            }
        }
    }

    public func stop() {
        cancellables.removeAll()
        loopTask?.cancel()
        loopTask = nil
        // Ending the loop also ends the live connection that feeds it.
        nudgeTask?.cancel()
        nudgeTask = nil
    }

    /// After failures wait longer (up to five minutes) instead of hammering a server that is down.
    private func nextWait(base: TimeInterval) -> TimeInterval {
        failures == 0 ? base : min(300, base * pow(2, Double(min(failures, 5))))
    }

    /// Forgets what was synced (after signing out). Local goals stay; signing in again merges them anew.
    public func reset() {
        stop()
        state = SyncState(deviceID: state.deviceID)
        try? persistence.save(state)
        status = .idle
    }

    // MARK: - One run

    /// Runs a full pull / push cycle. If another run is already going, asks it to go round again.
    public func syncNow() async {
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        repeat {
            syncAgain = false
            do {
                try await runUntilSettled()
                failures = 0
                status = .synced(now())
            } catch let error as SyncError {
                failures += 1
                switch error {
                case .notSignedIn: status = .signedOut
                case .offline: status = .offline
                case .server(let code, let message): status = .failed("\(code): \(message)")
                case .invalidResponse: status = .failed("Invalid response")
                }
                return
            } catch is CancellationError {
                return
            } catch let error as URLError {
                failures += 1
                status = error.code == .cancelled ? .idle : .offline
                return
            } catch {
                failures += 1
                status = .failed(error.localizedDescription)
                return
            }
        } while syncAgain
    }

    /// Pull, push, and go round again while the server turns out to hold something newer.
    private func runUntilSettled() async throws {
        for _ in 0..<3 {
            try await pullAndApply()
            let needsAnotherPull = try await pushLocalChanges()
            if !needsAnotherPull { return }
        }
    }

    // MARK: Pull

    private func pullAndApply() async throws {
        var records: [SyncRecord] = []
        var newest = state.cursor
        var since = state.cursor.map { $0.addingTimeInterval(-Self.pullOverlap) }

        while true {
            let page = try await transport.pull(since: since, limit: Self.pageSize)
            records.append(contentsOf: page)
            guard let last = page.last?.serverUpdatedAt else { break }
            newest = max(newest ?? last, last)
            // A full page ending on the instant we asked from cannot make progress; stop rather than loop.
            if page.count < Self.pageSize || last == since { break }
            since = last
        }

        apply(records)
        if let newest, newest != state.cursor { state.cursor = newest }
        try? persistence.save(state)
    }

    private func apply(_ records: [SyncRecord]) {
        guard !records.isEmpty else { return }
        let local = snapshot()
        var changes = TaskStore.RemoteChanges()
        var unreadable = 0

        // The same id can appear twice (the overlap): the later row is the newer state.
        var latest: [UUID: SyncRecord] = [:]
        for record in records { latest[record.id] = record }

        for record in latest.values {
            let known = state.known[record.id]
            let mine = local[record.id]

            // Our own push coming back, or a row already handled.
            if let known, known.deleted == record.deleted, known.deviceID == record.deviceID, known.stamp == record.clientUpdatedAt {
                continue
            }

            // What this device would say about the item right now.
            let hasLocalChange: Bool = {
                if let mine { return known == nil || known!.deleted || known!.fingerprint != mine.fingerprint }
                return known != nil && !(known!.deleted)   // deleted here, not yet told the server
            }()
            if hasLocalChange {
                let localStamp = pendingStamp(forID: record.id, item: mine, known: known)
                if (record.clientUpdatedAt, record.deviceID) <= (localStamp, state.deviceID) { continue }
            } else if let known, (record.clientUpdatedAt, record.deviceID) <= (known.stamp, known.deviceID) {
                continue   // an older or repeated version of what we already hold
            }

            if record.deleted {
                if mine != nil {
                    switch record.kind {
                    case .task: changes.deletedTaskIDs.insert(record.id)
                    case .habit: changes.deletedHabitIDs.insert(record.id)
                    }
                }
                state.known[record.id] = KnownRecord(
                    kind: record.kind, stamp: record.clientUpdatedAt, deviceID: record.deviceID,
                    fingerprint: "", deleted: true
                )
                continue
            }

            do {
                let fingerprint: String
                switch record.kind {
                case .task:
                    let task = try SyncCodec.decodeTask(record.data)
                    fingerprint = SyncCodec.fingerprint(try SyncCodec.encode(task))
                    if mine?.fingerprint != fingerprint { changes.tasks.append(task) }
                case .habit:
                    let habit = try SyncCodec.decodeHabit(record.data)
                    fingerprint = SyncCodec.fingerprint(try SyncCodec.encode(habit))
                    if mine?.fingerprint != fingerprint { changes.habits.append(habit) }
                }
                state.known[record.id] = KnownRecord(
                    kind: record.kind, stamp: record.clientUpdatedAt, deviceID: record.deviceID,
                    fingerprint: fingerprint, deleted: false
                )
            } catch {
                unreadable += 1
            }
        }

        unreadableRecords = unreadable
        store.applyRemote(changes)
    }

    // MARK: Local changes

    /// An item as it is now, with the fingerprint of its encoding.
    private struct LocalItem {
        var kind: SyncKind
        var data: Data
        var fingerprint: String
        var updatedAt: Date?
    }

    private func snapshot() -> [UUID: LocalItem] {
        var items: [UUID: LocalItem] = [:]
        items.reserveCapacity(store.allTasks.count + store.habits.count)
        for task in store.allTasks {
            guard let data = try? SyncCodec.encode(task) else { continue }
            items[task.id] = LocalItem(kind: .task, data: data, fingerprint: SyncCodec.fingerprint(data), updatedAt: task.updatedAt)
        }
        for habit in store.habits {
            guard let data = try? SyncCodec.encode(habit) else { continue }
            items[habit.id] = LocalItem(kind: .habit, data: data, fingerprint: SyncCodec.fingerprint(data), updatedAt: nil)
        }
        return items
    }

    /// The time to give a local change: the item's own edit time when it has one newer than the
    /// last synced version, otherwise now. Always later than the version it replaces.
    private func pendingStamp(for item: LocalItem, known: KnownRecord?) -> Date {
        let current = now()
        let ceiling = current.addingTimeInterval(Self.maxClockSkew)
        var stamp = current
        if let updatedAt = item.updatedAt, updatedAt > (known?.stamp ?? .distantPast) {
            stamp = min(updatedAt, ceiling)
        }
        if let known, stamp <= known.stamp { stamp = known.stamp.addingTimeInterval(0.001) }
        return WireDate.normalized(stamp)
    }

    /// The time a local change (an edit, or a deletion when `item` is nil) would carry if sent now.
    /// Pulling and pushing must use this same function, and the result is rounded the way the
    /// server rounds it: if they disagreed by a microsecond, a tie could be judged one way here and
    /// the other way there, and the loser would keep re-sending forever.
    private func pendingStamp(forID id: UUID, item: LocalItem?, known: KnownRecord?) -> Date {
        if let item { return pendingStamp(for: item, known: known) }
        // A deletion carries the moment it really happened, when this session saw it; otherwise now.
        let removedAt = min(store.removalDate(for: id) ?? now(), now())
        return WireDate.normalized(max(removedAt, (known?.stamp ?? .distantPast).addingTimeInterval(0.001)))
    }

    /// Sends everything that changed here. Returns true if the server refused some because it
    /// holds newer versions, which a fresh pull will bring in.
    private func pushLocalChanges() async throws -> Bool {
        let local = snapshot()
        var outgoing: [(record: SyncRecord, fingerprint: String)] = []

        for (id, item) in local {
            let known = state.known[id]
            guard known == nil || known!.deleted || known!.fingerprint != item.fingerprint else { continue }
            let stamp = pendingStamp(for: item, known: known)
            outgoing.append((
                SyncRecord(id: id, kind: item.kind, data: item.data, clientUpdatedAt: stamp, deviceID: state.deviceID),
                item.fingerprint
            ))
        }
        for (id, known) in state.known where !known.deleted && local[id] == nil {
            // The moment it was really removed, when this session saw it; otherwise now.
            let stamp = pendingStamp(forID: id, item: nil, known: known)
            outgoing.append((
                SyncRecord(id: id, kind: known.kind, data: Data("{}".utf8), clientUpdatedAt: stamp, deleted: true, deviceID: state.deviceID),
                ""
            ))
        }
        guard !outgoing.isEmpty else { return false }

        // Oldest first, so a batch that fails halfway leaves the older changes already stored.
        outgoing.sort { $0.record.clientUpdatedAt < $1.record.clientUpdatedAt }
        var refused = false
        var index = 0
        while index < outgoing.count {
            let batch = Array(outgoing[index..<min(index + Self.pushBatchSize, outgoing.count)])
            index += batch.count
            let outcomes = try await transport.push(batch.map(\.record))
            let applied = Dictionary(outcomes.map { ($0.id, $0.applied) }, uniquingKeysWith: { _, last in last })
            for entry in batch {
                guard let wasApplied = applied[entry.record.id] else { continue }
                if wasApplied {
                    if entry.record.deleted { store.forgetRemovals([entry.record.id]) }
                    state.known[entry.record.id] = KnownRecord(
                        kind: entry.record.kind, stamp: entry.record.clientUpdatedAt, deviceID: state.deviceID,
                        fingerprint: entry.fingerprint, deleted: entry.record.deleted
                    )
                } else {
                    refused = true
                }
            }
            try? persistence.save(state)
        }
        return refused
    }
}
