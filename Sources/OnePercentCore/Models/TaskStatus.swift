import Foundation

/// The four statuses a goal can have
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case inProgress
    case done
    case deferred

    public var displayName: String {
        switch self {
        case .todo: return L("To do")
        case .inProgress: return L("In progress")
        case .done: return L("Done")
        case .deferred: return L("Tomorrow")
        }
    }

    public var iconName: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        case .deferred: return "calendar.badge.clock"
        }
    }
}
