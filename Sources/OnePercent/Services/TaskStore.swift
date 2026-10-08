import Foundation
import Combine

/// Observable state and domain operations for daily tasks (Section 3.1, 5.4, 6, 7, 8)
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var allTasks: [TaskItem] = []
    @Published var selectedDate: Date {
        didSet {
            let normalized = dateService.normalize(selectedDate)
            if normalized != selectedDate {
                selectedDate = normalized
            }
        }
    }
    @Published private(set) var lastErrorMessage: String?

    private let persistence: TaskPersisting
    let dateService: DateService

    init(
        persistence: TaskPersisting? = nil,
        dateService: DateService? = nil
    ) {
        let dateSvc = dateService ?? DateService()
        self.dateService = dateSvc
        self.selectedDate = dateSvc.today
        self.persistence = persistence ?? PersistenceController()

        loadAllTasks()

        self.dateService.onDayChanged = { [weak self] newToday in
            guard let self else { return }
            // If the user was viewing today when day changed, follow to new today
            if self.dateService.isToday(self.selectedDate) {
                self.selectedDate = newToday
            }
        }
    }

    func loadAllTasks() {
        do {
            self.allTasks = try persistence.loadTasks()
            self.lastErrorMessage = nil
        } catch {
            self.lastErrorMessage = "Failed to load tasks: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try persistence.saveTasks(allTasks)
            self.lastErrorMessage = nil
        } catch {
            self.lastErrorMessage = "Failed to save tasks: \(error.localizedDescription)"
        }
    }

    // MARK: - Querying Tasks

    func tasks(for date: Date) -> [TaskItem] {
        let target = dateService.normalize(date)
        return allTasks
            .filter { dateService.normalize($0.scheduledDate) == target }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var selectedDateTasks: [TaskItem] {
        tasks(for: selectedDate)
    }

    var currentProgress: TaskProgress {
        TaskProgress(tasks: selectedDateTasks)
    }

    // MARK: - Task Mutations

    @discardableResult
    func addTask(title: String, for date: Date? = nil) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let targetDate = dateService.normalize(date ?? selectedDate)
        let newTask = TaskItem(
            title: trimmed,
            status: .todo,
            scheduledDate: targetDate
        )

        allTasks.append(newTask)
        persist()
        return newTask
    }

    func updateTaskStatus(id: UUID, newStatus: TaskStatus) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = allTasks[index]
        if existing.status == newStatus {
            return
        }

        if newStatus == .deferred {
            deferTask(id: id)
            return
        }

        allTasks[index].status = newStatus
        if existing.status == .deferred {
            allTasks[index].deferredToTaskID = nil
            allTasks[index].deferredAt = nil
        }
        allTasks[index].updatedAt = Date()
        persist()
    }

    func deferTask(id: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let task = allTasks[index]
        let nextDay = dateService.nextDay(after: task.scheduledDate)

        let result = TaskRolloverService.deferTask(task, to: nextDay)
        switch result {
        case .success(let updatedTask, let newDeferredTask):
            allTasks[index] = updatedTask
            allTasks.append(newDeferredTask)
            persist()

        case .ignoredAlreadyDeferred:
            // Idempotent: already deferred
            break

        case .rejectedCompletedTask:
            // Spec Section 7.3: completed tasks cannot be deferred directly
            break

        case .taskNotFound:
            break
        }
    }

    func retrySave() {
        persist()
    }

    func clearErrorMessage() {
        lastErrorMessage = nil
    }

    func deleteTask(id: UUID) {
        let initialCount = allTasks.count
        allTasks.removeAll { $0.id == id }
        if allTasks.count != initialCount {
            persist()
        }
    }

    // MARK: - Date Navigation

    func selectDate(_ date: Date) {
        selectedDate = dateService.normalize(date)
    }

    func selectToday() {
        selectedDate = dateService.today
    }

    func selectTomorrow() {
        selectedDate = dateService.nextDay(after: dateService.today)
    }

    var canGoToPreviousDay: Bool {
        dateService.canNavigatePrevious(from: selectedDate)
    }

    var canGoToNextDay: Bool {
        dateService.canNavigateNext(from: selectedDate)
    }

    func selectPreviousDay() {
        guard canGoToPreviousDay else { return }
        selectedDate = dateService.previousDay(before: selectedDate)
    }

    func selectNextDay() {
        guard canGoToNextDay else { return }
        selectedDate = dateService.nextDay(after: selectedDate)
    }
}
