import Foundation

protocol TaskPersisting: Sendable {
    func loadTasks() throws -> [TaskItem]
    func saveTasks(_ tasks: [TaskItem]) throws
}

/// Folder shared by every file the app writes (`~/Library/Application Support/OnePercent`).
enum AppStorageLocation {
    static func directory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folderURL = appSupport.appendingPathComponent("OnePercent", isDirectory: true)
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        return folderURL
    }
}

/// Atomically persists and retrieves tasks in local JSON storage (Section 5.4)
///
/// Two safety nets, because the first write after a failed read would otherwise destroy the file:
/// an unreadable `tasks.json` is copied to `tasks.corrupt-<time>.json` before it can be replaced,
/// and every save keeps the previous version as `tasks.json.bak`.
final class PersistenceController: TaskPersisting, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = AppStorageLocation.directory(fileManager: fileManager).appendingPathComponent("tasks.json")
        }
    }

    func loadTasks() throws -> [TaskItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([TaskItem].self, from: data)
        } catch {
            preserveUnreadableFile()
            throw error
        }
    }

    func saveTasks(_ tasks: [TaskItem]) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tasks)
        keepPreviousVersion()
        try data.write(to: fileURL, options: .atomic)
    }

    private func keepPreviousVersion() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let backup = fileURL.appendingPathExtension("bak")
        try? fileManager.removeItem(at: backup)
        try? fileManager.copyItem(at: fileURL, to: backup)
    }

    private func preserveUnreadableFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent("\(name).corrupt-\(stamp).json")
        try? fileManager.copyItem(at: fileURL, to: destination)
    }
}
