import Foundation

/// What a synced record holds. The server stores it as `kind`.
public enum SyncKind: String, Codable, Sendable {
    case task
    case habit
}

/// One item as it travels between a device and the server.
public struct SyncRecord: Equatable, Sendable {
    public var id: UUID
    public var kind: SyncKind
    /// The item's JSON (the same encoding as the local files).
    public var data: Data
    /// When the device last changed the item. Decides who wins a conflict.
    public var clientUpdatedAt: Date
    public var deleted: Bool
    public var deviceID: String
    /// Set by the server; nil on records that are about to be pushed.
    public var serverUpdatedAt: Date?

    public init(
        id: UUID,
        kind: SyncKind,
        data: Data,
        clientUpdatedAt: Date,
        deleted: Bool = false,
        deviceID: String,
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.data = data
        self.clientUpdatedAt = clientUpdatedAt
        self.deleted = deleted
        self.deviceID = deviceID
        self.serverUpdatedAt = serverUpdatedAt
    }
}

/// The server's answer for one pushed item.
public struct PushOutcome: Equatable, Sendable {
    public var id: UUID
    /// False when the server already held a newer version.
    public var applied: Bool

    public init(id: UUID, applied: Bool) {
        self.id = id
        self.applied = applied
    }
}

public enum SyncError: Error, Equatable, Sendable {
    case notSignedIn
    /// No network, a timeout, a dropped connection.
    case offline
    case server(status: Int, message: String)
    case invalidResponse
}

/// How a device talks to the server. The real one speaks to Supabase; tests use a fake.
public protocol SyncTransport: Sendable {
    /// Sends changes. Each is applied only if the server does not already hold a newer version.
    func push(_ records: [SyncRecord]) async throws -> [PushOutcome]
    /// Records stored after `since` (all of them when nil), oldest first, at most `limit`.
    func pull(since: Date?, limit: Int) async throws -> [SyncRecord]
}

/// Timestamps on the wire: UTC, up to microseconds (what the server keeps), so two edits made a
/// moment apart never look simultaneous.
public enum WireDate {
    /// The instant exactly as it will look after a trip through the server (microsecond precision),
    /// so a stamp we keep compares equal to the one that comes back.
    public static func normalized(_ date: Date) -> Date {
        parse(string(date)) ?? date
    }

    public static func string(_ date: Date) -> String {
        let total = date.timeIntervalSince1970
        var seconds = total.rounded(.down)
        var micros = Int(((total - seconds) * 1_000_000).rounded())
        if micros >= 1_000_000 { seconds += 1; micros -= 1_000_000 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%06dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, micros)
    }

    /// Understands what Postgres returns: `2026-10-09T11:22:33.123456+00:00`, trailing zeros
    /// trimmed (`.12345`), no fraction, `Z`, or another offset.
    public static func parse(_ text: String) -> Date? {
        let s = text.replacingOccurrences(of: " ", with: "T")
        guard let t = s.firstIndex(of: "T") else { return nil }
        let datePart = s[s.startIndex..<t]
        var timePart = s[s.index(after: t)...]

        var offsetSeconds = 0
        if timePart.hasSuffix("Z") {
            timePart = timePart.dropLast()
        } else if let signIndex = timePart.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let sign = timePart[signIndex] == "-" ? -1 : 1
            let offset = timePart[timePart.index(after: signIndex)...].replacingOccurrences(of: ":", with: "")
            timePart = timePart[timePart.startIndex..<signIndex]
            guard offset.count == 2 || offset.count == 4, let digits = Int(offset) else { return nil }
            let hours = offset.count == 2 ? digits : digits / 100
            let minutes = offset.count == 2 ? 0 : digits % 100
            offsetSeconds = sign * (hours * 3600 + minutes * 60)
        }

        let dateFields = datePart.split(separator: "-").compactMap { Int($0) }
        guard dateFields.count == 3 else { return nil }
        let clock = timePart.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let hms = clock[0].split(separator: ":").compactMap { Int($0) }
        guard hms.count == 3 else { return nil }

        var fraction = 0.0
        if clock.count == 2 {
            let digits = String(clock[1])
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Double("0." + digits) else { return nil }
            fraction = value
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let base = calendar.date(from: DateComponents(
            year: dateFields[0], month: dateFields[1], day: dateFields[2],
            hour: hms[0], minute: hms[1], second: hms[2]
        )) else { return nil }
        return base.addingTimeInterval(fraction - Double(offsetSeconds))
    }
}
