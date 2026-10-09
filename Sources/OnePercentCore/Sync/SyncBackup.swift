import Foundation

/// A copy of the goal and habit files, made right before this device first merges with the cloud.
/// Merging never deletes what only exists here, but a copy costs nothing.
public enum SyncBackup {
    public static let folderName = "pre-sync-backups"
    public static let keep = 5

    /// Copies `tasks.json` and `habits.json` into `pre-sync-backups/<timestamp>/` and forgets all but
    /// the newest few. Returns the new folder, or nil when there was nothing to copy.
    @discardableResult
    public static func make(
        storage: URL = AppStorageLocation.directory(),
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> URL? {
        let sources = ["tasks.json", "habits.json"]
            .map { storage.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        guard !sources.isEmpty else { return nil }

        let root = storage.appendingPathComponent(folderName, isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var folder = root.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        var suffix = 1
        while fileManager.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(formatter.string(from: now))-\(suffix)", isDirectory: true)
            suffix += 1
        }

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in sources {
                try fileManager.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
            }
        } catch {
            return nil
        }
        prune(root: root, fileManager: fileManager)
        return folder
    }

    private static func prune(root: URL, fileManager: FileManager) {
        guard let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        // Names start with the timestamp, so alphabetical order is chronological.
        let sorted = folders.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in sorted.dropLast(keep) {
            try? fileManager.removeItem(at: old)
        }
    }
}
