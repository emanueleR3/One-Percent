import Foundation

/// Completion numbers for one calendar day, derived from the tasks scheduled on it.
/// Mirrors `TaskProgress` (Section 8): deferred goals never count against the day.
public struct DayStats: Equatable, Identifiable, Sendable {
    public let date: Date
    public let completed: Int
    /// Goals that count towards the day (everything except deferred).
    public let total: Int
    public let deferred: Int

    public init(date: Date, completed: Int, total: Int, deferred: Int) {
        self.date = date
        self.completed = completed
        self.total = total
        self.deferred = deferred
    }

    public var id: Date { date }
    public var ratio: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    public var hasGoals: Bool { total + deferred > 0 }
    /// At least one goal done: keeps the streak alive.
    public var isActive: Bool { completed > 0 }
    /// Every goal that counted today is done.
    public var isPerfect: Bool { total > 0 && completed == total }

    public static func empty(_ date: Date) -> DayStats {
        DayStats(date: date, completed: 0, total: 0, deferred: 0)
    }
}

public struct WeekdayPerformance: Equatable, Sendable {
    /// `Calendar` weekday component (1 = Sunday in the Gregorian calendar).
    public let weekday: Int
    public let averageRatio: Double

    public init(weekday: Int, averageRatio: Double) {
        self.weekday = weekday
        self.averageRatio = averageRatio
    }
}

/// Everything the tracking UI shows, computed in one pass from the task history.
public struct TrackingSummary: Equatable, Sendable {
    /// Last seven days, oldest first, ending today.
    public var week: [DayStats]
    public var currentStreak: Int
    public var bestStreak: Int
    /// True once today has at least one goal done, i.e. today is already "banked" in the streak.
    public var isTodayCounted: Bool
    public var rate7: Double?
    public var rate30: Double?
    public var averagePerDay: Double
    public var bestWeekday: WeekdayPerformance?
    public var perfectDays: Int
    /// 1.01 ^ perfectDays.
    public var score: Double
    /// Score at the end of each of the last `curveDays` days, oldest first.
    public var scoreCurve: [Double]
    /// `heatmap[column][row]`: columns are weeks (oldest first), rows follow the calendar's
    /// first weekday. Days after today are `nil`.
    public var heatmap: [[DayStats?]]

    public init(week: [DayStats], currentStreak: Int, bestStreak: Int, isTodayCounted: Bool, rate7: Double? = nil, rate30: Double? = nil, averagePerDay: Double, bestWeekday: WeekdayPerformance? = nil, perfectDays: Int, score: Double, scoreCurve: [Double], heatmap: [[DayStats?]]) {
        self.week = week
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.isTodayCounted = isTodayCounted
        self.rate7 = rate7
        self.rate30 = rate30
        self.averagePerDay = averagePerDay
        self.bestWeekday = bestWeekday
        self.perfectDays = perfectDays
        self.score = score
        self.scoreCurve = scoreCurve
        self.heatmap = heatmap
    }

    public static let empty = TrackingSummary(
        week: [], currentStreak: 0, bestStreak: 0, isTodayCounted: false,
        rate7: nil, rate30: nil, averagePerDay: 0, bestWeekday: nil,
        perfectDays: 0, score: 1, scoreCurve: [], heatmap: []
    )
}

/// Pure functions behind the streak, week strip, stats page and 1% score.
/// Days are attributed by `scheduledDate` (the day the goal was planned for), which keeps the
/// numbers consistent with the progress ring and needs no extra fields on `TaskItem`.
public enum TrackingCalculator {
    public static let dailyGain = 1.01
    public static let rateShortWindow = 7
    public static let rateLongWindow = 30
    public static let minimumWeekdaySamples = 2
    private static let maxDeferralDepth = 365

    // MARK: - Per-day stats

    public static func dayStats(for tasks: [TaskItem], calendar: Calendar) -> [Date: DayStats] {
        var buckets: [Date: (completed: Int, total: Int, deferred: Int)] = [:]
        for task in tasks {
            let day = calendar.startOfDay(for: task.scheduledDate)
            var bucket = buckets[day] ?? (0, 0, 0)
            switch task.status {
            case .deferred:
                bucket.deferred += 1
            case .done:
                bucket.completed += 1
                bucket.total += 1
            case .todo, .inProgress:
                bucket.total += 1
            }
            buckets[day] = bucket
        }
        return buckets.reduce(into: [:]) { result, entry in
            result[entry.key] = DayStats(
                date: entry.key,
                completed: entry.value.completed,
                total: entry.value.total,
                deferred: entry.value.deferred
            )
        }
    }

    // MARK: - Summary

    public static func summary(
        dayStats: [Date: DayStats],
        today rawToday: Date,
        calendar: Calendar,
        heatmapWeeks: Int = 12,
        curveDays: Int = 60
    ) -> TrackingSummary {
        let today = calendar.startOfDay(for: rawToday)

        func offset(_ days: Int, from date: Date = today) -> Date {
            calendar.date(byAdding: .day, value: days, to: date) ?? date
        }
        func stats(_ date: Date) -> DayStats {
            dayStats[date] ?? .empty(date)
        }

        // History up to and including today. Goals planned ahead never move the numbers.
        let history = dayStats.values.filter { $0.date <= today }
        let activeDates = history.filter(\.isActive).map(\.date).sorted()
        let perfectDates = history.filter(\.isPerfect).map(\.date).sorted()

        // Streaks
        let isTodayCounted = stats(today).isActive
        var current = 0
        var cursor = isTodayCounted ? today : offset(-1)
        while stats(cursor).isActive {
            current += 1
            cursor = offset(-1, from: cursor)
        }

        var best = 0
        var run = 0
        var previous: Date?
        for date in activeDates {
            if let previous, offset(1, from: previous) == date {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        best = max(best, current)

        // Rates
        func rate(window: Int) -> Double? {
            var completed = 0
            var total = 0
            for back in 0..<window {
                let day = stats(offset(-back))
                completed += day.completed
                total += day.total
            }
            return total > 0 ? Double(completed) / Double(total) : nil
        }

        // Average goals done per day over the last 30 days (shorter if the history is shorter)
        var averagePerDay = 0.0
        if let first = history.filter(\.hasGoals).map(\.date).min() {
            let windowStart = max(offset(-(rateLongWindow - 1)), first)
            let spanDays = (calendar.dateComponents([.day], from: windowStart, to: today).day ?? 0) + 1
            var completed = 0
            for index in 0..<max(1, spanDays) {
                completed += stats(offset(index, from: windowStart)).completed
            }
            averagePerDay = Double(completed) / Double(max(1, spanDays))
        }

        // Best weekday
        var ratiosByWeekday: [Int: [Double]] = [:]
        for day in history where day.total > 0 {
            ratiosByWeekday[calendar.component(.weekday, from: day.date), default: []].append(day.ratio)
        }
        let bestWeekday = ratiosByWeekday
            .filter { $0.value.count >= minimumWeekdaySamples }
            .map { WeekdayPerformance(weekday: $0.key, averageRatio: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted {
                if $0.averageRatio != $1.averageRatio { return $0.averageRatio > $1.averageRatio }
                return $0.weekday < $1.weekday
            }
            .first

        // 1% score
        let score = pow(dailyGain, Double(perfectDates.count))
        var curve: [Double] = []
        var perfectIndex = 0
        for back in stride(from: curveDays - 1, through: 0, by: -1) {
            let day = offset(-back)
            while perfectIndex < perfectDates.count, perfectDates[perfectIndex] <= day {
                perfectIndex += 1
            }
            curve.append(pow(dailyGain, Double(perfectIndex)))
        }

        // Week strip
        let week = (0..<7).map { stats(offset(-(6 - $0))) }

        // Heatmap (columns = weeks, rows = weekdays from the calendar's first weekday)
        let weekdayOfToday = calendar.component(.weekday, from: today)
        let rowOfToday = (weekdayOfToday - calendar.firstWeekday + 7) % 7
        let startOfCurrentWeek = offset(-rowOfToday)
        var heatmap: [[DayStats?]] = []
        for column in 0..<heatmapWeeks {
            let weekStart = offset(-(heatmapWeeks - 1 - column) * 7, from: startOfCurrentWeek)
            heatmap.append((0..<7).map { row in
                let day = offset(row, from: weekStart)
                return day <= today ? stats(day) : nil
            })
        }

        return TrackingSummary(
            week: week,
            currentStreak: current,
            bestStreak: best,
            isTodayCounted: isTodayCounted,
            rate7: rate(window: rateShortWindow),
            rate30: rate(window: rateLongWindow),
            averagePerDay: averagePerDay,
            bestWeekday: bestWeekday,
            perfectDays: perfectDates.count,
            score: score,
            scoreCurve: curve,
            heatmap: heatmap
        )
    }

    // MARK: - Deferrals

    /// How many times each goal has already been pushed to the next day, following `sourceTaskID`.
    /// A source that was deleted still counts as one deferral.
    public static func deferralCounts(for tasks: [TaskItem]) -> [UUID: Int] {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(tasks.count)
        for task in tasks {
            var count = 0
            var visited: Set<UUID> = [task.id]
            var cursor = task
            while let sourceID = cursor.sourceTaskID, count < maxDeferralDepth {
                count += 1
                guard let next = byID[sourceID], visited.insert(next.id).inserted else { break }
                cursor = next
            }
            counts[task.id] = count
        }
        return counts
    }
}
