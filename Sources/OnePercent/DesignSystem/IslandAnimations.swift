import SwiftUI

/// Centralized animation curves per ONE_PERCENT_SPEC.md (Section 10.8)
enum IslandAnimations {
    static let showDuration: TimeInterval = 0.20
    static let hideDuration: TimeInterval = 0.16
    static let statusDuration: TimeInterval = 0.16
    static let progressDuration: TimeInterval = 0.20

    static var defaultSpring: Animation {
        .spring(response: 0.24, dampingFraction: 0.82)
    }

    static var statusTransition: Animation {
        .easeInOut(duration: statusDuration)
    }

    static var progressTransition: Animation {
        .easeInOut(duration: progressDuration)
    }
}
