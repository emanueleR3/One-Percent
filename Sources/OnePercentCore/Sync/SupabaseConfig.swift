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

    /// The Info.plist keys the build fills in from `Config/OnePercent.xcconfig` (and your
    /// `Config/Local.xcconfig`).
    public static let hostInfoKey = "OnePercentSupabaseHost"
    public static let keyInfoKey = "OnePercentSupabaseKey"

    /// The project this build was set up with, or nil when it has none: cloud sync is then off.
    public static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        make(
            host: bundle.object(forInfoDictionaryKey: hostInfoKey) as? String,
            key: bundle.object(forInfoDictionaryKey: keyInfoKey) as? String
        )
    }

    /// `host` is the project's host, `abcd.supabase.co` (an .xcconfig file cannot hold "//"); a
    /// full `https://` URL is accepted too. Nil when either value is missing or unusable.
    public static func make(host: String?, key: String?) -> SupabaseConfig? {
        let host = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unset build setting reaches the Info.plist as "" or, from some tools, as "$(NAME)".
        // "https:" is what is left of a full URL once Xcode has read "//" as a comment.
        guard !host.isEmpty, !key.isEmpty, !host.contains("$("), !key.contains("$("), !host.hasSuffix(":") else {
            return nil
        }
        let text = host.contains("://") ? host : "https://" + host
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let name = url.host, !name.isEmpty else { return nil }
        return SupabaseConfig(url: url, publishableKey: key)
    }

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
