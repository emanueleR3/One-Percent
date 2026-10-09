import Foundation
import Combine
import SwiftUI

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
    @Published var autoSlidingTaskID: UUID? = nil
    private var demoteWorkItems: [UUID: DispatchWorkItem] = [:]
    private var promoteWorkItems: [UUID: DispatchWorkItem] = [:]

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
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
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
        let currentDayTasks = tasks(for: targetDate)
        let maxSortOrder = currentDayTasks.map(\.sortOrder).max() ?? -1
        let newTask = TaskItem(
            title: trimmed,
            status: .todo,
            scheduledDate: targetDate,
            sortOrder: maxSortOrder + 1
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

        let wasInProgress = (existing.status == .inProgress)

        if newStatus == .deferred {
            deferTask(id: id)
            return
        }

        if existing.status == .deferred {
            // If reactivating a deferred task (e.g. back to .todo), delete the tomorrow occurrence if it is still .todo
            if let deferredID = existing.deferredToTaskID,
               let targetIndex = allTasks.firstIndex(where: { $0.id == deferredID }),
               allTasks[targetIndex].status == .todo {
                allTasks.remove(at: targetIndex)
            }
            if let currentIndex = allTasks.firstIndex(where: { $0.id == id }) {
                allTasks[currentIndex].deferredToTaskID = nil
                allTasks[currentIndex].deferredAt = nil
                allTasks[currentIndex].status = newStatus
                allTasks[currentIndex].updatedAt = Date()
            }
        } else {
            allTasks[index].status = newStatus
            allTasks[index].updatedAt = Date()
        }

        if newStatus == .done {
            scheduleAutoDemote(for: id)
        } else {
            cancelAutoDemote(for: id)
        }

        if newStatus == .inProgress {
            scheduleAutoPromote(for: id)
        } else {
            cancelAutoPromote(for: id)
        }

        if wasInProgress && newStatus == .todo {
            self.autoSlidingTaskID = id
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                self.moveTaskBelowLastInProgress(id: id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.autoSlidingTaskID == id {
                    self?.autoSlidingTaskID = nil
                }
            }
        }

        persist()
    }

    @discardableResult
    func updateTaskTitle(id: UUID, newTitle: String) -> Bool {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else {
            return false
        }
        if allTasks[index].title == trimmed {
            return true
        }
        allTasks[index].title = trimmed
        allTasks[index].updatedAt = Date()
        persist()
        return true
    }

    func deferTask(id: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let task = allTasks[index]
        let nextDay = dateService.nextDay(after: task.scheduledDate)

        let result = TaskRolloverService.deferTask(task, to: nextDay)
        switch result {
        case .success(let updatedTask, var newDeferredTask):
            let nextDayTasks = tasks(for: nextDay)
            let maxOrder = nextDayTasks.map(\.sortOrder).max() ?? -1
            newDeferredTask.sortOrder = maxOrder + 1
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

    func moveTask(from sourceID: UUID, to destinationID: UUID, for date: Date? = nil) {
        cancelAutoDemote(for: sourceID)
        cancelAutoPromote(for: sourceID)
        guard sourceID != destinationID else { return }
        let targetDate = dateService.normalize(date ?? selectedDate)
        var dayTasks = tasks(for: targetDate)
        guard let sourceIndex = dayTasks.firstIndex(where: { $0.id == sourceID }),
              let destIndex = dayTasks.firstIndex(where: { $0.id == destinationID }) else {
            return
        }

        let moved = dayTasks.remove(at: sourceIndex)
        dayTasks.insert(moved, at: destIndex)

        for (index, item) in dayTasks.enumerated() {
            if let globalIndex = allTasks.firstIndex(where: { $0.id == item.id }) {
                allTasks[globalIndex].sortOrder = index
                allTasks[globalIndex].updatedAt = Date()
            }
        }
        persist()
    }

    func moveTask(from sourceIndex: Int, to destinationIndex: Int, for date: Date? = nil) {
        let targetDate = dateService.normalize(date ?? selectedDate)
        var dayTasks = tasks(for: targetDate)
        guard sourceIndex >= 0, sourceIndex < dayTasks.count,
              destinationIndex >= 0, destinationIndex < dayTasks.count,
              sourceIndex != destinationIndex else {
            return
        }

        let sourceID = dayTasks[sourceIndex].id
        cancelAutoDemote(for: sourceID)
        cancelAutoPromote(for: sourceID)

        let moved = dayTasks.remove(at: sourceIndex)
        dayTasks.insert(moved, at: destinationIndex)

        for (index, item) in dayTasks.enumerated() {
            if let globalIndex = allTasks.firstIndex(where: { $0.id == item.id }) {
                allTasks[globalIndex].sortOrder = index
                allTasks[globalIndex].updatedAt = Date()
            }
        }
        persist()
    }

    func cancelAutoDemote(for id: UUID) {
        demoteWorkItems[id]?.cancel()
        demoteWorkItems.removeValue(forKey: id)
        if autoSlidingTaskID == id {
            autoSlidingTaskID = nil
        }
    }

    func scheduleAutoDemote(for id: UUID, delay: TimeInterval = 1.5) {
        cancelAutoDemote(for: id)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.demoteWorkItems.removeValue(forKey: id)
            guard let task = self.allTasks.first(where: { $0.id == id }),
                  task.status == .done else {
                return
            }
            self.autoSlidingTaskID = id
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                self.moveTaskToBottom(id: id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.autoSlidingTaskID == id {
                    self?.autoSlidingTaskID = nil
                }
            }
        }
        demoteWorkItems[id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelAutoPromote(for id: UUID) {
        promoteWorkItems[id]?.cancel()
        promoteWorkItems.removeValue(forKey: id)
        if autoSlidingTaskID == id {
            autoSlidingTaskID = nil
        }
    }

    func scheduleAutoPromote(for id: UUID, delay: TimeInterval = 1.0) {
        cancelAutoPromote(for: id)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.promoteWorkItems.removeValue(forKey: id)
            guard let task = self.allTasks.first(where: { $0.id == id }),
                  task.status == .inProgress else {
                return
            }
            self.autoSlidingTaskID = id
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                self.moveTaskToInProgressSection(id: id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.autoSlidingTaskID == id {
                    self?.autoSlidingTaskID = nil
                }
            }
        }
        promoteWorkItems[id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func moveTaskToInProgressSection(id: UUID, for date: Date? = nil) {
        guard let task = allTasks.first(where: { $0.id == id }) else {
            return
        }
        let targetDate = dateService.normalize(date ?? task.scheduledDate)
        var dayTasks = tasks(for: targetDate)
        guard let sourceIndex = dayTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let moved = dayTasks.remove(at: sourceIndex)

        let targetInsertIndex: Int
        if let lastInProgressIndex = dayTasks.lastIndex(where: { $0.status == .inProgress }) {
            targetInsertIndex = lastInProgressIndex + 1
        } else {
            targetInsertIndex = 0
        }

        if sourceIndex == targetInsertIndex {
            return
        }

        dayTasks.insert(moved, at: targetInsertIndex)

        for (index, item) in dayTasks.enumerated() {
            if let globalIndex = allTasks.firstIndex(where: { $0.id == item.id }) {
                allTasks[globalIndex].sortOrder = index
                allTasks[globalIndex].updatedAt = Date()
            }
        }
        persist()
    }

    func moveTaskBelowLastInProgress(id: UUID, for date: Date? = nil) {
        guard let task = allTasks.first(where: { $0.id == id }) else {
            return
        }
        let targetDate = dateService.normalize(date ?? task.scheduledDate)
        var dayTasks = tasks(for: targetDate)
        guard let sourceIndex = dayTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let tasksBelow = dayTasks.suffix(from: sourceIndex + 1)
        guard let lastInProgressBelow = tasksBelow.last(where: { $0.status == .inProgress }),
              let destIndexInDayTasks = dayTasks.firstIndex(where: { $0.id == lastInProgressBelow.id }) else {
            return
        }

        let moved = dayTasks.remove(at: sourceIndex)
        dayTasks.insert(moved, at: destIndexInDayTasks)

        for (index, item) in dayTasks.enumerated() {
            if let globalIndex = allTasks.firstIndex(where: { $0.id == item.id }) {
                allTasks[globalIndex].sortOrder = index
                allTasks[globalIndex].updatedAt = Date()
            }
        }
        persist()
    }

    func moveTaskToBottom(id: UUID, for date: Date? = nil) {
        guard let task = allTasks.first(where: { $0.id == id }) else {
            return
        }
        let targetDate = dateService.normalize(date ?? task.scheduledDate)
        var dayTasks = tasks(for: targetDate)
        guard let sourceIndex = dayTasks.firstIndex(where: { $0.id == id }),
              sourceIndex != dayTasks.count - 1 else {
            return
        }

        let moved = dayTasks.remove(at: sourceIndex)
        dayTasks.append(moved)

        for (index, item) in dayTasks.enumerated() {
            if let globalIndex = allTasks.firstIndex(where: { $0.id == item.id }) {
                allTasks[globalIndex].sortOrder = index
                allTasks[globalIndex].updatedAt = Date()
            }
        }
        persist()
    }

    func retrySave() {
        persist()
    }

    func clearErrorMessage() {
        lastErrorMessage = nil
    }

    func deleteTask(id: UUID) {
        cancelAutoDemote(for: id)
        cancelAutoPromote(for: id)
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
