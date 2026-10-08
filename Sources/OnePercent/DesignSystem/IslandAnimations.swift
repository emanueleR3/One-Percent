import SwiftUI

/// Centralized animation curves per ONE_PERCENT_SPEC.md (Section 10.8) and bubble droplet physics
enum IslandAnimations {
    static let showDuration: TimeInterval = 0.22
    static let hideDuration: TimeInterval = 0.15
    static let statusDuration: TimeInterval = 0.16
    static let progressDuration: TimeInterval = 0.20

    static var defaultSpring: Animation {
        .spring(response: 0.24, dampingFraction: 0.82)
    }

    /// Fluid droplet expansion with bounce when emerging from the notch
    static var dropletExpandSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.60, blendDuration: 0)
    }

    /// Crisp retraction into the notch when closing
    static var dropletCollapseSpring: Animation {
        .spring(response: 0.18, dampingFraction: 0.88, blendDuration: 0)
    }

    static var statusTransition: Animation {
        .easeInOut(duration: statusDuration)
    }

    static var progressTransition: Animation {
        .easeInOut(duration: progressDuration)
    }
}
