import Foundation

/// A websocket, reduced to what the Realtime client needs (so tests can script one).
public protocol RealtimeSocket: Sendable {
    func connect(to url: URL) async throws
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

public final class URLSessionRealtimeSocket: RealtimeSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?

    public init() {}

    public func connect(to url: URL) async throws {
        let task = URLSession.shared.webSocketTask(with: url)
        lock.withLock { self.task = task }
        task.resume()
    }

    public func send(_ text: String) async throws {
        guard let task = lock.withLock({ task }) else { throw SyncError.offline }
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        guard let task = lock.withLock({ task }) else { throw SyncError.offline }
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }

    public func close() {
        lock.withLock { task }?.cancel(with: .goingAway, reason: nil)
    }
}

/// What a message from the Realtime server means to us.
public enum RealtimeEvent: Equatable, Sendable {
    /// The subscription is active.
    case joined
    /// A row of `sync_records` changed.
    case change
    /// The server refused the subscription or closed the channel: reconnect.
    case failed
    case other
}

public enum RealtimeProtocol {
    public static let topic = "realtime:one-percent-sync"

    public static func joinMessage(userID: UUID, accessToken: String) -> String {
        encode([
            "topic": topic,
            "event": "phx_join",
            "payload": [
                "config": [
                    "broadcast": ["ack": false, "self": false],
                    "presence": ["key": ""],
                    "postgres_changes": [[
                        "event": "*", "schema": "public", "table": "sync_records",
                        "filter": "user_id=eq.\(userID.uuidString.lowercased())"
                    ]],
                    "private": false
                ],
                "access_token": accessToken
            ],
            "ref": "1",
            "join_ref": "1"
        ])
    }

    public static func heartbeat(ref: Int) -> String {
        encode(["topic": "phoenix", "event": "heartbeat", "payload": [String: String](), "ref": String(ref)])
    }

    public static func parse(_ text: String) -> RealtimeEvent {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let event = object["event"] as? String else { return .other }
        switch event {
        case "postgres_changes":
            return .change
        case "phx_reply":
            let payload = object["payload"] as? [String: Any]
            let ok = (payload?["status"] as? String) == "ok"
            // Heartbeat replies arrive on the "phoenix" topic; only the channel's own reply decides.
            if (object["topic"] as? String) == topic { return ok ? .joined : .failed }
            return ok ? .other : .failed
        case "phx_error", "phx_close":
            return .failed
        case "system":
            return (object["payload"] as? [String: Any])?["status"] as? String == "error" ? .failed : .other
        default:
            return .other
        }
    }

    private static func encode(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }
}

/// A live "something changed" signal. It carries no data: each signal makes the engine pull, so a
/// missed or doubled message can never corrupt anything. It also fires on every (re)connection, to
/// catch up on whatever happened while the socket was down.
public final class SupabaseRealtime: @unchecked Sendable {
    private let config: SupabaseConfig
    private let auth: SupabaseAuth
    private let makeSocket: @Sendable () -> RealtimeSocket
    private let heartbeatInterval: TimeInterval
    private let tokenMargin: TimeInterval

    public init(
        config: SupabaseConfig = .onePercent,
        auth: SupabaseAuth,
        heartbeatInterval: TimeInterval = 25,
        tokenMargin: TimeInterval = 90,
        makeSocket: @escaping @Sendable () -> RealtimeSocket = { URLSessionRealtimeSocket() }
    ) {
        self.config = config
        self.auth = auth
        self.heartbeatInterval = heartbeatInterval
        self.tokenMargin = tokenMargin
        self.makeSocket = makeSocket
    }

    public func nudges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { await self.run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var socketURL: URL {
        var components = URLComponents(url: config.url.appendingPathComponent("realtime/v1/websocket"), resolvingAgainstBaseURL: false)!
        components.scheme = config.url.scheme == "http" ? "ws" : "wss"
        components.queryItems = [URLQueryItem(name: "apikey", value: config.publishableKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return components.url!
    }

    private func run(_ continuation: AsyncStream<Void>.Continuation) async {
        var backoff: TimeInterval = 1
        while !Task.isCancelled {
            do {
                try await connectOnce(continuation)
                backoff = 1
            } catch is CancellationError {
                return
            } catch {
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 30)
            }
        }
    }

    private func connectOnce(_ continuation: AsyncStream<Void>.Continuation) async throws {
        let session = try await auth.validSession()
        let socket = makeSocket()
        try await socket.connect(to: socketURL)
        defer { socket.close() }
        try await socket.send(RealtimeProtocol.joinMessage(userID: session.userID, accessToken: session.accessToken))

        let keepAlive = Task { [heartbeatInterval] in
            var ref = 2
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                if Task.isCancelled { break }
                try? await socket.send(RealtimeProtocol.heartbeat(ref: ref))
                ref += 1
            }
        }
        // The socket is authorised with this token only; reconnect with a fresh one before it lapses.
        let renewal = Task { [tokenMargin] in
            let wait = max(1, session.expiresAt.timeIntervalSinceNow - tokenMargin)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if !Task.isCancelled { socket.close() }
        }
        defer { keepAlive.cancel(); renewal.cancel() }

        while !Task.isCancelled {
            switch RealtimeProtocol.parse(try await socket.receive()) {
            case .joined, .change: continuation.yield()
            case .failed: throw SyncError.offline
            case .other: continue
            }
        }
        throw CancellationError()
    }
}
