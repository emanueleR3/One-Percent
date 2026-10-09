import XCTest
import SwiftUI
import AppKit
@testable import OnePercent

@MainActor
final class ScrollResetTests: XCTestCase {
    private struct Harness: View {
        @ObservedObject var model: Model
        final class Model: ObservableObject { @Published var token = 0 }

        var body: some View {
            FadingScrollView(resetToken: AnyHashable(model.token)) {
                VStack(spacing: 4) {
                    ForEach(0..<30, id: \.self) { index in
                        Text("Row \(index)").frame(height: 28)
                    }
                }
            }
            .frame(width: 300, height: 160)
        }
    }

    private func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(sub) { return found } }
        return nil
    }

    private func pump(_ window: NSWindow, _ rounds: Int = 12) {
        for _ in 0..<rounds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            CATransaction.flush()
            window.displayIfNeeded()
        }
    }

    func testChangingTheTokenReturnsTheListToTheTop() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = Harness.Model()
        let host = NSHostingView(rootView: Harness(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 160)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: 20, y: 120))
        window.orderFrontRegardless()
        pump(window)

        let scroll = try XCTUnwrap(findScrollView(host))
        let doc = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(doc.frame.height, 300, "the content should overflow")

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        pump(window)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 200, accuracy: 1)

        model.token += 1
        pump(window)

        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 1, "starts from the top again")
        window.orderOut(nil)
    }

    func testScrollingWithoutAChangeOfTokenIsLeftAlone() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = Harness.Model()
        let host = NSHostingView(rootView: Harness(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 160)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: 20, y: 120))
        window.orderFrontRegardless()
        pump(window)

        let scroll = try XCTUnwrap(findScrollView(host))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        scroll.reflectScrolledClipView(scroll.contentView)
        pump(window, 20)

        XCTAssertEqual(scroll.documentVisibleRect.minY, 120, accuracy: 1)
        window.orderOut(nil)
    }
}
