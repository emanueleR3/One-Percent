import SwiftUI

/// Distinct statuses defined in ONE_PERCENT_SPEC.md (Section 5.2 & 10.7)
enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case inProgress
    case done
    case deferred

    var displayName: String {
        switch self {
        case .todo: return L("To do")
        case .inProgress: return L("In progress")
        case .done: return L("Done")
        case .deferred: return L("Tomorrow")
        }
    }

    var iconName: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        case .deferred: return "calendar.badge.clock"
        }
    }

    var color: Color {
        switch self {
        case .todo: return IslandPalette.secondaryText
        case .inProgress: return IslandPalette.inProgressAccent
        case .done: return IslandPalette.completedAccent
        case .deferred: return IslandPalette.deferredAccent
        }
    }
}
