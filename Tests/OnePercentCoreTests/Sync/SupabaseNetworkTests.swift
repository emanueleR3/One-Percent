import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

/// Answers HTTP requests from a closure and remembers them.
final class StubHTTP: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [URLRequest] = []
    var handler: @Sendable (URLRequest) throws -> (Data, Int)

    init(_ handler: @escaping @Sendable (URLRequest) throws -> (Data, Int)) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { log } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { log.append(request) }
        let (data, status) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
func bodyJSON(_ request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

let userID = UUID()
func tokenResponse(access: String = "access-1", refresh: String = "refresh-1", expiresIn: Double = 3600) -> Data {
    json([
        "access_token": access, "refresh_token": refresh, "expires_in": expiresIn, "token_type": "bearer",
        "user": ["id": userID.uuidString.lowercased(), "email": "me@example.com"]
    ])
}

final class SupabaseAuthTests: XCTestCase {
    private let config = SupabaseConfig(url: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")

    func testSigningInStoresTheSessionAndSendsTheRightRequest() async throws {
        let secrets = InMemorySecretStore()
        let http = StubHTTP { _ in (tokenResponse(), 200) }
        let auth = SupabaseAuth(config: config, secrets: secrets, http: http)

        let session = try await auth.signIn(email: "  me@example.com ", password: "pw")

        XCTAssertEqual(session.accessToken, "access-1")
        XCTAssertEqual(session.userID, userID)
        XCTAssertEqual(session.email, "me@example.com")
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/auth/v1/token?grant_type=password")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertEqual(bodyJSON(request)["email"] as? String, "me@example.com", "the email is trimmed")
        XCTAssertEqual(bodyJSON(request)["password"] as? String, "pw")
        XCTAssertNotNil(secrets.read("session"), "the session is kept in the secret store")
    }

    func testWrongPasswordIsReportedAndNothingIsStored() async {
        let secrets = InMemorySecretStore()
        let http = StubHTTP { _ in (json(["error_code": "invalid_credentials", "msg": "Invalid login credentials"]), 400) }
        let auth = SupabaseAuth(config: config, secrets: secrets, http: http)
        do {
            _ = try await auth.signIn(email: "a@b.c", password: "bad")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        XCTAssertNil(secrets.read("session"))
        let current = await auth.currentSession()
        XCTAssertNil(current)
    }

    func testUnconfirmedEmailAndOfflineAreTold() async {
        let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(),
                                http: StubHTTP { _ in (json(["error_code": "email_not_confirmed", "msg": "Email not confirmed"]), 400) })
        do { _ = try await auth.signIn(email: "a@b.c", password: "x"); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .emailNotConfirmed) }

        let offline = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: StubHTTP { _ in throw URLError(.notConnectedToInternet) })
        do { _ = try await offline.signIn(email: "a@b.c", password: "x"); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .offline) }
    }

    func testASessionSurvivesARestart() async throws {
        let secrets = InMemorySecretStore()
        let first = SupabaseAuth(config: config, secrets: secrets, http: StubHTTP { _ in (tokenResponse(), 200) })
        _ = try await first.signIn(email: "me@example.com", password: "pw")

        let second = SupabaseAuth(config: config, secrets: secrets, http: StubHTTP { _ in XCTFail("no request needed"); return (Data(), 500) })
        let restored = try await second.validSession()
        XCTAssertEqual(restored.accessToken, "access-1")
    }

    func testAnExpiringTokenIsRefreshedWithTheRefreshToken() async throws {
        let calls = LockedCounter()
        let http = StubHTTP { request in
            let n = calls.increment()
            if request.url!.absoluteString.contains("grant_type=refresh_token") {
                XCTAssertEqual(bodyJSON(request)["refresh_token"] as? String, "refresh-1")
                return (tokenResponse(access: "access-2", refresh: "refresh-2"), 200)
            }
            _ = n
            return (tokenResponse(expiresIn: 30), 200)   // expires almost at once
        }
        let secrets = InMemorySecretStore()
        let auth = SupabaseAuth(config: config, secrets: secrets, http: http)
        _ = try await auth.signIn(email: "me@example.com", password: "pw")

        let refreshed = try await auth.validSession()
        XCTAssertEqual(refreshed.accessToken, "access-2")
        XCTAssertEqual(refreshed.refreshToken, "refresh-2", "the new single-use refresh token replaces the old one")
        let stored = try JSONDecoder().decode(AuthSession.self, from: try XCTUnwrap(secrets.read("session")))
        XCTAssertEqual(stored.refreshToken, "refresh-2")
    }

    func testAFreshTokenIsNotRefreshed() async throws {
        let http = StubHTTP { _ in (tokenResponse(expiresIn: 3600), 200) }
        let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: http)
        _ = try await auth.signIn(email: "me@example.com", password: "pw")
        _ = try await auth.validSession()
        _ = try await auth.validSession()
        XCTAssertEqual(http.requests.count, 1)
    }

    func testManyCallersRefreshOnlyOnce() async throws {
        let refreshes = LockedCounter()
        let http = StubHTTP { request in
            if request.url!.absoluteString.contains("grant_type=refresh_token") {
                _ = refreshes.increment()
                return (tokenResponse(access: "access-2", refresh: "refresh-2"), 200)
            }
            return (tokenResponse(expiresIn: 30), 200)
        }
        let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: http)
        _ = try await auth.signIn(email: "me@example.com", password: "pw")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try? await auth.validSession() } }
        }
        XCTAssertEqual(refreshes.value, 1, "refresh tokens are single use, so the refresh must not run in parallel")
    }

    func testARevokedRefreshTokenSignsTheDeviceOut() async throws {
        let http = StubHTTP { request in
            if request.url!.absoluteString.contains("grant_type=refresh_token") {
                return (json(["error_code": "refresh_token_not_found", "msg": "Invalid Refresh Token"]), 400)
            }
            return (tokenResponse(expiresIn: 30), 200)
        }
        let secrets = InMemorySecretStore()
        let auth = SupabaseAuth(config: config, secrets: secrets, http: http)
        _ = try await auth.signIn(email: "me@example.com", password: "pw")
        do { _ = try await auth.validSession(); XCTFail() } catch { XCTAssertEqual(error as? SyncError, .notSignedIn) }
        XCTAssertNil(secrets.read("session"))
    }

    func testWithoutASessionThereIsNothingToUse() async {
        let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: StubHTTP { _ in (Data(), 500) })
        do { _ = try await auth.validSession(); XCTFail() } catch { XCTAssertEqual(error as? SyncError, .notSignedIn) }
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}

final class SupabaseTransportTests: XCTestCase {
    private let config = SupabaseConfig(url: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")

    private func signedIn(_ http: StubHTTP, authHTTP: StubHTTP? = nil) async throws -> SupabaseTransport {
        let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: authHTTP ?? StubHTTP { _ in (tokenResponse(), 200) })
        _ = try await auth.signIn(email: "me@example.com", password: "pw")
        return SupabaseTransport(config: config, auth: auth, http: http)
    }

    func testPushSendsEveryFieldAndNestsTheJSONData() async throws {
        let http = StubHTTP { request in
            let id = ((bodyJSON(request)["p_records"] as? [[String: Any]])?.first?["id"] as? String) ?? ""
            return (json([["r_id": id, "r_applied": true, "r_server_updated_at": "2026-10-09T11:22:33.123456+00:00"]]), 200)
        }
        let transport = try await signedIn(http)
        let id = UUID()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000.5)
        let outcome = try await transport.push([
            SyncRecord(id: id, kind: .task, data: Data(#"{"title":"Gym","n":1}"#.utf8), clientUpdatedAt: stamp, deviceID: "mac")
        ])

        XCTAssertEqual(outcome, [PushOutcome(id: id, applied: true)])
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/rest/v1/rpc/push_records")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let record = try XCTUnwrap((bodyJSON(request)["p_records"] as? [[String: Any]])?.first)
        XCTAssertEqual(record["id"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(record["kind"] as? String, "task")
        XCTAssertEqual((record["data"] as? [String: Any])?["title"] as? String, "Gym", "data is a JSON object, not a string")
        XCTAssertEqual(record["client_updated_at"] as? String, "2027-01-15T08:00:00.500000Z")
        XCTAssertEqual(record["deleted"] as? Bool, false)
        XCTAssertEqual(record["device_id"] as? String, "mac")
    }

    func testPullAsksForNewerRowsInOrderAndReadsWhatPostgresReturns() async throws {
        let rowID = UUID()
        let http = StubHTTP { _ in
            (json([
                ["id": rowID.uuidString.lowercased(), "kind": "habit", "data": ["title": "Gym"],
                 "client_updated_at": "2026-10-09T11:00:00.5+00:00", "server_updated_at": "2026-10-09T11:00:01.123456+00:00",
                 "deleted": false, "device_id": "phone"],
                ["id": UUID().uuidString.lowercased(), "kind": "somethingnew", "data": [:],
                 "client_updated_at": "2026-10-09T11:00:00+00:00", "server_updated_at": "2026-10-09T11:00:02+00:00",
                 "deleted": false, "device_id": "x"]
            ]), 200)
        }
        let transport = try await signedIn(http)
        let records = try await transport.pull(since: Date(timeIntervalSince1970: 1_800_000_000), limit: 500)

        XCTAssertEqual(records.count, 1, "a kind this version does not know is skipped")
        XCTAssertEqual(records[0].id, rowID)
        XCTAssertEqual(records[0].kind, .habit)
        XCTAssertEqual(records[0].deviceID, "phone")
        XCTAssertEqual(records[0].clientUpdatedAt, WireDate.parse("2026-10-09T11:00:00.5Z"))
        XCTAssertEqual(records[0].serverUpdatedAt, WireDate.parse("2026-10-09T11:00:01.123456Z"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: records[0].data) as? [String: String], ["title": "Gym"])

        let url = try XCTUnwrap(http.requests.first?.url)
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["order"], "server_updated_at.asc,id.asc")
        XCTAssertEqual(items["limit"], "500")
        XCTAssertEqual(items["server_updated_at"], "gt.2027-01-15T08:00:00.000000Z")
        XCTAssertTrue(items["select"]!.contains("server_updated_at"))
    }

    func testARejectedTokenIsRefreshedOnceAndTheRequestRepeated() async throws {
        let attempts = LockedCounter()
        let http = StubHTTP { request in
            attempts.increment() == 1 ? (json(["message": "JWT expired"]), 401) : (json([]), 200)
        }
        let authHTTP = StubHTTP { request in
            request.url!.absoluteString.contains("refresh_token") ? (tokenResponse(access: "access-2", refresh: "refresh-2"), 200) : (tokenResponse(), 200)
        }
        let transport = try await signedIn(http, authHTTP: authHTTP)
        let records = try await transport.pull(since: nil, limit: 10)
        XCTAssertEqual(records, [])
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(http.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testStillRejectedMeansSignedOut() async throws {
        let http = StubHTTP { _ in (json(["message": "JWT expired"]), 401) }
        let authHTTP = StubHTTP { _ in (tokenResponse(), 200) }
        let transport = try await signedIn(http, authHTTP: authHTTP)
        do { _ = try await transport.pull(since: nil, limit: 10); XCTFail() } catch { XCTAssertEqual(error as? SyncError, .notSignedIn) }
    }

    func testNetworkAndServerFailuresAreTranslated() async throws {
        let offline = try await signedIn(StubHTTP { _ in throw URLError(.notConnectedToInternet) })
        do { _ = try await offline.pull(since: nil, limit: 1); XCTFail() } catch { XCTAssertEqual(error as? SyncError, .offline) }

        let broken = try await signedIn(StubHTTP { _ in (json(["message": "boom"]), 500) })
        do { _ = try await broken.pull(since: nil, limit: 1); XCTFail() } catch { XCTAssertEqual(error as? SyncError, .server(status: 500, message: "boom")) }

        let garbage = try await signedIn(StubHTTP { _ in (Data("<html>".utf8), 200) })
        do { _ = try await garbage.pull(since: nil, limit: 1); XCTFail() } catch { XCTAssertEqual(error as? SyncError, .invalidResponse) }
    }

    func testNotBeingSignedInStopsBeforeAnyRequest() async {
        let http = StubHTTP { _ in XCTFail("no request without a session"); return (Data(), 500) }
        let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: http)
        let transport = SupabaseTransport(config: config, auth: auth, http: http)
        do { _ = try await transport.pull(since: nil, limit: 1); XCTFail() } catch { XCTAssertEqual(error as? SyncError, .notSignedIn) }
    }
}
