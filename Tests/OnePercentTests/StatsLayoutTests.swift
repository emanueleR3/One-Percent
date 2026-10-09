import XCTest
import SwiftUI
import AppKit
@testable import OnePercent

/// Switching between "Overview" and "Focus" must not move anything: both tabs take the same height,
/// in every language, so the chips at the bottom stay under the pointer.
@MainActor
final class StatsLayoutTests: XCTestCase {
    override func tearDown() async throws {
        Localizer.shared.setLanguage(.english)
    }

    private func makeStore(withFocusTime: Bool) -> TaskStore {
        let store = TaskStore(persistence: MockTaskPersistence(), dateService: DateService(), habitPersistence: InMemoryHabitPersistence())
        for index in 0..<4 {
            guard let task = store.addTask(title: "Goal \(index)") else { continue }
            if index < 2 { store.updateTaskStatus(id: task.id, newStatus: .done) }
            if withFocusTime, index == 2 {
                let now = Date()
                XCTAssertTrue(store.startTimer(id: task.id, at: now.addingTimeInterval(-1800)))
                store.pauseTimer(id: task.id, at: now)
            }
        }
        return store
    }

    private func height(of tab: StatsView.Tab, store: TaskStore) -> CGFloat {
        let host = NSHostingView(rootView: StatsView(store: store, onSelectDay: { _ in }, initialTab: tab).frame(width: 396))
        host.frame = NSRect(x: 0, y: 0, width: 396, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    private func assertSameHeights(language: AppLanguage, withFocusTime: Bool, file: StaticString = #filePath, line: UInt = #line) {
        Localizer.shared.setLanguage(language)
        let store = makeStore(withFocusTime: withFocusTime)
        let overview = height(of: .overview, store: store)
        let focus = height(of: .focus, store: store)
        XCTAssertEqual(overview, focus, accuracy: 0.5, "\(language) tabs differ in height (focus time: \(withFocusTime))", file: file, line: line)
    }

    func testTabsHaveTheSameHeightInEnglish() {
        assertSameHeights(language: .english, withFocusTime: false)
        assertSameHeights(language: .english, withFocusTime: true)
    }

    func testTabsHaveTheSameHeightInItalian() {
        assertSameHeights(language: .italian, withFocusTime: false)
        assertSameHeights(language: .italian, withFocusTime: true)
    }

    func testTheFooterSitsAtTheSameHeightWhateverTheTab() {
        // The page is a fixed block (tiles + detail + footer), so its height is just that sum.
        Localizer.shared.setLanguage(.italian)
        let store = makeStore(withFocusTime: false)
        let expected = StatsLayout.tileRowHeight + 10 + StatsLayout.detailHeight + 10 + 24
        XCTAssertEqual(height(of: .overview, store: store), expected, accuracy: 0.5)
        XCTAssertEqual(height(of: .focus, store: store), expected, accuracy: 0.5)
    }
}
