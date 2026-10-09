import Foundation

/// The kinds of "when" a note can name. Kept separate from the model's own types so the date and
/// tag rules below are plain, testable code that does not depend on Apple Intelligence.
public enum DayReferenceKind: Equatable, Sendable {
    case none
    case today
    case tomorrow
    case dayAfterTomorrow
    case inSomeDays
    case onWeekday
}

/// What the model said about the day. Only the field that belongs to `kind` is ever read: the
/// model likes to fill the others with plausible leftovers (today's weekday, for instance), and
/// trusting them once turned "domani" into "today".
public struct DayReference: Equatable, Sendable {
    public var kind: DayReferenceKind
    /// Used only by `.inSomeDays`.
    public var daysAhead: Int = 0
    /// `Calendar` weekday number (1 = Sunday). Used only by `.onWeekday`.
    public var weekday: Int? = nil

    public init(kind: DayReferenceKind, daysAhead: Int = 0, weekday: Int? = nil) {
        self.kind = kind
        self.daysAhead = daysAhead
        self.weekday = weekday
    }
}

public enum SmartDateResolver {
    public static let maxDaysAhead = 7

    public static func resolve(_ reference: DayReference, today: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: today)

        func offset(_ days: Int) -> Date? {
            calendar.date(byAdding: .day, value: min(max(days, 0), maxDaysAhead), to: start)
        }

        switch reference.kind {
        case .none:
            return nil
        case .today:
            return offset(0)
        case .tomorrow:
            return offset(1)
        case .dayAfterTomorrow:
            return offset(2)
        case .inSomeDays:
            return offset(reference.daysAhead)
        case .onWeekday:
            guard let weekday = reference.weekday else { return nil }
            // The model names the weekday; the arithmetic is ours. Today counts if it matches.
            let todayNumber = calendar.component(.weekday, from: start)
            return offset((weekday - todayNumber + 7) % 7)
        }
    }
}

/// One of the user's tags with a few goals that carry it, so the model can learn what each means.
public struct TagVocabularyEntry: Equatable, Sendable {
    public var tag: String
    public var examples: [String]

    public init(tag: String, examples: [String]) {
        self.tag = tag
        self.examples = examples
    }
}

public enum SmartTagFilter {
    public static let maxTags = 2

    /// Keeps only tags the user already has. The model proposes, the user's own vocabulary decides.
    public static func filter(_ proposed: [String], known: Set<String>) -> [String] {
        var result: [String] = []
        for raw in proposed {
            guard let tag = TagNormalizer.normalize(raw), known.contains(tag), !result.contains(tag) else { continue }
            result.append(tag)
            if result.count == maxTags { break }
        }
        return result
    }
}
