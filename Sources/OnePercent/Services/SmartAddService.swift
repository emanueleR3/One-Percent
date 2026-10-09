import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What the on-device model understood from a quick-add sentence.
struct SmartGoal: Equatable, Sendable {
    var title: String
    /// Nil when the sentence did not name a day.
    var date: Date?
    var tags: [String]
    var schedule: HabitSchedule?
}

/// Natural-language quick add, powered by the on-device Apple Intelligence model.
/// Nothing leaves the Mac, and nothing is guessed with regexes: where the model is missing
/// (older macOS, Apple Intelligence off, unsupported language) the feature reports itself
/// unavailable and quick add stays a plain text field.
@MainActor
final class SmartAddService: ObservableObject {
    @Published private(set) var isAvailable = false

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                isAvailable = true
                return
            }
        }
        #endif
        isAvailable = false
    }

    /// Returns nil when the model is unavailable, refuses, or takes longer than `timeout`.
    ///
    /// `vocabulary` is the user's own tags with example goals. The model may only pick from it, which
    /// is how "domani ... il piano" gets tagged *your* "lavoro" without you typing `#lavoro`.
    func parse(
        _ text: String,
        today: Date,
        calendar: Calendar,
        vocabulary: [TagVocabularyEntry] = [],
        timeout: TimeInterval = 4
    ) async -> SmartGoal? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            return await OnDeviceGoalParser.parse(text, today: today, calendar: calendar, vocabulary: vocabulary, timeout: timeout)
        }
        #endif
        return nil
    }

    /// Loads the model ahead of the first request so the first answer is not slow.
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            OnDeviceGoalParser.prewarm()
        }
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private enum RepeatRule {
    case never
    case daily
    case mondayToFriday
    case customDays
}

@available(macOS 26.0, *)
@Generable
private enum WeekdayName {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// `Calendar` weekday number (1 = Sunday).
    var number: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }
}

@available(macOS 26.0, *)
@Generable
private enum DayWord {
    case none
    case today
    case tomorrow
    case dayAfterTomorrow
    case inSomeDays
    case onWeekday

    var kind: DayReferenceKind {
        switch self {
        case .none: return .none
        case .today: return .today
        case .tomorrow: return .tomorrow
        case .dayAfterTomorrow: return .dayAfterTomorrow
        case .inSomeDays: return .inSomeDays
        case .onWeekday: return .onWeekday
        }
    }
}

@available(macOS 26.0, *)
@Generable
private struct GoalDraft {
    @Guide(description: "The goal as a short action in the same language as the note. Remove the day, repeat words, hashtags and fillers like 'devo', 'I need to', 'ricordati di'.")
    var title: String

    @Guide(description: "When the goal is for, as the note says it. none when the note names no day at all.")
    var day: DayWord

    @Guide(description: "Only when day is inSomeDays: how many days from now. Otherwise 0.", .range(0...7))
    var daysAhead: Int

    @Guide(description: "Only when day is onWeekday: that weekday. Otherwise nil.")
    var weekday: WeekdayName?

    @Guide(description: "How often the goal repeats. never unless the note says so.")
    var repeatRule: RepeatRule

    @Guide(description: "Only when repeatRule is customDays: every weekday it repeats on, one or several. Otherwise empty.")
    var repeatDays: [WeekdayName]

    @Guide(description: "Up to two tags copied exactly from the user's tag list that match the topic of the note. Empty when none clearly fits.")
    var tags: [String]
}

@available(macOS 26.0, *)
private enum OnDeviceGoalParser {
    static func prewarm() {
        LanguageModelSession().prewarm()
    }

    static func parse(
        _ text: String,
        today: Date,
        calendar: Calendar,
        vocabulary: [TagVocabularyEntry],
        timeout: TimeInterval
    ) async -> SmartGoal? {
        let instructions = Self.instructions(today: today, calendar: calendar, vocabulary: vocabulary)

        return await withTaskGroup(of: SmartGoal?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(
                        to: text,
                        generating: GoalDraft.self,
                        options: greedyOptions()
                    )
                    return map(response.content, today: today, calendar: calendar, vocabulary: vocabulary)
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func instructions(today: Date, calendar: Calendar, vocabulary: [TagVocabularyEntry]) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, yyyy-MM-dd"

        var text = """
        You turn one short note into a to-do goal. Today is \(formatter.string(from: today)).
        Keep the title in the language of the note. Never translate it.
        The note may be in Italian or English.

        Day words (set day, and the field that goes with it):
        - "domani" / "tomorrow" -> day tomorrow
        - "dopodomani" -> day dayAfterTomorrow
        - "tra 3 giorni" / "in 3 days" -> day inSomeDays, daysAhead 3
        - "oggi" / "today" -> day today
        - a weekday name -> day onWeekday and set weekday: lunedì=monday, martedì=tuesday, mercoledì=wednesday, giovedì=thursday, venerdì=friday, sabato=saturday, domenica=sunday
        - no day word at all -> day none

        Repeat words (set repeatRule):
        - "ogni giorno", "tutti i giorni", "every day", "daily" -> daily
        - "nei giorni feriali", "dal lunedì al venerdì", "every weekday", "Monday to Friday" -> mondayToFriday (all five working days, nothing else)
        - "ogni venerdì", "every friday", "ogni settimana il lunedì" -> customDays with that one weekday in repeatDays
        - several weekdays listed ("lunedì mercoledì e venerdì", "every tuesday and thursday", "il martedì e il giovedì") -> customDays with all of them in repeatDays
        A single weekday name without "ogni" or "every" is a date (day onWeekday), never a repeat. When the note repeats, day is none.

        Examples:
        "call mom tomorrow" -> title "call mom", day tomorrow
        "domani devo arrivare al 66% del piano" -> title "arrivare al 66% del piano", day tomorrow
        "dopodomani preparare le slide" -> title "preparare le slide", day dayAfterTomorrow
        "pay rent in 3 days" -> title "pay rent", day inSomeDays, daysAhead 3
        "review the contract on friday" -> title "review the contract", day onWeekday, weekday friday
        "sabato preparare la cena" -> title "preparare la cena", day onWeekday, weekday saturday
        "lunedì devo consegnare il report" -> title "consegnare il report", day onWeekday, weekday monday
        "ogni giorno leggere 20 pagine" -> title "leggere 20 pagine", day none, repeatRule daily
        "palestra nei giorni feriali" -> title "palestra", day none, repeatRule mondayToFriday
        "weekly review every sunday" -> title "weekly review", day none, repeatRule customDays, repeatDays sunday
        "palestra ogni venerdì" -> title "palestra", day none, repeatRule customDays, repeatDays friday
        "palestra lunedì mercoledì e venerdì" -> title "palestra", day none, repeatRule customDays, repeatDays monday, wednesday, friday
        "run every tuesday and thursday" -> title "run", day none, repeatRule customDays, repeatDays tuesday, thursday
        "yoga il martedì e il giovedì" -> title "yoga", day none, repeatRule customDays, repeatDays tuesday, thursday
        "nuoto sabato e domenica" -> title "nuoto", day none, repeatRule customDays, repeatDays saturday, sunday
        "dentista venerdì" -> title "dentista", day onWeekday, weekday friday, repeatRule never
        "buy milk" -> title "buy milk", day none, repeatRule never
        """

        if vocabulary.isEmpty {
            text += "\n\nThe user has no tags yet, so tags must always be empty."
        } else {
            let lines = vocabulary.map { entry -> String in
                let examples = entry.examples.map { "\"\($0)\"" }.joined(separator: ", ")
                return examples.isEmpty ? "- \(entry.tag)" : "- \(entry.tag): \(examples)"
            }
            text += """


            The user's tags, each with example goals that carry it:
            \(lines.joined(separator: "\n"))
            For tags, choose up to two names from this list, copied exactly, only when the topic of the note clearly matches the examples of that tag. Everyday errands and anything unclear get an empty list. Never invent a tag.
            """
        }
        return text
    }

    /// Deterministic answers: the same sentence should always land on the same day.
    private static func greedyOptions() -> GenerationOptions {
        GenerationOptions(samplingMode: .greedy)
    }

    private static func map(
        _ draft: GoalDraft,
        today: Date,
        calendar: Calendar,
        vocabulary: [TagVocabularyEntry]
    ) -> SmartGoal? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // "Every Sunday" is a rule, not a date: the habit simply starts showing up on those weekdays.
        let repeatsOnWeekdays = draft.repeatRule == .customDays && !draft.repeatDays.isEmpty
        let reference = DayReference(kind: draft.day.kind, daysAhead: draft.daysAhead, weekday: draft.weekday?.number)
        let date = repeatsOnWeekdays ? nil : SmartDateResolver.resolve(reference, today: today, calendar: calendar)

        let schedule: HabitSchedule?
        switch draft.repeatRule {
        case .never: schedule = nil
        case .daily: schedule = .daily
        case .mondayToFriday: schedule = .weekdays
        case .customDays:
            schedule = draft.repeatDays.isEmpty ? nil : .custom(days: draft.repeatDays.map(\.number))
        }

        let tags = SmartTagFilter.filter(draft.tags, known: Set(vocabulary.map(\.tag)))
        return SmartGoal(title: title, date: date, tags: tags, schedule: schedule)
    }
}
#endif
