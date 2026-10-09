import AppKit
import CoreGraphics
import OnePercentCore

struct NotchScreenMetrics {
    let frame: NSRect
    let visibleFrame: NSRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopLeftArea: NSRect
    let auxiliaryTopRightArea: NSRect
}

struct NotchGeometry: Equatable {
    let expandedFrame: NSRect
    let activationRect: NSRect
    /// The notch itself, or the stand-in strip where a display has none.
    let notchBounds: NSRect
    let hasPhysicalNotch: Bool
    /// The whole display, so overlays can sit on its very top edge.
    let screenFrame: NSRect
}

/// Where the panel hangs on a display without a notch.
enum PanelAnchor: String, CaseIterable, Sendable {
    case center
    case leading
    case trailing
}

/// Resolves all screen coordinates at runtime. No pixel dimensions of a particular MacBook
/// are assumed; the two public auxiliary areas identify the gap created by a display cutout.
struct NotchPositionResolver {
    static let preferredPanelSize = NSSize(width: IslandMetrics.panelWidth, height: IslandMetrics.standardPanelHeight)
    static let activationHorizontalPadding: CGFloat = 4
    static let defaultHeadroom: CGFloat = 24

    @MainActor
    func resolve(
        panelHeight: CGFloat = preferredPanelSize.height,
        panelWidth: CGFloat = preferredPanelSize.width,
        overshootHeadroom: CGFloat = defaultHeadroom,
        selection: ScreenSelection = .automatic,
        anchor: PanelAnchor = .center
    ) -> NotchGeometry? {
        guard let screen = targetScreen(from: NSScreen.screens, selection: selection) else {
            return nil
        }

        let metrics = NotchScreenMetrics(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea ?? .zero
        )
        return Self.geometry(
            for: metrics,
            preferredSize: NSSize(width: panelWidth, height: panelHeight),
            anchor: anchor,
            overshootHeadroom: overshootHeadroom
        )
    }

    static func geometry(
        for metrics: NotchScreenMetrics,
        preferredSize: NSSize = preferredPanelSize,
        anchor: PanelAnchor = .center,
        overshootHeadroom: CGFloat = 0
    ) -> NotchGeometry {
        let frame = metrics.frame
        let leftArea = metrics.auxiliaryTopLeftArea
        let rightArea = metrics.auxiliaryTopRightArea
        let hasPhysicalNotch = !leftArea.isEmpty
            && !rightArea.isEmpty
            && leftArea.maxX < rightArea.minX

        let topAnchor = min(frame.maxY - metrics.safeAreaInsets.top, metrics.visibleFrame.maxY)
        let horizontalInset = min(12, frame.width / 2)
        let maximumWidth = max(1, frame.width - horizontalInset * 2)

        let cardWidth = min(preferredSize.width, maximumWidth)
        let totalWindowWidth = min(cardWidth + overshootHeadroom * 2, frame.width)

        // A real notch fixes the horizontal position. Without one, the panel can hang from the
        // centre or from either corner, and the stand-in notch strip follows it.
        let notchBounds: NSRect
        if hasPhysicalNotch {
            notchBounds = NSRect(
                x: leftArea.maxX,
                y: frame.maxY - metrics.safeAreaInsets.top,
                width: rightArea.minX - leftArea.maxX,
                height: metrics.safeAreaInsets.top
            )
        } else {
            let fallbackWidth = min(160, frame.width)
            let anchoredMidX: CGFloat
            switch anchor {
            case .center: anchoredMidX = frame.midX
            case .leading: anchoredMidX = frame.minX + totalWindowWidth / 2
            case .trailing: anchoredMidX = frame.maxX - totalWindowWidth / 2
            }
            notchBounds = NSRect(
                x: anchoredMidX - (fallbackWidth / 2),
                y: metrics.visibleFrame.maxY,
                width: fallbackWidth,
                height: max(24, frame.maxY - metrics.visibleFrame.maxY)
            )
        }

        let maximumHeight = max(1, topAnchor - frame.minY - 12)
        let cardHeight = min(preferredSize.height, maximumHeight)
        let totalWindowHeight = min(cardHeight + overshootHeadroom, topAnchor - frame.minY)

        let minimumPanelX = frame.minX
        let maximumPanelX = max(minimumPanelX, frame.maxX - totalWindowWidth)
        let panelX = min(max(notchBounds.midX - totalWindowWidth / 2, minimumPanelX), maximumPanelX)
        let expandedFrame = NSRect(
            x: panelX,
            y: topAnchor - totalWindowHeight,
            width: totalWindowWidth,
            height: totalWindowHeight
        )

        let activationHeight = max(24, notchBounds.height, frame.maxY - metrics.visibleFrame.maxY)
        let activationWidth = max(50, min(frame.width, notchBounds.width + activationHorizontalPadding * 2))
        let activationRect = NSRect(
            x: max(frame.minX, notchBounds.midX - activationWidth / 2),
            y: max(frame.minY, frame.maxY - activationHeight),
            width: activationWidth,
            height: activationHeight + 20
        )

        return NotchGeometry(
            expandedFrame: expandedFrame,
            activationRect: activationRect,
            notchBounds: notchBounds,
            hasPhysicalNotch: hasPhysicalNotch,
            screenFrame: frame
        )
    }

    @MainActor
    private func targetScreen(from screens: [NSScreen], selection: ScreenSelection) -> NSScreen? {
        let descriptors = screens.map { screen in
            ScreenDescriptor(
                id: screen.stableDisplayID ?? "\(screen.frame)",
                isBuiltIn: Self.isBuiltIn(screen),
                isMenuBarScreen: screen == screens.first
            )
        }
        guard let chosen = ScreenChooser.choose(from: descriptors, selection: selection),
              let index = descriptors.firstIndex(where: { $0.id == chosen }) else {
            return nil
        }
        return screens[index]
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
