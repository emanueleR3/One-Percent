import AppKit
import CoreGraphics

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
    let hasPhysicalNotch: Bool
}

/// Resolves all screen coordinates at runtime. No pixel dimensions of a particular MacBook
/// are assumed; the two public auxiliary areas identify the gap created by a display cutout.
struct NotchPositionResolver {
    static let preferredPanelSize = NSSize(width: 400, height: 174)
    static let activationHorizontalPadding: CGFloat = 16
    static let defaultHeadroom: CGFloat = 24

    @MainActor
    func resolve(
        panelHeight: CGFloat = preferredPanelSize.height,
        panelWidth: CGFloat = preferredPanelSize.width,
        overshootHeadroom: CGFloat = defaultHeadroom
    ) -> NotchGeometry? {
        guard let screen = targetScreen(from: NSScreen.screens) else {
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
            overshootHeadroom: overshootHeadroom
        )
    }

    static func geometry(
        for metrics: NotchScreenMetrics,
        preferredSize: NSSize = preferredPanelSize,
        overshootHeadroom: CGFloat = 0
    ) -> NotchGeometry {
        let frame = metrics.frame
        let leftArea = metrics.auxiliaryTopLeftArea
        let rightArea = metrics.auxiliaryTopRightArea
        let hasPhysicalNotch = !leftArea.isEmpty
            && !rightArea.isEmpty
            && leftArea.maxX < rightArea.minX

        let notchBounds: NSRect
        if hasPhysicalNotch {
            notchBounds = NSRect(
                x: leftArea.maxX,
                y: frame.maxY - metrics.safeAreaInsets.top,
                width: rightArea.minX - leftArea.maxX,
                height: metrics.safeAreaInsets.top
            )
        } else {
            let fallbackWidth = min(180, frame.width)
            notchBounds = NSRect(
                x: frame.midX - (fallbackWidth / 2),
                y: metrics.visibleFrame.maxY,
                width: fallbackWidth,
                height: max(24, frame.maxY - metrics.visibleFrame.maxY)
            )
        }

        let topAnchor = min(frame.maxY - metrics.safeAreaInsets.top, metrics.visibleFrame.maxY)
        let horizontalInset = min(12, frame.width / 2)
        let maximumWidth = max(1, frame.width - horizontalInset * 2)

        let cardWidth = min(preferredSize.width, maximumWidth)
        let totalWindowWidth = min(cardWidth + overshootHeadroom * 2, frame.width)

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
        let activationRect = NSRect(
            x: max(frame.minX, notchBounds.minX - activationHorizontalPadding),
            y: max(frame.minY, frame.maxY - activationHeight),
            width: min(frame.width, notchBounds.width + activationHorizontalPadding * 2),
            height: activationHeight + 20
        )

        return NotchGeometry(
            expandedFrame: expandedFrame,
            activationRect: activationRect,
            hasPhysicalNotch: hasPhysicalNotch
        )
    }

    @MainActor
    private func targetScreen(from screens: [NSScreen]) -> NSScreen? {
        let builtIn = screens.first(where: Self.isBuiltIn)
        return builtIn ?? NSScreen.main ?? screens.first
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
