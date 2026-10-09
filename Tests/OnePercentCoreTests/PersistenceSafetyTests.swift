import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

final class PersistenceSafetyTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("op-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testUnreadableFileIsCopiedAsideBeforeItCanBeOverwritten() throws {
        let file = dir.appendingPathComponent("tasks.json")
        try Data("{ not json".utf8).write(to: file)
        let controller = PersistenceController(fileURL: file)

        XCTAssertThrowsError(try controller.loadTasks())

        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("tasks.corrupt-") }, "siblings: \(siblings)")
    }

    func testSavingKeepsThePreviousVersionAsBackup() throws {
        let file = dir.appendingPathComponent("tasks.json")
        let controller = PersistenceController(fileURL: file)
        let first = TaskItem(title: "first", scheduledDate: Date())
        let second = TaskItem(title: "second", scheduledDate: Date())

        try controller.saveTasks([first])
        try controller.saveTasks([first, second])

        let backup = dir.appendingPathComponent("tasks.json.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode([TaskItem].self, from: Data(contentsOf: backup))
        XCTAssertEqual(old.map(\.title), ["first"])
    }

    func testHabitsRoundTripThroughDisk() throws {
        let file = dir.appendingPathComponent("habits.json")
        let controller = HabitPersistenceController(fileURL: file)
        let habit = Habit(title: "Read", schedule: .weekdays, startDate: Date(), tags: ["mind"])
        try controller.saveHabits([habit])
        let loaded = try controller.loadHabits()
        XCTAssertEqual(loaded.map(\.id), [habit.id])
        XCTAssertEqual(loaded.first?.schedule, .weekdays)
        XCTAssertEqual(loaded.first?.tags, ["mind"])
    }

    func testMissingHabitsFileLoadsEmpty() throws {
        let controller = HabitPersistenceController(fileURL: dir.appendingPathComponent("none.json"))
        XCTAssertEqual(try controller.loadHabits(), [])
    }
}
