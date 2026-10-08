import Foundation

protocol TaskPersisting: Sendable {
    func loadTasks() throws -> [TaskItem]
    func saveTasks(_ tasks: [TaskItem]) throws
}

/// Atomically persists and retrieves tasks in local JSON storage (Section 5.4)
final class PersistenceController: TaskPersisting, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            let folderURL = appSupport.appendingPathComponent("OnePercent", isDirectory: true)
            if !fileManager.fileExists(atPath: folderURL.path) {
                try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            self.fileURL = folderURL.appendingPathComponent("tasks.json")
        }
    }

    func loadTasks() throws -> [TaskItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TaskItem].self, from: data)
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
        try data.write(to: fileURL, options: .atomic)
    }
}
