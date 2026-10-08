import Foundation
import AppKit

/// Handles local calendar date logic, midnight transitions, and date navigation (Section 3.1, 6.3, 12)
@MainActor
final class DateService: ObservableObject {
    @Published private(set) var today: Date
    private var calendar: Calendar
    private var observerTokens: [NSObjectProtocol] = []

    var onDayChanged: ((Date) -> Void)?

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: Date())

        let dayChangeToken = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshToday()
            }
        }
        let activeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshToday()
            }
        }
        self.observerTokens = [dayChangeToken, activeToken]
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func refreshToday() {
        let newToday = calendar.startOfDay(for: Date())
        if newToday != today {
            today = newToday
            onDayChanged?(newToday)
        }
    }

    func normalize(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func nextDay(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: normalize(date)) ?? normalize(date)
    }

    func previousDay(before date: Date) -> Date {
        calendar.date(byAdding: .day, value: -1, to: normalize(date)) ?? normalize(date)
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    func isTomorrow(_ date: Date) -> Bool {
        calendar.isDateInTomorrow(date)
    }

    func formatDayTitle(for date: Date) -> String {
        let normalized = normalize(date)
        if isToday(normalized) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "MMM d"
            return "Today, \(formatter.string(from: normalized))"
        } else if isTomorrow(normalized) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "MMM d"
            return "Tomorrow, \(formatter.string(from: normalized))"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: normalized)
        }
    }

    func formatProgressHeader(for date: Date) -> String {
        let normalized = normalize(date)
        if isToday(normalized) {
            return "TODAY'S GOALS"
        } else if isTomorrow(normalized) {
            return "TOMORROW'S GOALS"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "EEE, MMM d"
            return "\(formatter.string(from: normalized).uppercased())'S GOALS"
        }
    }
}
