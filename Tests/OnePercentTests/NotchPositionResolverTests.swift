import AppKit
import XCTest
@testable import OnePercent

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
        XCTAssertEqual(geometry.expandedFrame.width, 400, accuracy: 0.001)
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
