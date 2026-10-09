import SwiftUI
import OnePercentCore

/// Centralized typography definitions per ONE_PERCENT_SPEC.md (Section 10.5)
enum IslandTypography {
    static let appWordmark = Font.system(size: 13.5, weight: .medium)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let taskTitle = Font.system(size: 13.5, weight: .regular)
    static let statusLabel = Font.system(size: 11, weight: .medium)
    static let secondaryMetadata = Font.system(size: 11, weight: .regular)
    static let progressIndicator = Font.system(size: 11.5, weight: .medium)
    static let caption = Font.system(size: 10, weight: .regular)

    /// Large rounded percentage that anchors the header.
    static let heroNumber = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let heroUnit = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let heroHeadline = Font.system(size: 12.5, weight: .medium)
    static let chip = Font.system(size: 10.5, weight: .medium)
    static let keycap = Font.system(size: 9.5, weight: .medium, design: .monospaced)

    /// Small uppercase label above a stat. Pair with `.tracking(0.6)`.
    static let eyebrow = Font.system(size: 9.5, weight: .semibold)
    static let statValue = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let statValueLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let statCaption = Font.system(size: 10, weight: .regular)
    static let weekdayLetter = Font.system(size: 9, weight: .semibold)
}
