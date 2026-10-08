import SwiftUI

/// Centralized typography definitions per ONE_PERCENT_SPEC.md (Section 10.5)
enum IslandTypography {
    static let appWordmark = Font.system(size: 13.5, weight: .medium)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let taskTitle = Font.system(size: 13.5, weight: .regular)
    static let statusLabel = Font.system(size: 11, weight: .medium)
    static let secondaryMetadata = Font.system(size: 11, weight: .regular)
    static let progressIndicator = Font.system(size: 11.5, weight: .medium)
    static let caption = Font.system(size: 10, weight: .regular)
}
