import Foundation

/// Where the sync server lives. The publishable key is meant to ship inside the app: on its own it
/// can do nothing, because every table answers only to a signed-in user.
public struct SupabaseConfig: Equatable, Sendable {
    public var url: URL
    public var publishableKey: String

    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }

    /// The One Percent project (see `supabase/project.json`).
    public static let onePercent = SupabaseConfig(
        url: URL(string: "https://your-project-ref.supabase.co")!,
        publishableKey: "sb_publishable_your-key"
    )

    public func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }
}

/// The one thing the network code needs from URLSession, so tests can answer without a network.
public protocol HTTPSending: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPSending {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        return (data, http)
    }
}

/// A place to keep the sign-in session safely (the Keychain in the apps).
public protocol SecretStoring: Sendable {
    func read(_ account: String) -> Data?
    func write(_ data: Data, account: String)
    func delete(_ account: String)
}

public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    public init() {}
    public func read(_ account: String) -> Data? { lock.withLock { items[account] } }
    public func write(_ data: Data, account: String) { lock.withLock { items[account] = data } }
    public func delete(_ account: String) { lock.withLock { items[account] = nil } }
}
