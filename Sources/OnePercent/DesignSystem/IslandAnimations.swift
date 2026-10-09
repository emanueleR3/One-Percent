import SwiftUI
import AppKit

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

    /// Checkmark pop. Slightly under-damped so completing a goal has a little snap.
    static var checkSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.62)
    }

    /// Progress fill. Settles without wobble; the numerals do the "playful" work.
    static var progressSpring: Animation {
        .spring(response: 0.5, dampingFraction: 0.86)
    }

    /// Hover / press colour changes. Frequent, so short and ease-out.
    static var hoverFade: Animation {
        .easeOut(duration: 0.12)
    }

    static var pressFade: Animation {
        .easeOut(duration: 0.1)
    }
}

/// Trackpad haptics. No-ops on hardware without a Force Touch trackpad.
enum IslandHaptics {
    @MainActor
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    @MainActor
    static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
