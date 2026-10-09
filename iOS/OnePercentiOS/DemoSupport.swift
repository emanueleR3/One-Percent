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
    static func fill(_ store: TaskStore) {
        func add(_ title: String, tags: [String] = [], offset: Int = 0) -> TaskItem {
            let day = store.dateService.nextDay(after: store.dateService.today)
            let target = offset == 0 ? store.dateService.today : day
            return store.addTask(title: title, for: target, tags: tags)!
        }
        let plan = add("33% del piano", tags: ["lavoro", "brain"])
        store.updateTaskStatus(id: plan.id, newStatus: .inProgress)
        store.setTheOne(id: plan.id)
        store.addSubtask(to: plan.id, title: "Scrivere la bozza")
        store.addSubtask(to: plan.id, title: "Rivedere i numeri")
        if let first = store.allTasks.first(where: { $0.id == plan.id })?.subtasks.first {
            store.toggleSubtask(taskID: plan.id, subtaskID: first.id)
        }
        store.updateNote(id: plan.id, note: "Chiedere al team i dati di marzo.")

        let write = add("Scrivere al team", tags: ["lavoro"])
        store.updateTaskStatus(id: write.id, newStatus: .inProgress)
        _ = add("Leggere venti pagine", tags: ["personale"])
        let google = add("Configurare app Google", tags: ["lavoro", "brain"])
        store.updateTaskStatus(id: google.id, newStatus: .done)
        let mail = add("Pagare la bolletta della luce")
        store.updateTaskStatus(id: mail.id, newStatus: .done)
        _ = store.addHabit(title: "Palestra", schedule: .custom(days: [2, 4, 6]), startDate: store.dateService.today)
        _ = add("Prenotare il dentista", tags: ["personale"], offset: 1)
    }
}
#endif
