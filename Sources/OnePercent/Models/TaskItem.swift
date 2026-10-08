import Foundation

/// Core task occurrence entity defined in ONE_PERCENT_SPEC.md (Section 5.1)
/// Distinct occurrences possess unique identifiers; identical titles on different occurrences
/// or dates are explicitly preserved and not treated as duplicates.
struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var status: TaskStatus
    var scheduledDate: Date
    var createdAt: Date
    var updatedAt: Date
    var sourceTaskID: UUID?
    var deferredToTaskID: UUID?
    var deferredAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .todo,
        scheduledDate: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceTaskID: UUID? = nil,
        deferredToTaskID: UUID? = nil,
        deferredAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.scheduledDate = scheduledDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceTaskID = sourceTaskID
        self.deferredToTaskID = deferredToTaskID
        self.deferredAt = deferredAt
    }
}
