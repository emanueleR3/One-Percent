import AppKit
import OnePercentCore

/// Defaults and limits for the virtual notch: a black notch drawn over the real one. It is wider
/// than the hardware notch, so the real notch hides the middle and the two sides stick out as
/// matching "ears" that carry the information. Nothing is guessed about a particular MacBook; the
/// real notch size comes from the display and the user can adjust the rest.
enum VirtualNotchSizing {
    /// How far each side sticks out past the real notch when the size is automatic.
    static let defaultEarWidth: CGFloat = 46
    static let minimumEarWidth: CGFloat = 28
    static let maximumEarWidth: CGFloat = 120
    /// Empty space between the two sides on a display without a notch.
    static let standInGap: CGFloat = 16
    /// The black shape reaches this far above the screen so no sliver of menu bar shows over it.
    static let topBleed: CGFloat = 3

    /// Width the real notch (or the stand-in gap) takes in the middle.
    static func centerGap(for geometry: NotchGeometry) -> CGFloat {
        geometry.hasPhysicalNotch ? geometry.notchBounds.width : standInGap
    }

    static func automaticWidth(for geometry: NotchGeometry) -> CGFloat {
        centerGap(for: geometry) + 2 * defaultEarWidth
    }

    /// The same height as the real notch, so the bottom edges line up exactly.
    static func automaticHeight(for geometry: NotchGeometry) -> CGFloat {
        geometry.notchBounds.height
    }

    static func widthRange(for geometry: NotchGeometry) -> ClosedRange<CGFloat> {
        let gap = centerGap(for: geometry)
        return (gap + 2 * minimumEarWidth)...(gap + 2 * maximumEarWidth)
    }

    static func heightRange(for geometry: NotchGeometry) -> ClosedRange<CGFloat> {
        let natural = automaticHeight(for: geometry)
        return max(20, natural - 8)...(natural + 16)
    }
}

/// Where the virtual notch goes and how it divides into two sides and a middle.
struct VirtualNotchLayout: Equatable {
    /// The window: the visible notch plus `topBleed` above the screen edge.
    let frame: NSRect
    /// The visible notch alone, flush with the top of the screen. Pointing at it opens the panel.
    let visibleRect: NSRect
    /// Width of each side outside the middle.
    let earWidth: CGFloat
    /// The middle, which the real notch covers.
    let centerGap: CGFloat

    var bleed: CGFloat { frame.height - visibleRect.height }

    /// `width` and `height` are the stored preferences: 0 means automatic. Sizes are kept inside the
    /// range that still reads as a notch, and the notch is centred on the real one.
    static func make(
        for geometry: NotchGeometry,
        width: Double,
        height: Double,
        backingScale: CGFloat = 2
    ) -> VirtualNotchLayout {
        let screen = geometry.screenFrame
        let gap = VirtualNotchSizing.centerGap(for: geometry)

        let widthRange = VirtualNotchSizing.widthRange(for: geometry)
        let heightRange = VirtualNotchSizing.heightRange(for: geometry)
        let wanted = width > 0 ? CGFloat(width) : VirtualNotchSizing.automaticWidth(for: geometry)
        let tall = height > 0 ? CGFloat(height) : VirtualNotchSizing.automaticHeight(for: geometry)

        let snap = { (value: CGFloat) in (value * backingScale).rounded() / backingScale }
        let notchWidth = snap(min(max(wanted, widthRange.lowerBound), min(widthRange.upperBound, screen.width)))
        let notchHeight = snap(min(max(tall, heightRange.lowerBound), heightRange.upperBound))

        let x = min(max(snap(geometry.notchBounds.midX - notchWidth / 2), screen.minX), screen.maxX - notchWidth)
        let top = screen.maxY
        let visible = NSRect(x: x, y: top - notchHeight, width: notchWidth, height: notchHeight)
        let bleed = VirtualNotchSizing.topBleed
        let frame = NSRect(x: x, y: visible.minY, width: notchWidth, height: notchHeight + bleed)

        return VirtualNotchLayout(
            frame: frame,
            visibleRect: visible,
            earWidth: max(0, (notchWidth - gap) / 2),
            centerGap: gap
        )
    }
}
