import XCTest
import SwiftUI
import AppKit
@testable import OnePercent
@testable import OnePercentCore
import OnePercentTestSupport

/// A click already buzzes the trackpad (press and release), so controls must not add their own.
@MainActor
final class HapticsTests: XCTestCase {
    private var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []

    override func setUp() async throws {
        patterns = []
        IslandHaptics.performer = { [weak self] in self?.patterns.append($0) }
    }

    override func tearDown() async throws {
        IslandHaptics.performer = { NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: .now) }
    }

    private struct ChipsHarness: View {
        @State var selection = 0
        var body: some View {
            OptionChips(options: [.init(label: "Overview", value: 0), .init(label: "Focus", value: 1)], selection: $selection)
                .padding(8).background(Color.black)
        }
    }

    private struct SwitchHarness: View {
        @State var isOn = false
        var body: some View { IslandSwitch(isOn: $isOn).padding(8).background(Color.black) }
    }

    /// Presses and releases the mouse on a view and reports whether its binding changed.
    private func click<V: View>(_ view: V, at fraction: CGPoint) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: 50, y: 200))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        let point = NSPoint(x: size.width * fraction.x, y: size.height * fraction.y)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
        }
        window.sendEvent(event(.leftMouseDown))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.sendEvent(event(.leftMouseUp))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        window.orderOut(nil)
    }

    func testClickingAChipAddsNoHapticOfItsOwn() {
        click(ChipsHarness(), at: CGPoint(x: 0.8, y: 0.5))
        XCTAssertEqual(patterns.count, 0)
    }

    func testClickingASwitchAddsNoHapticOfItsOwn() {
        click(SwitchHarness(), at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(patterns.count, 0)
    }

    func testSuccessStillMarksTheBigMoments() {
        IslandHaptics.success()
        XCTAssertEqual(patterns, [.levelChange])
    }
}
