import Foundation

/// Checklist item nested inside a goal.
public struct SubTask: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// Core task occurrence entity defined in ONE_PERCENT_SPEC.md (Section 5.1)
/// Distinct occurrences possess unique identifiers; identical titles on different occurrences
/// or dates are explicitly preserved and not treated as duplicates.
public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var status: TaskStatus
    public var scheduledDate: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceTaskID: UUID?
    public var deferredToTaskID: UUID?
    public var deferredAt: Date?
    public var sortOrder: Int

    /// Lowercase tag names without the leading `#`. Colors live in `TagPalette`.
    public var tags: [String]
    public var note: String?
    public var subtasks: [SubTask]
    /// The single most important goal of its day. At most one per day (enforced by `TaskStore`).
    public var isTheOne: Bool
    /// Set on occurrences generated from a recurring `Habit`.
    public var habitID: UUID?
    /// Finished stretches of focused work on this goal.
    public var focusSessions: [FocusSession]
    /// When the running stretch began; nil when no timer is running on this goal.
    public var timerStartedAt: Date?
    public var timerIsPomodoro: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .todo,
        scheduledDate: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceTaskID: UUID? = nil,
        deferredToTaskID: UUID? = nil,
        deferredAt: Date? = nil,
        sortOrder: Int = 0,
        tags: [String] = [],
        note: String? = nil,
        subtasks: [SubTask] = [],
        isTheOne: Bool = false,
        habitID: UUID? = nil,
        focusSessions: [FocusSession] = [],
        timerStartedAt: Date? = nil,
        timerIsPomodoro: Bool = false
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
        self.tags = tags
        self.note = note
        self.subtasks = subtasks
        self.isTheOne = isTheOne
        self.habitID = habitID
        self.focusSessions = focusSessions
        self.timerStartedAt = timerStartedAt
        self.timerIsPomodoro = timerIsPomodoro
    }

    public enum CodingKeys: String, CodingKey {
        case id, title, status, scheduledDate, createdAt, updatedAt
        case sourceTaskID, deferredToTaskID, deferredAt, sortOrder
        case tags, note, subtasks, isTheOne, habitID
        case focusSessions, timerStartedAt, timerIsPomodoro
    }

    public init(from decoder: Decoder) throws {
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
        // Fields added after v0.0.2: files written by older versions simply lack them.
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
        self.subtasks = try container.decodeIfPresent([SubTask].self, forKey: .subtasks) ?? []
        self.isTheOne = try container.decodeIfPresent(Bool.self, forKey: .isTheOne) ?? false
        self.habitID = try container.decodeIfPresent(UUID.self, forKey: .habitID)
        self.focusSessions = try container.decodeIfPresent([FocusSession].self, forKey: .focusSessions) ?? []
        self.timerStartedAt = try container.decodeIfPresent(Date.self, forKey: .timerStartedAt)
        self.timerIsPomodoro = try container.decodeIfPresent(Bool.self, forKey: .timerIsPomodoro) ?? false
    }

    public var isTimerRunning: Bool { timerStartedAt != nil }

    /// Focused time on this goal, including the stretch that is still running.
    public func timeSpent(at now: Date) -> TimeInterval {
        let banked = focusSessions.reduce(0) { $0 + $1.seconds }
        let running = timerStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return banked + running
    }

    public var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }
}
