import Foundation

/// Centralized spacing and metric definitions per ONE_PERCENT_SPEC.md (Section 10.6)
enum IslandMetrics {
    static let micro: CGFloat = 4
    static let compact: CGFloat = 8
    static let standard: CGFloat = 12
    static let groupSeparation: CGFloat = 16
    static let mainPadding: CGFloat = 16
    static let wideSeparation: CGFloat = 24

    static let cornerRadius: CGFloat = 24
    static let rowCornerRadius: CGFloat = 10
    static let badgeCornerRadius: CGFloat = 6
    static let controlCornerRadius: CGFloat = 8

    /// Minimum height of a single goal row. Drag-to-reorder math is derived from this value.
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 2
    static let progressBarHeight: CGFloat = 4

    static let minPanelHeight: CGFloat = 160
    static let maxPanelHeight: CGFloat = 420
    static let panelWidth: CGFloat = 440
    static let standardPanelHeight: CGFloat = 264
}
