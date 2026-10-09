import Foundation

/// Keeps the sign-in session in a private file next to the app's other data (readable only by you).
///
/// The Mac app is signed ad hoc, so every new version looks like a different program to the
/// Keychain, which would ask for permission again after each update. This file holds the same
/// goals and habits that already sit unencrypted in this folder, and only login tokens (never the
/// password), so it gives up nothing the folder does not already expose. The iPhone app uses the Keychain.
public final class FileSecretStore: SecretStoring, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppStorageLocation.directory().appendingPathComponent("session.json")
    }

    private func load() -> [String: Data] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([String: Data].self, from: data) else { return [:] }
        return items
    }

    private func save(_ items: [String: Data]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func read(_ account: String) -> Data? { lock.withLock { load()[account] } }

    public func write(_ data: Data, account: String) {
        lock.withLock {
            var items = load()
            items[account] = data
            save(items)
        }
    }

    public func delete(_ account: String) {
        lock.withLock {
            var items = load()
            items[account] = nil
            if items.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
            } else {
                save(items)
            }
        }
    }
}
