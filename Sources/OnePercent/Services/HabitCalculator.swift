import Foundation

struct HabitStats: Equatable, Sendable {
    var currentStreak: Int
    var bestStreak: Int
    /// Share of scheduled days done in the last 30 days; nil until something was due.
    var rate30: Double?
    var completedCount: Int

    static let empty = HabitStats(currentStreak: 0, bestStreak: 0, rate30: nil, completedCount: 0)
}

/// Streaks for recurring goals. Only scheduled days count: a weekday habit is not broken by the
/// weekend, a weekly one is measured week to week. Days the user deleted on purpose are skipped,
/// and a day whose occurrence was moved (`.deferred`) is left out until the move resolves.
enum HabitCalculator {
    static func stats(
        for habit: Habit,
        occurrences: [Date: TaskStatus],
        today rawToday: Date,
        calendar: Calendar
    ) -> HabitStats {
        let today = calendar.startOfDay(for: rawToday)
        let start = calendar.startOfDay(for: habit.startDate)
        guard start <= today else { return .empty }

        let skipped = Set(habit.skippedDays.map { calendar.startOfDay(for: $0) })

        var days: [Date] = []
        var cursor = start
        while cursor <= today {
            if habit.schedule.isScheduled(on: cursor, calendar: calendar), !skipped.contains(cursor) {
                days.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // A day moved elsewhere and not resolved yet is neither done nor missed: leave it out.
        days.removeAll { occurrences[$0] == .deferred }

        func isDone(_ day: Date) -> Bool { occurrences[day] == .done }

        // Best run, oldest to newest.
        var best = 0
        var run = 0
        for day in days {
            if isDone(day) {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }

        // Current run: today still pending is "not yet", not "missed".
        var current = 0
        var index = days.count - 1
        if index >= 0, days[index] == today, !isDone(today) {
            index -= 1
        }
        while index >= 0, isDone(days[index]) {
            current += 1
            index -= 1
        }

        // 30-day completion rate, leaving out a still-pending today.
        let windowStart = calendar.date(byAdding: .day, value: -29, to: today) ?? start
        let due = days.filter { $0 >= windowStart && ($0 != today || isDone($0)) }
        let rate: Double? = due.isEmpty ? nil : Double(due.filter(isDone).count) / Double(due.count)

        return HabitStats(
            currentStreak: current,
            bestStreak: max(best, current),
            rate30: rate,
            completedCount: days.filter(isDone).count
        )
    }
}
