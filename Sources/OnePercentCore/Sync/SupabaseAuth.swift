import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: UUID
    public var email: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: UUID, email: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }
}

public enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case emailNotConfirmed
    case offline
    case server(status: Int, message: String)
}

/// Email + password sign-in against Supabase Auth, with automatic token refresh.
/// An actor, so two parts of the app asking for a token never refresh it twice (refresh tokens are single use).
public actor SupabaseAuth {
    private static let sessionAccount = "session"
    /// Refresh this long before the token really expires.
    private static let refreshMargin: TimeInterval = 120

    private let config: SupabaseConfig
    private let secrets: SecretStoring
    private let http: HTTPSending
    private let now: @Sendable () -> Date
    private var session: AuthSession?
    private var inFlightRefresh: Task<AuthSession, Error>?

    public init(
        config: SupabaseConfig = .onePercent,
        secrets: SecretStoring,
        http: HTTPSending = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.secrets = secrets
        self.http = http
        self.now = now
        if let data = secrets.read(Self.sessionAccount) {
            self.session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }

    /// Whoever is signed in (their token may need a refresh before use).
    public func currentSession() -> AuthSession? { session }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        let body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
        let fresh = try await requestToken(grant: "password", body: body)
        store(fresh)
        return fresh
    }

    /// A session whose token is good for at least a couple of minutes, refreshed if needed.
    /// Several callers at once share one refresh: an actor lets others in while it waits for the
    /// network, and a second refresh with the same single-use token would sign the device out.
    public func validSession() async throws -> AuthSession {
        guard let current = session else { throw SyncError.notSignedIn }
        if current.expiresAt.timeIntervalSince(now()) > Self.refreshMargin { return current }
        if let running = inFlightRefresh { return try await running.value }

        let task = Task { try await self.refresh(current) }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    private func refresh(_ current: AuthSession) async throws -> AuthSession {
        do {
            let refreshed = try await requestToken(grant: "refresh_token", body: ["refresh_token": current.refreshToken])
            store(refreshed)
            return refreshed
        } catch AuthError.invalidCredentials {
            // The refresh token was revoked or already used: this device has to sign in again.
            signOut()
            throw SyncError.notSignedIn
        } catch AuthError.offline {
            throw SyncError.offline
        } catch AuthError.server(let status, let message) {
            throw SyncError.server(status: status, message: message)
        } catch AuthError.emailNotConfirmed {
            throw SyncError.notSignedIn
        }
    }

    /// Forces a refresh even if the token looks fresh (the server just refused it).
    public func refreshNow() async throws -> AuthSession {
        guard session != nil else { throw SyncError.notSignedIn }
        session?.expiresAt = .distantPast
        return try await validSession()
    }

    public func signOut() {
        session = nil
        secrets.delete(Self.sessionAccount)
    }

    // MARK: - Requests

    private func store(_ session: AuthSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session) {
            secrets.write(data, account: Self.sessionAccount)
        }
    }

    private func requestToken(grant: String, body: [String: Any]) async throws -> AuthSession {
        var request = URLRequest(url: config.endpoint("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grant)]))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch is URLError {
            throw AuthError.offline
        }

        guard (200..<300).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = json?["error_code"] as? String ?? json?["error"] as? String ?? ""
            let message = json?["msg"] as? String ?? json?["error_description"] as? String ?? json?["message"] as? String ?? "HTTP \(response.statusCode)"
            if code == "email_not_confirmed" { throw AuthError.emailNotConfirmed }
            if response.statusCode == 400 || response.statusCode == 401 || code.contains("invalid") || code.contains("not_found") {
                throw AuthError.invalidCredentials
            }
            throw AuthError.server(status: response.statusCode, message: message)
        }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userID = (user["id"] as? String).flatMap(UUID.init(uuidString:)) else {
            throw AuthError.server(status: response.statusCode, message: "Unexpected sign-in response")
        }
        let lifetime = (json["expires_in"] as? Double) ?? 3600
        let expiresAt = (json["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? now().addingTimeInterval(lifetime)
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, userID: userID, email: user["email"] as? String ?? "")
    }
}
