import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

/// A websocket that plays back scripted server messages and records what the client sends.
final class ScriptedSocket: RealtimeSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [String]
    private(set) var sent: [String] = []
    private(set) var url: URL?
    private(set) var closed = false

    init(_ messages: [String]) { incoming = messages }

    func connect(to url: URL) async throws { lock.withLock { self.url = url } }
    func send(_ text: String) async throws { lock.withLock { sent.append(text) } }
    func close() { lock.withLock { closed = true } }

    func receive() async throws -> String {
        while true {
            if let next = lock.withLock({ incoming.isEmpty ? nil : incoming.removeFirst() }) { return next }
            if lock.withLock({ closed }) { throw SyncError.offline }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

final class SupabaseRealtimeTests: XCTestCase {
    private let config = SupabaseConfig(url: URL(string: "https://abc.supabase.co")!, publishableKey: "sb_publishable_test")
    private let joinedReply = #"{"topic":"realtime:one-percent-sync","event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"1"}"#
    private let changeEvent = #"{"topic":"realtime:one-percent-sync","event":"postgres_changes","payload":{"data":{"type":"UPDATE"}},"ref":null}"#

    func testJoinMessageAsksForTheUsersRowsOnly() throws {
        let user = UUID()
        let message = RealtimeProtocol.joinMessage(userID: user, accessToken: "jwt")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])
        XCTAssertEqual(object["event"] as? String, "phx_join")
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(payload["access_token"] as? String, "jwt")
        let changes = try XCTUnwrap((payload["config"] as? [String: Any])?["postgres_changes"] as? [[String: String]])
        XCTAssertEqual(changes, [["event": "*", "schema": "public", "table": "sync_records", "filter": "user_id=eq.\(user.uuidString.lowercased())"]])
    }

    func testMessagesAreClassified() {
        XCTAssertEqual(RealtimeProtocol.parse(joinedReply), .joined)
        XCTAssertEqual(RealtimeProtocol.parse(changeEvent), .change)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:one-percent-sync","event":"phx_reply","payload":{"status":"error","response":{"reason":"nope"}},"ref":"1"}"#), .failed)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:one-percent-sync","event":"phx_close","payload":{}}"#), .failed)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"phoenix","event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"2"}"#), .other, "a heartbeat reply is not a join")
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:one-percent-sync","event":"system","payload":{"status":"ok","message":"Subscribed"}}"#), .other)
        XCTAssertEqual(RealtimeProtocol.parse("garbage"), .other)
    }

    func testHeartbeatShape() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(RealtimeProtocol.heartbeat(ref: 7).utf8)) as? [String: Any])
        XCTAssertEqual(object["topic"] as? String, "phoenix")
        XCTAssertEqual(object["event"] as? String, "heartbeat")
        XCTAssertEqual(object["ref"] as? String, "7")
    }

    private func signedInAuth() async throws -> SupabaseAuth {
        let http = StubHTTP { _ in (tokenResponse(), 200) }
        let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: http)
        _ = try await auth.signIn(email: "me@example.com", password: "pw")
        return auth
    }

    func testConnectingJoinsTheChannelAndSignalsOnJoinAndOnEveryChange() async throws {
        let socket = ScriptedSocket([joinedReply, changeEvent, changeEvent])
        let realtime = SupabaseRealtime(config: config, auth: try await signedInAuth(), heartbeatInterval: 60, makeSocket: { socket })

        var signals = 0
        for await _ in realtime.nudges() {
            signals += 1
            if signals == 3 { break }
        }
        XCTAssertEqual(signals, 3, "one on joining (to catch up) and one per change")
        let url = try XCTUnwrap(socket.url)
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "abc.supabase.co")
        XCTAssertEqual(url.path, "/realtime/v1/websocket")
        XCTAssertTrue(url.query?.contains("apikey=sb_publishable_test") == true)
        XCTAssertTrue(socket.sent.first?.contains("phx_join") == true)
    }

    func testAFailedJoinReconnectsAndSignalsAgain() async throws {
        let sockets = [
            ScriptedSocket([#"{"topic":"realtime:one-percent-sync","event":"phx_reply","payload":{"status":"error","response":{}},"ref":"1"}"#]),
            ScriptedSocket([joinedReply])
        ]
        let counter = LockedCounter()
        let realtime = SupabaseRealtime(config: config, auth: try await signedInAuth(), heartbeatInterval: 60, makeSocket: {
            sockets[min(counter.increment() - 1, sockets.count - 1)]
        })
        var signals = 0
        for await _ in realtime.nudges() { signals += 1; break }
        XCTAssertEqual(signals, 1)
        XCTAssertGreaterThanOrEqual(counter.value, 2, "it connected again after the refusal")
    }

    func testHeartbeatsKeepTheConnectionAlive() async throws {
        let socket = ScriptedSocket([joinedReply])
        let realtime = SupabaseRealtime(config: config, auth: try await signedInAuth(), heartbeatInterval: 0.05, makeSocket: { socket })
        let stream = realtime.nudges()
        let task = Task { for await _ in stream { } }
        try await Task.sleep(nanoseconds: 400_000_000)
        task.cancel()
        let beats = socket.sent.filter { $0.contains("heartbeat") }
        XCTAssertGreaterThanOrEqual(beats.count, 3)
    }

    func testStoppingTheStreamClosesTheSocket() async throws {
        let socket = ScriptedSocket([joinedReply])
        let realtime = SupabaseRealtime(config: config, auth: try await signedInAuth(), heartbeatInterval: 60, makeSocket: { socket })
        let task = Task { for await _ in realtime.nudges() { break } }
        await task.value
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(socket.closed)
    }
}

/// Opt-in check against the real project. Skipped unless credentials are in the environment:
///   ONEPERCENT_LIVE_EMAIL=… ONEPERCENT_LIVE_PASSWORD=… swift test --filter LiveSupabaseTests
@MainActor
final class LiveSupabaseTests: XCTestCase {
    private func credentials() throws -> (String, String) {
        guard let email = ProcessInfo.processInfo.environment["ONEPERCENT_LIVE_EMAIL"],
              let password = ProcessInfo.processInfo.environment["ONEPERCENT_LIVE_PASSWORD"] else {
            throw XCTSkip("set ONEPERCENT_LIVE_EMAIL and ONEPERCENT_LIVE_PASSWORD to test against the real project")
        }
        return (email, password)
    }

    func testSyncAndRealtimeAgainstTheRealProject() async throws {
        let (email, password) = try credentials()
        let auth = SupabaseAuth(secrets: InMemorySecretStore())
        _ = try await auth.signIn(email: email, password: password)
        let transport = SupabaseTransport(auth: auth)

        // A device syncs a goal up and another one receives it.
        let mac = Device("live-test-mac", server: transport)
        let phone = Device("live-test-phone", server: transport)
        let task = mac.add("Live sync check \(UUID().uuidString.prefix(6))")
        await settle(mac, phone, rounds: 2)
        XCTAssertNotNil(phone.task(task.id), "the goal reached the second device through the real server")
        XCTAssertEqual(mac.engine.status.isSynced, true)

        // The live channel announces a change made elsewhere.
        let realtime = SupabaseRealtime(auth: auth)
        let signals = LockedCounter()
        let listener = Task { for await _ in realtime.nudges() { _ = signals.increment() } }
        defer { listener.cancel() }
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let afterJoin = signals.value
        XCTAssertGreaterThanOrEqual(afterJoin, 1, "joining the channel signals")

        mac.store.updateTaskStatus(id: task.id, newStatus: .done)
        await mac.sync()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertGreaterThan(signals.value, afterJoin, "a change is announced live")

        // Leave no trace (a tombstone stays, which purge_tombstones() removes later).
        mac.store.deleteTask(id: task.id)
        await settle(mac, phone, rounds: 2)
    }
}
