import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Handles local calendar date logic, midnight transitions, and date navigation (Section 3.1, 6.3, 12)
@MainActor
public final class DateService: ObservableObject {
    @Published public private(set) var today: Date
    private var calendar: Calendar
    private var observerTokens: [NSObjectProtocol] = []

    public var onDayChanged: ((Date) -> Void)?

    /// Weekday and month names follow the language chosen in Settings, not the macOS one.
    public func setLocale(_ locale: Locale) {
        calendar.locale = locale
    }

    /// Calendar used for every day computation, exposed for aggregations such as `TrackingCalculator`.
    public var currentCalendar: Calendar { calendar }

    public init(calendar: Calendar = .autoupdatingCurrent) {
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
            forName: Self.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshToday()
            }
        }
        self.observerTokens = [dayChangeToken, activeToken]
    }

    /// Coming back to the app is when a day change that happened while it slept gets noticed.
    private static var didBecomeActiveNotification: Notification.Name {
        #if canImport(AppKit)
        return NSApplication.didBecomeActiveNotification
        #else
        return UIApplication.didBecomeActiveNotification
        #endif
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    public func refreshToday() {
        let newToday = calendar.startOfDay(for: Date())
        if newToday != today {
            today = newToday
            onDayChanged?(newToday)
        }
    }

    /// `yyyy-MM-dd` in the local calendar. Stable key for "once per day" state.
    public func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func normalize(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func nextDay(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: normalize(date)) ?? normalize(date)
    }

    public func previousDay(before date: Date) -> Date {
        calendar.date(byAdding: .day, value: -1, to: normalize(date)) ?? normalize(date)
    }

    public func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    public func isTomorrow(_ date: Date) -> Bool {
        calendar.isDateInTomorrow(date)
    }

    public func daysFromToday(to date: Date) -> Int {
        let startToday = normalize(today)
        let target = normalize(date)
        return calendar.dateComponents([.day], from: startToday, to: target).day ?? 0
    }

    public func canNavigatePrevious(from date: Date) -> Bool {
        daysFromToday(to: date) > -7
    }

    public func canNavigateNext(from date: Date) -> Bool {
        daysFromToday(to: date) < 7
    }

    public func formatDayTitle(for date: Date) -> String {
        let normalized = normalize(date)
        if isToday(normalized) {
            return L("Today, %@", LocalizedDates.string(normalized, template: "MMMd", calendar: calendar))
        } else if isTomorrow(normalized) {
            return L("Tomorrow, %@", LocalizedDates.string(normalized, template: "MMMd", calendar: calendar))
        } else {
            return LocalizedDates.string(normalized, template: "EEEMMMd", calendar: calendar)
        }
    }

    public func formatProgressHeader(for date: Date) -> String {
        let normalized = normalize(date)
        if isToday(normalized) {
            return L("TODAY'S GOALS")
        } else if isTomorrow(normalized) {
            return L("TOMORROW'S GOALS")
        } else {
            return L("%@'S GOALS", LocalizedDates.string(normalized, template: "EEEMMMd", calendar: calendar).uppercased())
        }
    }
}
