import Foundation

enum ReminderKind: String, CaseIterable, Sendable {
    case morning
    case afternoon
    case wrapUp
}

/// Snapshot of one day used to word a reminder and to decide whether to send it at all.
struct DaySummary: Equatable, Sendable {
    var total: Int
    var done: Int
    /// Open goals that can still be moved to tomorrow (habits excluded).
    var remainingGoals: Int
    var remainingHabits: Int
    var theOneTitle: String?
    var theOneDone: Bool
    var streak: Int
    var isStreakCountedToday: Bool

    var remaining: Int { remainingGoals + remainingHabits }

    static let empty = DaySummary(
        total: 0, done: 0, remainingGoals: 0, remainingHabits: 0,
        theOneTitle: nil, theOneDone: false, streak: 0, isStreakCountedToday: false
    )
}

struct ReminderContent: Equatable, Sendable {
    var title: String
    var body: String
}

/// Wording and timing of the gentle nudges. Pure, so it can be tested without notifications.
enum ReminderPlanner {
    /// Returns nil when there is nothing worth saying; silence beats a pointless ping.
    static func content(for kind: ReminderKind, summary: DaySummary, variantSeed: Int) -> ReminderContent? {
        func pick(_ options: [String]) -> String {
            options[abs(variantSeed) % options.count]
        }

        switch kind {
        case .wrapUp:
            guard summary.total > 0 else { return nil }
            if summary.remainingGoals > 0 {
                let title = Lp("%d goal left", "%d goals left", summary.remainingGoals)
                if summary.streak > 0, !summary.isStreakCountedToday {
                    return ReminderContent(title: title, body: L("Keep your %d-day streak alive: one goal is enough.", summary.streak))
                }
                return ReminderContent(title: title, body: pick([
                    L("Finish one more, or move the rest to tomorrow."),
                    L("A small push now, or a clean handoff to tomorrow."),
                    L("Close what you can. The rest can wait until tomorrow.")
                ]))
            }
            if summary.remainingHabits > 0 {
                return ReminderContent(
                    title: Lp("%d habit still open", "%d habits still open", summary.remainingHabits),
                    body: pick([
                        L("Two minutes now keeps the chain going."),
                        L("Small and done beats perfect and skipped."),
                        L("One tick before bed and the streak survives.")
                    ])
                )
            }
            return nil

        case .morning:
            if let theOne = summary.theOneTitle, !summary.theOneDone {
                return ReminderContent(title: L("Good morning"), body: L("Start with “%@”. Everything else follows.", theOne))
            }
            if summary.remaining > 0 {
                let n = Lp("%d goal", "%d goals", summary.remaining)
                return ReminderContent(title: L("Good morning"), body: pick([
                    L("%@ today. Pick the one that matters most.", n),
                    L("%@ on the board. Start with the hardest while you're fresh.", n)
                ]))
            }
            return ReminderContent(title: L("Good morning"), body: pick([
                L("What's the one thing that would make today a good day?"),
                L("An empty list is a clean slate. Add your first goal.")
            ]))

        case .afternoon:
            guard summary.total > 0, summary.remaining > 0 else { return nil }
            return ReminderContent(
                title: L("%d of %d done", summary.done, summary.total),
                body: pick([
                    L("Steady beats fast. %d to go.", summary.remaining),
                    L("You're moving. %d more and the day is yours.", summary.remaining),
                    L("Halfway there is still progress. %d left.", summary.remaining)
                ])
            )
        }
    }

    /// The next `days` moments at `minutes` past midnight that are still in the future.
    static func fireDates(minutes: Int, now: Date, calendar: Calendar, days: Int) -> [Date] {
        let clamped = clampMinutes(minutes)
        let startOfToday = calendar.startOfDay(for: now)
        var result: [Date] = []
        var offset = 0
        while result.count < days, offset < days + 2 {
            if let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
               let fire = calendar.date(byAdding: .minute, value: clamped, to: day),
               fire > now {
                result.append(fire)
            }
            offset += 1
        }
        return result
    }

    static func clampMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60 - 1)
    }

    static func clockString(minutes: Int) -> String {
        let clamped = clampMinutes(minutes)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
