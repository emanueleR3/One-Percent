import Foundation

protocol HabitPersisting: Sendable {
    func loadHabits() throws -> [Habit]
    func saveHabits(_ habits: [Habit]) throws
}

/// Habit definitions live next to `tasks.json`, in `habits.json`.
final class HabitPersistenceController: HabitPersisting, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? AppStorageLocation.directory(fileManager: fileManager).appendingPathComponent("habits.json")
    }

    func loadHabits() throws -> [Habit] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Habit].self, from: data)
    }

    func saveHabits(_ habits: [Habit]) throws {
        let parent = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(habits).write(to: fileURL, options: .atomic)
    }
}

/// Default for tests and previews: nothing touches the disk.
final class InMemoryHabitPersistence: HabitPersisting, @unchecked Sendable {
    private(set) var stored: [Habit] = []

    func loadHabits() throws -> [Habit] { stored }
    func saveHabits(_ habits: [Habit]) throws { stored = habits }
}
