import Foundation

public struct FocusDay: Equatable, Identifiable, Sendable {
    public let date: Date
    public let seconds: TimeInterval

    public init(date: Date, seconds: TimeInterval) {
        self.date = date
        self.seconds = seconds
    }
    public var id: Date { date }
}

public struct FocusGoalTime: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let seconds: TimeInterval

    public init(id: UUID, title: String, seconds: TimeInterval) {
        self.id = id
        self.title = title
        self.seconds = seconds
    }
}

/// Focus time over the last seven days, from the sessions banked on each goal.
public struct FocusSummary: Equatable, Sendable {
    /// Last seven days, oldest first, ending today.
    public var days: [FocusDay]
    public var todaySeconds: TimeInterval
    public var weekSeconds: TimeInterval
    public var sessionCount: Int
    /// Week time divided by the number of goals that got any; nil when nothing was tracked.
    public var averagePerGoal: TimeInterval?
    public var topGoals: [FocusGoalTime]

    public init(days: [FocusDay], todaySeconds: TimeInterval, weekSeconds: TimeInterval, sessionCount: Int, averagePerGoal: TimeInterval? = nil, topGoals: [FocusGoalTime]) {
        self.days = days
        self.todaySeconds = todaySeconds
        self.weekSeconds = weekSeconds
        self.sessionCount = sessionCount
        self.averagePerGoal = averagePerGoal
        self.topGoals = topGoals
    }

    public static let empty = FocusSummary(days: [], todaySeconds: 0, weekSeconds: 0, sessionCount: 0, averagePerGoal: nil, topGoals: [])
}

public enum FocusCalculator {
    public static let topGoalLimit = 4

    public static func summary(tasks: [TaskItem], now: Date, calendar: Calendar) -> FocusSummary {
        let today = calendar.startOfDay(for: now)
        let dayStarts = (0..<7).map { calendar.date(byAdding: .day, value: -(6 - $0), to: today) ?? today }
        let windowStart = dayStarts[0]
        var perDay: [Date: TimeInterval] = [:]
        var perGoal: [UUID: (title: String, seconds: TimeInterval)] = [:]
        var sessionCount = 0

        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for task in tasks {
            var pieces = task.focusSessions.map { (start: $0.start, seconds: $0.seconds) }
            if let started = task.timerStartedAt {
                pieces.append((started, max(0, now.timeIntervalSince(started))))
            }
            let key = groupKey(for: task, in: byID)

            for piece in pieces {
                let day = calendar.startOfDay(for: piece.start)
                guard day >= windowStart, day <= today, piece.seconds > 0 else { continue }
                perDay[day, default: 0] += piece.seconds
                sessionCount += 1
                var entry = perGoal[key] ?? (task.title, 0)
                entry.seconds += piece.seconds
                // Keep the title of the most recent occurrence of a moved goal or a habit.
                if task.createdAt >= (byID[key]?.createdAt ?? .distantPast) { entry.title = task.title }
                perGoal[key] = entry
            }
        }

        let days = dayStarts.map { FocusDay(date: $0, seconds: perDay[$0] ?? 0) }
        let week = days.reduce(0) { $0 + $1.seconds }
        let top = perGoal
            .map { FocusGoalTime(id: $0.key, title: $0.value.title, seconds: $0.value.seconds) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.title < $1.title }

        return FocusSummary(
            days: days,
            todaySeconds: days.last?.seconds ?? 0,
            weekSeconds: week,
            sessionCount: sessionCount,
            averagePerGoal: perGoal.isEmpty ? nil : week / Double(perGoal.count),
            topGoals: Array(top.prefix(topGoalLimit))
        )
    }

    /// Habits count as one goal per habit; a goal moved from day to day counts as one goal.
    private static func groupKey(for task: TaskItem, in byID: [UUID: TaskItem]) -> UUID {
        if let habitID = task.habitID { return habitID }
        var cursor = task
        var hops = 0
        while let source = cursor.sourceTaskID, let next = byID[source], hops < 60 {
            cursor = next
            hops += 1
        }
        return cursor.id
    }
}

public enum FocusFormat {
    /// `12:34`, or `1:02:05` past an hour. Ticks every second, so it keeps seconds.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// `45m`, `1h 05m`: for totals where seconds are noise.
    public static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        if total == 0 { return "0m" }
        if total < 60 { return "<1m" }
        let h = total / 3600, m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : String(format: "%dh %02dm", h, m)
    }
}
