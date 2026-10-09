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
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .todo,
        scheduledDate: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceTaskID: UUID? = nil,
        deferredToTaskID: UUID? = nil,
        deferredAt: Date? = nil,
        sortOrder: Int = 0
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
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id, title, status, scheduledDate, createdAt, updatedAt
        case sourceTaskID, deferredToTaskID, deferredAt, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.status = try container.decode(TaskStatus.self, forKey: .status)
        self.scheduledDate = try container.decode(Date.self, forKey: .scheduledDate)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.sourceTaskID = try container.decodeIfPresent(UUID.self, forKey: .sourceTaskID)
        self.deferredToTaskID = try container.decodeIfPresent(UUID.self, forKey: .deferredToTaskID)
        self.deferredAt = try container.decodeIfPresent(Date.self, forKey: .deferredAt)
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}
