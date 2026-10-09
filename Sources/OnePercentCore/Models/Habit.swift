import Foundation

/// When a habit shows up. Weekday numbers follow `Calendar` (1 = Sunday in the Gregorian calendar).
///
/// Any set of weekdays is possible. `custom(days:)` folds the common sets back into the named
/// kinds, so "Monday to Friday" still reads "Weekdays" and a single day still reads "Every Friday".
public struct HabitSchedule: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case daily
        case weekdays
        case weekly
        case custom
    }

    public var kind: Kind
    /// The weekday of a `.weekly` habit.
    public var weekday: Int?
    /// The weekdays of a `.custom` habit, sorted and unique. Absent in files written before it existed.
    public var days: [Int]? = nil

    public init(kind: Kind, weekday: Int? = nil, days: [Int]? = nil) {
        self.kind = kind
        self.weekday = weekday
        self.days = days
    }

    public static let daily = HabitSchedule(kind: .daily, weekday: nil)
    public static let weekdays = HabitSchedule(kind: .weekdays, weekday: nil)

    public static func weekly(on weekday: Int) -> HabitSchedule {
        HabitSchedule(kind: .weekly, weekday: weekday)
    }

    /// Builds the schedule for an arbitrary set of weekdays. Out-of-range numbers are dropped and an
    /// empty selection means every day, so a schedule can never match nothing.
    public static func custom(days: [Int]) -> HabitSchedule {
        let valid = Set(days.filter { (1...7).contains($0) })
        switch valid.count {
        case 0, 7:
            return .daily
        case 1:
            return .weekly(on: valid.first ?? 1)
        default:
            return valid == Set(2...6)
                ? .weekdays
                : HabitSchedule(kind: .custom, weekday: nil, days: valid.sorted())
        }
    }

    /// The weekdays this schedule covers, whatever its kind. Drives the day toggles.
    public var selectedDays: Set<Int> {
        switch kind {
        case .daily: return Set(1...7)
        case .weekdays: return Set(2...6)
        case .weekly: return weekday.map { [$0] } ?? []
        case .custom: return Set(days ?? [])
        }
    }

    public func isScheduled(on date: Date, calendar: Calendar) -> Bool {
        selectedDays.contains(calendar.component(.weekday, from: date))
    }

    public func label(calendar: Calendar) -> String {
        switch kind {
        case .daily:
            return L("Every day")
        case .weekdays:
            return L("Weekdays")
        case .weekly:
            let symbols = calendar.weekdaySymbols
            if let weekday, symbols.indices.contains(weekday - 1) {
                return L("Every %@", symbols[weekday - 1])
            }
            return L("Every week")
        case .custom:
            let symbols = calendar.shortWeekdaySymbols
            let first = calendar.firstWeekday
            return selectedDays
                .sorted { ($0 - first + 7) % 7 < ($1 - first + 7) % 7 }
                .compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1].localizedCapitalized : nil }
                .joined(separator: ", ")
        }
    }
}

/// Recurring goal definition. It never shows up in the list itself: `TaskStore` materializes one
/// `TaskItem` per scheduled day (carrying `habitID`) and the streak is derived from those.
public struct Habit: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var schedule: HabitSchedule
    /// First day an occurrence may exist.
    public var startDate: Date
    public var createdAt: Date
    public var tags: [String]
    /// Scheduled days the user deleted on purpose; they are skipped, not missed.
    public var skippedDays: [Date]

    public init(
        id: UUID = UUID(),
        title: String,
        schedule: HabitSchedule,
        startDate: Date,
        createdAt: Date = Date(),
        tags: [String] = [],
        skippedDays: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.schedule = schedule
        self.startDate = startDate
        self.createdAt = createdAt
        self.tags = tags
        self.skippedDays = skippedDays
    }
}
