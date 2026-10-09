import SwiftUI
import OnePercentCore

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

    /// Warm orange reserved for streaks and the "moved again" nudge, distinct from the in-progress amber.
    static let streakAccent = Color(red: 255.0 / 255.0, green: 150.0 / 255.0, blue: 88.0 / 255.0)

    /// Cool periwinkle for "The One": nothing else in the palette is blue-violet.
    static let theOneAccent = Color(red: 150.0 / 255.0, green: 165.0 / 255.0, blue: 255.0 / 255.0)

    // MARK: - Surface tokens
    //
    // The panel melts into the physical notch, so it starts at pure black and only lifts a
    // few percent towards the bottom. Everything else is a translucent white wash on top of
    // it, which keeps hover / press states consistent without a bespoke color per surface.

    static let panelTop = Color.black
    static let panelBottom = Color(red: 12.0 / 255.0, green: 12.0 / 255.0, blue: 13.0 / 255.0)

    /// 1pt structural lines and keycap outlines.
    static let hairline = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.13)

    /// Resting / hover / pressed fills for interactive surfaces.
    static let restFill = Color.white.opacity(0.045)
    static let hoverFill = Color.white.opacity(0.07)
    static let pressedFill = Color.white.opacity(0.11)

    /// Track behind the progress bar.
    static let track = Color.white.opacity(0.08)

    /// Slightly lighter mint used for the leading highlight of the progress fill.
    static let completedHighlight = Color(red: 190.0 / 255.0, green: 240.0 / 255.0, blue: 205.0 / 255.0)
}
