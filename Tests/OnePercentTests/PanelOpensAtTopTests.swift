import XCTest
import SwiftUI
import AppKit
@testable import OnePercent

/// The real panel, on the real display, with a list long enough to scroll: after every opening the
/// first goal must be fully visible (offset exactly 0), however the opening animation rounded things.
@MainActor
final class PanelOpensAtTopTests: XCTestCase {
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView { found.append(scroll) }
        for sub in view.subviews { found += scrollViews(in: sub) }
        return found
    }

    private func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            CATransaction.flush()
        }
    }

    func testEveryOpeningStartsExactlyAtTheTop() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("needs a display") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let defaults = UserDefaults(suiteName: "OnePercentTests.panelTop")!
        defaults.removePersistentDomain(forName: "OnePercentTests.panelTop")
        defer { defaults.removePersistentDomain(forName: "OnePercentTests.panelTop") }
        let preferences = AppPreferences(defaults: defaults)
        let store = TaskStore(persistence: MockTaskPersistence(), dateService: DateService(), habitPersistence: InMemoryHabitPersistence())
        var ids: [UUID] = []
        for (index, title) in ["33% del piano", "Scrivere al team", "Leggere", "Palestra", "Configurare app", "Ordine A", "Ordine B", "Ordine C"].enumerated() {
            if let task = store.addTask(title: title, tags: index < 2 ? ["lavoro", "brain"] : []) { ids.append(task.id) }
        }
        store.setTheOne(id: ids[0])
        store.addSubtask(to: ids[0], title: "Uno")
        store.updateTaskStatus(id: ids[0], newStatus: .inProgress)
        store.updateTaskStatus(id: ids[1], newStatus: .inProgress)

        let focus = FocusController(store: store, preferences: preferences, scheduler: nil, autoTick: false)
        let services = IslandServices(
            preferences: preferences, reminders: nil, launchAtLogin: LaunchAtLoginController(),
            smartAdd: SmartAddService(), focus: focus
        )
        let controller = NotchWindowController(taskStore: store, services: services)
        controller.start()
        defer { controller.stop() }

        for round in 1...3 {
            controller.showPanel()
            pump(1.4)
            let panel = try XCTUnwrap(NSApp.windows.first { $0 is NSPanel && $0.level == .statusBar && $0.frame.height > 200 })
            let scroll = try XCTUnwrap(scrollViews(in: try XCTUnwrap(panel.contentView)).first)
            XCTAssertGreaterThan(scroll.documentView?.frame.height ?? 0, scroll.contentView.bounds.height, "the list should overflow")
            XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.001, "opening #\(round): first goal fully visible")
            XCTAssertEqual(scroll.contentView.bounds.origin.x, 0, accuracy: 0.001)

            // Scroll down like a user would, then close: the next opening starts at the top again.
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
            scroll.reflectScrolledClipView(scroll.contentView)
            controller.hidePanel()
            pump(0.8)
        }
    }
}
