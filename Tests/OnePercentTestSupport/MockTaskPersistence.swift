import OnePercentCore

/// Keeps tasks in memory so a store can be built without touching disk.
public final class MockTaskPersistence: TaskPersisting, @unchecked Sendable {
    public var storedTasks: [TaskItem] = []

    public init() {}

    public func loadTasks() throws -> [TaskItem] {
        storedTasks
    }

    public func saveTasks(_ tasks: [TaskItem]) throws {
        storedTasks = tasks
    }
}
