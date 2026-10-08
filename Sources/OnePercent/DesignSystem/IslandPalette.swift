import SwiftUI

/// Centralized color palette defined in ONE_PERCENT_SPEC.md (Section 10.2)
enum IslandPalette {
    static let background = Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0)
    static let primarySurface = Color(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0)
    static let secondarySurface = Color(red: 27.0 / 255.0, green: 27.0 / 255.0, blue: 29.0 / 255.0)
    static let elevatedSurface = Color(red: 37.0 / 255.0, green: 37.0 / 255.0, blue: 39.0 / 255.0)

    static let primaryText = Color(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0)
    static let secondaryText = Color(red: 161.0 / 255.0, green: 161.0 / 255.0, blue: 166.0 / 255.0)
    static let tertiaryText = Color(red: 119.0 / 255.0, green: 119.0 / 255.0, blue: 124.0 / 255.0)

    static let border = Color(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 46.0 / 255.0)

    static let completedAccent = Color(red: 143.0 / 255.0, green: 215.0 / 255.0, blue: 164.0 / 255.0)
    static let inProgressAccent = Color(red: 231.0 / 255.0, green: 198.0 / 255.0, blue: 110.0 / 255.0)
    static let deferredAccent = Color(red: 183.0 / 255.0, green: 183.0 / 255.0, blue: 201.0 / 255.0)
    static let destructiveAccent = Color(red: 255.0 / 255.0, green: 105.0 / 255.0, blue: 97.0 / 255.0)
}
