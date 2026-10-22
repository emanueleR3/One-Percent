#if DEBUG
import Foundation
import OnePercentCore

/// Sample data for looking at the screens. Only in development builds, only with `-demo`.
final class DemoPersistence: TaskPersisting, @unchecked Sendable {
    func loadTasks() throws -> [TaskItem] { [] }
    func saveTasks(_ tasks: [TaskItem]) throws {}
}

@MainActor
enum DemoData {
    /// Sample goals in the demo's language (`-demoItalian` for Italian).
    private struct Words {
        var plan, draft, numbers, note, review, read, laptop, bill, gym, dentist, goalA, goalB: String
        var work, focus, personal: String

        static let english = Words(
            plan: "Ship the 1% plan", draft: "Write the draft", numbers: "Check the numbers",
            note: "Ask the team for the March numbers.", review: "Reply to the design review",
            read: "Read twenty pages", laptop: "Set up the new laptop", bill: "Pay the electricity bill",
            gym: "Gym", dentist: "Book the dentist", goalA: "Goal A", goalB: "Goal B",
            work: "work", focus: "focus", personal: "personal"
        )
        static let italian = Words(
            plan: "33% del piano", draft: "Scrivere la bozza", numbers: "Rivedere i numeri",
            note: "Chiedere al team i dati di marzo.", review: "Rispondere alla revisione del design",
            read: "Leggere venti pagine", laptop: "Configurare il nuovo portatile", bill: "Pagare la bolletta della luce",
            gym: "Palestra", dentist: "Prenotare il dentista", goalA: "Obiettivo A", goalB: "Obiettivo B",
            work: "lavoro", focus: "focus", personal: "personale"
        )
    }

    static func fill(_ store: TaskStore, italian: Bool) {
        let w = italian ? Words.italian : Words.english
        func add(_ title: String, tags: [String] = [], offset: Int = 0) -> TaskItem {
            let day = store.dateService.nextDay(after: store.dateService.today)
            let target = offset == 0 ? store.dateService.today : day
            return store.addTask(title: title, for: target, tags: tags)!
        }
        let plan = add(w.plan, tags: [w.work, w.focus])
        store.updateTaskStatus(id: plan.id, newStatus: .inProgress)
        store.setTheOne(id: plan.id)
        store.addSubtask(to: plan.id, title: w.draft)
        store.addSubtask(to: plan.id, title: w.numbers)
        if let first = store.allTasks.first(where: { $0.id == plan.id })?.subtasks.first {
            store.toggleSubtask(taskID: plan.id, subtaskID: first.id)
        }
        store.updateNote(id: plan.id, note: w.note)

        let review = add(w.review, tags: [w.work])
        store.updateTaskStatus(id: review.id, newStatus: .inProgress)
        _ = add(w.read, tags: [w.personal])
        let laptop = add(w.laptop, tags: [w.work, w.focus])
        store.updateTaskStatus(id: laptop.id, newStatus: .done)
        let bill = add(w.bill)
        store.updateTaskStatus(id: bill.id, newStatus: .done)
        _ = store.addHabit(title: w.gym, schedule: .custom(days: [2, 4, 6]), startDate: store.dateService.today)
        _ = add(w.dentist, tags: [w.personal], offset: 1)

        // A few finished days behind us, so the streak, the heatmap and the score curve have something to show.
        let calendar = store.dateService.currentCalendar
        for back in 1...5 {
            let day = store.dateService.normalize(calendar.date(byAdding: .day, value: -back, to: store.dateService.today)!)
            for title in [w.goalA, w.goalB] {
                if let task = store.addTask(title: title, for: day) {
                    if back != 3 { store.updateTaskStatus(id: task.id, newStatus: .done) }
                }
            }
        }
    }
}
#endif
