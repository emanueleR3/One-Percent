import SwiftUI
import OnePercentCore

extension TaskStatus {
    /// Accent used for the status in the panel (the model itself carries no colors).
    var color: Color {
        switch self {
        case .todo: return IslandPalette.secondaryText
        case .inProgress: return IslandPalette.inProgressAccent
        case .done: return IslandPalette.completedAccent
        case .deferred: return IslandPalette.deferredAccent
        }
    }
}
