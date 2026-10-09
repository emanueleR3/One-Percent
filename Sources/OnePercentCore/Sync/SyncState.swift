import Foundation

/// What this device last agreed on with the server for one item.
public struct KnownRecord: Codable, Equatable, Sendable {
    public var kind: SyncKind
    /// The version's time (`client_updated_at`) and the device that wrote it.
    public var stamp: Date
    public var deviceID: String
    /// Fingerprint of the item as it was then. A different fingerprint means a local edit.
    public var fingerprint: String
    public var deleted: Bool

    public init(kind: SyncKind, stamp: Date, deviceID: String, fingerprint: String, deleted: Bool) {
        self.kind = kind
        self.stamp = stamp
        self.deviceID = deviceID
        self.fingerprint = fingerprint
        self.deleted = deleted
    }
}

/// Everything sync remembers between runs. Losing it is safe: the next run merges again from scratch.
public struct SyncState: Codable, Equatable, Sendable {
    /// Identifies this install; breaks ties between edits made at the same instant.
    public var deviceID: String
    /// Server time of the newest record already received.
    public var cursor: Date?
    public var known: [UUID: KnownRecord]

    public init(deviceID: String = UUID().uuidString.lowercased(), cursor: Date? = nil, known: [UUID: KnownRecord] = [:]) {
        self.deviceID = deviceID
        self.cursor = cursor
        self.known = known
    }
}

public protocol SyncStatePersisting: Sendable {
    func load() throws -> SyncState?
    func save(_ state: SyncState) throws
    func erase() throws
}

public final class InMemorySyncStatePersistence: SyncStatePersisting, @unchecked Sendable {
    public private(set) var stored: SyncState?
    public var saveCount = 0

    public init(_ initial: SyncState? = nil) { stored = initial }

    public func load() throws -> SyncState? { stored }
    public func save(_ state: SyncState) throws { stored = state; saveCount += 1 }
    public func erase() throws { stored = nil }
}

/// `sync-state.json` next to the other app files.
public final class FileSyncStatePersistence: SyncStatePersisting, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppStorageLocation.directory().appendingPathComponent("sync-state.json")
    }

    public func load() throws -> SyncState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        // Plain seconds: the stamps keep their sub-second precision, which conflicts depend on.
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(SyncState.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ state: SyncState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }

    public func erase() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
