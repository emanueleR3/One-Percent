import AppKit
import XCTest
@testable import OnePercent
@testable import OnePercentCore
import OnePercentTestSupport

final class NotchPositionResolverTests: XCTestCase {
    func testNotchedDisplayUsesTheGapBetweenAuxiliaryAreas() {
        let metrics = NotchScreenMetrics(
            frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 945),
            safeAreaInsets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: NSRect(x: 0, y: 945, width: 620, height: 37),
            auxiliaryTopRightArea: NSRect(x: 892, y: 945, width: 620, height: 37)
        )

        let geometry = NotchPositionResolver.geometry(for: metrics)

        XCTAssertTrue(geometry.hasPhysicalNotch)
        XCTAssertEqual(geometry.activationRect.midX, 756, accuracy: 0.001)
        XCTAssertEqual(geometry.activationRect.minY, 945, accuracy: 0.001)
        XCTAssertEqual(geometry.expandedFrame.maxY, 945, accuracy: 0.001)
        XCTAssertEqual(geometry.expandedFrame.width, IslandMetrics.panelWidth, accuracy: 0.001)
    }

    func testExternalDisplayFallsBackBelowTheMenuBar() {
        let metrics = NotchScreenMetrics(
            frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1056),
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero
        )

        let geometry = NotchPositionResolver.geometry(for: metrics)

        XCTAssertFalse(geometry.hasPhysicalNotch)
        XCTAssertEqual(geometry.activationRect.midX, 960, accuracy: 0.001)
        XCTAssertEqual(geometry.activationRect.minY, 1056, accuracy: 0.001)
        XCTAssertEqual(geometry.expandedFrame.maxY, 1056, accuracy: 0.001)
    }

    func testPanelIsClampedInsideASmallDisplay() {
        let metrics = NotchScreenMetrics(
            frame: NSRect(x: 0, y: 0, width: 280, height: 200),
            visibleFrame: NSRect(x: 0, y: 0, width: 280, height: 176),
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero
        )

        let geometry = NotchPositionResolver.geometry(for: metrics)

        XCTAssertGreaterThanOrEqual(geometry.expandedFrame.minX, 0)
        XCTAssertLessThanOrEqual(geometry.expandedFrame.maxX, 280)
        XCTAssertGreaterThanOrEqual(geometry.expandedFrame.minY, 0)
    }
}

// MARK: - Panel position, screen choice, indicator placement

final class NotchPlacementTests: XCTestCase {
    private let externalDisplay = NotchScreenMetrics(
        frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1056),
        safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: .zero,
        auxiliaryTopRightArea: .zero
    )

    private let notchedDisplay = NotchScreenMetrics(
        frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 945),
        safeAreaInsets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: NSRect(x: 0, y: 945, width: 620, height: 37),
        auxiliaryTopRightArea: NSRect(x: 892, y: 945, width: 620, height: 37)
    )

    // MARK: Panel anchor

    func testExternalDisplayCanAnchorTheLeftEdge() {
        let geometry = NotchPositionResolver.geometry(for: externalDisplay, anchor: .leading, overshootHeadroom: 24)
        XCTAssertEqual(geometry.expandedFrame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.activationRect.midX, geometry.expandedFrame.midX, accuracy: 0.001,
                       "the hot zone follows the panel")
        XCTAssertLessThan(geometry.activationRect.midX, 960)
    }

    func testExternalDisplayCanAnchorTheRightEdge() {
        let geometry = NotchPositionResolver.geometry(for: externalDisplay, anchor: .trailing, overshootHeadroom: 24)
        XCTAssertEqual(geometry.expandedFrame.maxX, 1920, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.activationRect.midX, 960)
    }

    func testCenterIsTheDefault() {
        let geometry = NotchPositionResolver.geometry(for: externalDisplay, anchor: .center)
        XCTAssertEqual(geometry.expandedFrame.midX, 960, accuracy: 0.001)
        XCTAssertEqual(NotchPositionResolver.geometry(for: externalDisplay), geometry)
    }

    func testAPhysicalNotchAlwaysWinsOverTheAnchor() {
        let centered = NotchPositionResolver.geometry(for: notchedDisplay, anchor: .center)
        XCTAssertEqual(NotchPositionResolver.geometry(for: notchedDisplay, anchor: .leading), centered)
        XCTAssertEqual(NotchPositionResolver.geometry(for: notchedDisplay, anchor: .trailing), centered)
    }

    func testGeometryExposesTheNotchRect() {
        let geometry = NotchPositionResolver.geometry(for: notchedDisplay)
        XCTAssertEqual(geometry.notchBounds.minX, 620, accuracy: 0.001)
        XCTAssertEqual(geometry.notchBounds.maxX, 892, accuracy: 0.001)
        XCTAssertEqual(geometry.notchBounds.minY, 945, accuracy: 0.001)
        XCTAssertEqual(geometry.notchBounds.height, 37, accuracy: 0.001)
    }

    // MARK: Screen choice

    private let screens = [
        ScreenDescriptor(id: "builtin", isBuiltIn: true, isMenuBarScreen: false),
        ScreenDescriptor(id: "external", isBuiltIn: false, isMenuBarScreen: true)
    ]

    func testAutomaticPrefersTheBuiltInDisplay() {
        XCTAssertEqual(ScreenChooser.choose(from: screens, selection: .automatic), "builtin")
    }

    func testAutomaticFallsBackToTheMenuBarScreenWithoutABuiltInOne() {
        let desk = [
            ScreenDescriptor(id: "a", isBuiltIn: false, isMenuBarScreen: false),
            ScreenDescriptor(id: "b", isBuiltIn: false, isMenuBarScreen: true)
        ]
        XCTAssertEqual(ScreenChooser.choose(from: desk, selection: .automatic), "b")
    }

    func testMainMeansTheScreenWithTheMenuBar() {
        XCTAssertEqual(ScreenChooser.choose(from: screens, selection: .main), "external")
    }

    func testAPickedDisplayIsUsedAndAnUnplugOneFallsBackToAutomatic() {
        XCTAssertEqual(ScreenChooser.choose(from: screens, selection: .display("external")), "external")
        XCTAssertEqual(ScreenChooser.choose(from: screens, selection: .display("gone")), "builtin")
    }

    func testNoScreensMeansNoChoice() {
        XCTAssertNil(ScreenChooser.choose(from: [], selection: .automatic))
    }

    func testSelectionRoundTripsThroughItsStoredString() {
        XCTAssertEqual(ScreenSelection(stored: "automatic"), .automatic)
        XCTAssertEqual(ScreenSelection(stored: "main"), .main)
        XCTAssertEqual(ScreenSelection(stored: "ABC-123"), .display("ABC-123"))
        XCTAssertEqual(ScreenSelection(stored: ""), .automatic)
        XCTAssertEqual(ScreenSelection.display("ABC-123").stored, "ABC-123")
        XCTAssertEqual(ScreenSelection.automatic.stored, "automatic")
    }

    // MARK: Virtual notch

    func testVirtualNotchIsCenteredOnTheRealNotchAndFlushWithTheScreenTop() {
        let geometry = NotchPositionResolver.geometry(for: notchedDisplay)
        let layout = VirtualNotchLayout.make(for: geometry, width: 0, height: 0)

        XCTAssertEqual(layout.visibleRect.midX, geometry.notchBounds.midX, accuracy: 0.26)
        XCTAssertEqual(layout.visibleRect.maxY, geometry.screenFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.visibleRect.height, geometry.notchBounds.height, accuracy: 0.001)
    }

    func testAutomaticWidthLeavesEqualSidesAroundTheRealNotch() {
        let geometry = NotchPositionResolver.geometry(for: notchedDisplay)
        let layout = VirtualNotchLayout.make(for: geometry, width: 0, height: 0)

        let leftSide = geometry.notchBounds.minX - layout.visibleRect.minX
        let rightSide = layout.visibleRect.maxX - geometry.notchBounds.maxX
        XCTAssertEqual(leftSide, rightSide, accuracy: 0.51)
        XCTAssertEqual(leftSide, layout.earWidth, accuracy: 0.51)
        XCTAssertEqual(layout.centerGap, geometry.notchBounds.width, accuracy: 0.001)
        XCTAssertGreaterThan(layout.earWidth, VirtualNotchSizing.minimumEarWidth)
    }

    func testTheNotchBleedsAboveTheScreenSoNoHairlineShows() {
        let geometry = NotchPositionResolver.geometry(for: notchedDisplay)
        let layout = VirtualNotchLayout.make(for: geometry, width: 0, height: 0)

        XCTAssertEqual(layout.frame.maxY, geometry.screenFrame.maxY + VirtualNotchSizing.topBleed, accuracy: 0.001)
        XCTAssertEqual(layout.frame.minY, layout.visibleRect.minY, accuracy: 0.001)
        XCTAssertEqual(layout.bleed, VirtualNotchSizing.topBleed, accuracy: 0.001)
    }

    func testCustomSizeIsUsedAndStillCentered() {
        let geometry = NotchPositionResolver.geometry(for: notchedDisplay)
        let layout = VirtualNotchLayout.make(for: geometry, width: 380, height: 40)

        XCTAssertEqual(layout.visibleRect.width, 380, accuracy: 0.51)
        XCTAssertEqual(layout.visibleRect.height, 40, accuracy: 0.51)
        XCTAssertEqual(layout.visibleRect.midX, geometry.notchBounds.midX, accuracy: 0.51)
    }

    func testSizesAreKeptInsideTheUsableRange() {
        let geometry = NotchPositionResolver.geometry(for: notchedDisplay)
        let widthRange = VirtualNotchSizing.widthRange(for: geometry)
        let heightRange = VirtualNotchSizing.heightRange(for: geometry)

        let tiny = VirtualNotchLayout.make(for: geometry, width: 10, height: 2)
        XCTAssertEqual(tiny.visibleRect.width, widthRange.lowerBound, accuracy: 0.51)
        XCTAssertEqual(tiny.visibleRect.height, heightRange.lowerBound, accuracy: 0.51)
        XCTAssertGreaterThanOrEqual(tiny.earWidth, VirtualNotchSizing.minimumEarWidth - 0.51)

        let huge = VirtualNotchLayout.make(for: geometry, width: 5000, height: 500)
        XCTAssertEqual(huge.visibleRect.width, widthRange.upperBound, accuracy: 0.51)
        XCTAssertEqual(huge.visibleRect.height, heightRange.upperBound, accuracy: 0.51)
        XCTAssertLessThanOrEqual(huge.visibleRect.maxX, geometry.screenFrame.maxX)
        XCTAssertGreaterThanOrEqual(huge.visibleRect.minX, geometry.screenFrame.minX)
    }

    func testWithoutARealNotchItIsACenteredStandIn() {
        let geometry = NotchPositionResolver.geometry(for: externalDisplay)
        let layout = VirtualNotchLayout.make(for: geometry, width: 0, height: 0)

        XCTAssertEqual(layout.visibleRect.midX, geometry.notchBounds.midX, accuracy: 0.51)
        XCTAssertEqual(layout.visibleRect.maxY, geometry.screenFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.centerGap, VirtualNotchSizing.standInGap, accuracy: 0.001)
        XCTAssertEqual(layout.earWidth, VirtualNotchSizing.defaultEarWidth, accuracy: 0.51)
    }

    func testTheNotchNeverLeavesTheScreen() {
        // A panel anchored to the left of an external display puts the stand-in near the edge.
        let geometry = NotchPositionResolver.geometry(for: externalDisplay, anchor: .leading)
        let layout = VirtualNotchLayout.make(for: geometry, width: 400, height: 0)

        XCTAssertGreaterThanOrEqual(layout.visibleRect.minX, geometry.screenFrame.minX)
        XCTAssertLessThanOrEqual(layout.visibleRect.maxX, geometry.screenFrame.maxX)
    }

    func testDimensionsSnapToWholeDevicePixels() {
        let geometry = NotchPositionResolver.geometry(for: notchedDisplay)
        let layout = VirtualNotchLayout.make(for: geometry, width: 301.3, height: 33.4, backingScale: 2)

        XCTAssertEqual(layout.visibleRect.width * 2, (layout.visibleRect.width * 2).rounded(), accuracy: 0.0001)
        XCTAssertEqual(layout.visibleRect.minX * 2, (layout.visibleRect.minX * 2).rounded(), accuracy: 0.0001)
        XCTAssertEqual(layout.visibleRect.height * 2, (layout.visibleRect.height * 2).rounded(), accuracy: 0.0001)
    }
}
