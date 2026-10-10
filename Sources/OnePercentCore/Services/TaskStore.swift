import Foundation
import Combine
import SwiftUI

/// Observable state and domain operations for daily tasks (Section 3.1, 5.4, 6, 7, 8)
@MainActor
public final class TaskStore: ObservableObject {
    @Published public private(set) var allTasks: [TaskItem] = [] {
        didSet {
            trackingCache = nil
            deferralCountsCache = nil
            habitStatsCache = nil
        }
    }
    @Published public private(set) var habits: [Habit] = [] {
        didSet { habitStatsCache = nil }
    }
    @Published public var selectedDate: Date {
        didSet {
            let normalized = dateService.normalize(selectedDate)
            if normalized != selectedDate {
                selectedDate = normalized
            }
        }
    }
    @Published public private(set) var lastErrorMessage: String?
    @Published public var autoSlidingTaskID: UUID? = nil
    private var trackingCache: (today: Date, summary: TrackingSummary)?
    private var deferralCountsCache: [UUID: Int]?
    private var habitStatsCache: (today: Date, stats: [UUID: HabitStats])?
    /// When goals and habits were removed here, so a deletion made offline keeps the moment it
    /// really happened when sync finally reports it.
    private var removalDates: [UUID: Date] = [:]
    private var demoteWorkItems: [UUID: DispatchWorkItem] = [:]
    private var promoteWorkItems: [UUID: DispatchWorkItem] = [:]

    private let persistence: TaskPersisting
    private let habitPersistence: HabitPersisting
    private let timerRelaunch: TimerRelaunchPolicy
    private let timerOrigin: TimerOriginStoring?
    public let dateService: DateService

    public init(
        persistence: TaskPersisting? = nil,
        dateService: DateService? = nil,
        habitPersistence: HabitPersisting? = nil,
        timerRelaunch: TimerRelaunchPolicy = .creditToLastCheckpoint,
        timerOrigin: TimerOriginStoring? = nil
    ) {
        let dateSvc = dateService ?? DateService()
        self.dateService = dateSvc
        self.selectedDate = dateSvc.today
        self.persistence = persistence ?? PersistenceController()
        self.timerRelaunch = timerRelaunch
        self.timerOrigin = timerOrigin
        // Without an explicit store, mirror the tasks store: real disk for the real app, memory for tests.
        self.habitPersistence = habitPersistence ?? (persistence == nil ? HabitPersistenceController() : InMemoryHabitPersistence())

        loadAllTasks()
        recoverInterruptedTimers()
        loadHabits()
        ensureHabitOccurrences()

        self.dateService.onDayChanged = { [weak self] newToday in
            guard let self else { return }
            // If the user was viewing today when day changed, follow to new today
            if self.dateService.isToday(self.selectedDate) {
                self.selectedDate = newToday
            }
            self.ensureHabitOccurrences()
        }
    }

    public func loadAllTasks() {
        do {
            self.allTasks = try persistence.loadTasks()
            self.lastErrorMessage = nil
        } catch {
            self.lastErrorMessage = L("Failed to load tasks: %@", error.localizedDescription)
        }
    }

    private func persist() {
        do {
            try persistence.saveTasks(allTasks)
            self.lastErrorMessage = nil
        } catch {
            self.lastErrorMessage = L("Failed to save tasks: %@", error.localizedDescription)
        }
    }

    // MARK: - Querying Tasks

    public func tasks(for date: Date) -> [TaskItem] {
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

    public var selectedDateTasks: [TaskItem] {
        tasks(for: selectedDate)
    }

    public var currentProgress: TaskProgress {
        TaskProgress(tasks: selectedDateTasks)
    }

    // MARK: - Tracking

    /// Streaks, week strip, stats page and 1% score. Recomputed only when tasks or the day change.
    public var tracking: TrackingSummary {
        let today = dateService.today
        if let cached = trackingCache, cached.today == today {
            return cached.summary
        }
        let calendar = dateService.currentCalendar
        let stats = TrackingCalculator.dayStats(for: allTasks, calendar: calendar)
        let summary = TrackingCalculator.summary(dayStats: stats, today: today, calendar: calendar)
        trackingCache = (today, summary)
        return summary
    }

    /// How many times this occurrence has already been pushed to the next day.
    public func deferralCount(for id: UUID) -> Int {
        if deferralCountsCache == nil {
            deferralCountsCache = TrackingCalculator.deferralCounts(for: allTasks)
        }
        return deferralCountsCache?[id] ?? 0
    }

    // MARK: - Task Mutations

    @discardableResult
    public func addTask(title: String, for date: Date? = nil, tags: [String] = []) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let targetDate = dateService.normalize(date ?? selectedDate)
        let newTask = insertAfterLastOpen(TaskItem(
            title: trimmed,
            status: .todo,
            scheduledDate: targetDate,
            tags: Self.normalizedTags(tags)
        ))
        persist()
        return newTask
    }

    /// Puts a new goal on its day right after the last open one (to do or in progress).
    /// Finished goals slide to the bottom of the list, so appending at the very end would bury
    /// a fresh goal under them. With nothing open, it goes first. Positions stay contiguous.
    private func insertAfterLastOpen(_ task: TaskItem) -> TaskItem {
        let day = dateService.normalize(task.scheduledDate)
        let dayTasks = tasks(for: day)
        let insertIndex = (dayTasks.lastIndex { $0.status == .todo || $0.status == .inProgress } ?? -1) + 1

        for (position, item) in dayTasks.enumerated() {
            let order = position < insertIndex ? position : position + 1
            if let global = allTasks.firstIndex(where: { $0.id == item.id }), allTasks[global].sortOrder != order {
                allTasks[global].sortOrder = order
            }
        }

        var placed = task
        placed.sortOrder = insertIndex
        allTasks.append(placed)
        return placed
    }

    public func updateTaskStatus(id: UUID, newStatus: TaskStatus) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = allTasks[index]
        if existing.status == newStatus {
            return
        }

        let wasInProgress = (existing.status == .inProgress)

        // Leaving "in progress" (done, back to to do, tomorrow) stops the clock and keeps the time.
        if existing.timerStartedAt != nil, newStatus != .inProgress {
            bankTimer(at: index, now: Date())
        }

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
    public func updateTaskTitle(id: UUID, newTitle: String) -> Bool {
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

    public func deferTask(id: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let task = allTasks[index]
        let nextDay = dateService.nextDay(after: task.scheduledDate)

        // A habit that already has its own occurrence on the next day is just skipped today:
        // a second copy tomorrow would only duplicate it.
        if let habitID = task.habitID,
           task.status != .done, task.status != .deferred,
           allTasks.contains(where: { $0.habitID == habitID && dateService.normalize($0.scheduledDate) == nextDay }) {
            allTasks[index].status = .deferred
            allTasks[index].deferredAt = Date()
            allTasks[index].isTheOne = false
            allTasks[index].updatedAt = Date()
            persist()
            return
        }

        let result = TaskRolloverService.deferTask(task, to: nextDay)
        switch result {
        case .success(var updatedTask, var newDeferredTask):
            let nextDayTasks = tasks(for: nextDay)
            let maxOrder = nextDayTasks.map(\.sortOrder).max() ?? -1
            newDeferredTask.sortOrder = maxOrder + 1
            // A goal that moved on is no longer today's most important one.
            updatedTask.isTheOne = false
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

    public func moveTask(from sourceID: UUID, to destinationID: UUID, for date: Date? = nil) {
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

    public func moveTask(from sourceIndex: Int, to destinationIndex: Int, for date: Date? = nil) {
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

    public func cancelAutoDemote(for id: UUID) {
        demoteWorkItems[id]?.cancel()
        demoteWorkItems.removeValue(forKey: id)
        if autoSlidingTaskID == id {
            autoSlidingTaskID = nil
        }
    }

    public func scheduleAutoDemote(for id: UUID, delay: TimeInterval = 1.5) {
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

    public func cancelAutoPromote(for id: UUID) {
        promoteWorkItems[id]?.cancel()
        promoteWorkItems.removeValue(forKey: id)
        if autoSlidingTaskID == id {
            autoSlidingTaskID = nil
        }
    }

    public func scheduleAutoPromote(for id: UUID, delay: TimeInterval = 1.0) {
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

    public func moveTaskToInProgressSection(id: UUID, for date: Date? = nil) {
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

    public func moveTaskBelowLastInProgress(id: UUID, for date: Date? = nil) {
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

    public func moveTaskToBottom(id: UUID, for date: Date? = nil) {
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

    public func retrySave() {
        persist()
    }

    public func clearErrorMessage() {
        lastErrorMessage = nil
    }

    public func deleteTask(id: UUID) {
        cancelAutoDemote(for: id)
        cancelAutoPromote(for: id)
        // Deleting a habit occurrence means "not this day": remember it so it is not recreated.
        if let task = allTasks.first(where: { $0.id == id }),
           let habitID = task.habitID,
           let habitIndex = habits.firstIndex(where: { $0.id == habitID }) {
            let day = dateService.normalize(task.scheduledDate)
            if !habits[habitIndex].skippedDays.contains(day) {
                habits[habitIndex].skippedDays.append(day)
                persistHabits()
            }
        }
        let initialCount = allTasks.count
        removeTasks { $0.id == id }
        if allTasks.count != initialCount {
            persist()
        }
    }

    // MARK: - Tags

    public static func normalizedTags(_ raw: [String]) -> [String] {
        var result: [String] = []
        for tag in raw {
            if let normalized = TagNormalizer.normalize(tag), !result.contains(normalized) {
                result.append(normalized)
            }
        }
        return result
    }

    public func addTag(_ raw: String, to id: UUID) {
        guard let tag = TagNormalizer.normalize(raw),
              let index = allTasks.firstIndex(where: { $0.id == id }),
              !allTasks[index].tags.contains(tag) else { return }
        allTasks[index].tags.append(tag)
        allTasks[index].updatedAt = Date()
        persist()
    }

    public func removeTag(_ tag: String, from id: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }),
              allTasks[index].tags.contains(tag) else { return }
        allTasks[index].tags.removeAll { $0 == tag }
        allTasks[index].updatedAt = Date()
        persist()
    }

    /// Every tag in use, most used first, then alphabetical.
    public var allTagNames: [String] {
        tagUsage.map(\.tag)
    }

    /// Every known tag the goal does not have yet, most used first. Tags used only on finished
    /// goals are still the user's tags, so nothing is cut off: a tag never drops out of reach just
    /// because others are used more.
    public func tagSuggestions(excluding current: [String]) -> [String] {
        allTagNames.filter { !current.contains($0) }
    }

    public var tagUsage: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for task in allTasks { for tag in task.tags { counts[tag, default: 0] += 1 } }
        for habit in habits { for tag in habit.tags where counts[tag] == nil { counts[tag] = 0 } }
        return counts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// The user's tags with a few recent goals each. Given to the on-device model so tags can be
    /// inferred from what *this* person means by "work" or "brain", not from a generic guess.
    public func tagVocabulary(maxTags: Int = 10, examplesPerTag: Int = 3) -> [TagVocabularyEntry] {
        let recentFirst = allTasks.sorted { $0.createdAt > $1.createdAt }
        return tagUsage
            .filter { $0.count > 0 }
            .prefix(maxTags)
            .map { entry in
                var seen = Set<String>()
                let examples = recentFirst
                    .filter { $0.tags.contains(entry.tag) && $0.title.count <= 80 }
                    .compactMap { task -> String? in
                        seen.insert(task.title.lowercased()).inserted ? task.title : nil
                    }
                    .prefix(examplesPerTag)
                return TagVocabularyEntry(tag: entry.tag, examples: Array(examples))
            }
    }

    public func deleteTagEverywhere(_ tag: String) {
        for index in allTasks.indices where allTasks[index].tags.contains(tag) {
            allTasks[index].tags.removeAll { $0 == tag }
        }
        var habitsChanged = false
        for index in habits.indices where habits[index].tags.contains(tag) {
            habits[index].tags.removeAll { $0 == tag }
            habitsChanged = true
        }
        persist()
        if habitsChanged { persistHabits() }
    }

    // MARK: - Notes & subtasks

    public func updateNote(id: UUID, note: String?) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard allTasks[index].note != value else { return }
        allTasks[index].note = value
        allTasks[index].updatedAt = Date()
        persist()
    }

    public func addSubtask(to id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = allTasks.firstIndex(where: { $0.id == id }) else { return }
        allTasks[index].subtasks.append(SubTask(title: trimmed))
        allTasks[index].updatedAt = Date()
        persist()
    }

    public func toggleSubtask(taskID: UUID, subtaskID: UUID) {
        mutateSubtask(taskID: taskID, subtaskID: subtaskID) { $0.isDone.toggle() }
    }

    public func renameSubtask(taskID: UUID, subtaskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateSubtask(taskID: taskID, subtaskID: subtaskID) { $0.title = trimmed }
    }

    public func deleteSubtask(taskID: UUID, subtaskID: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == taskID }) else { return }
        allTasks[index].subtasks.removeAll { $0.id == subtaskID }
        allTasks[index].updatedAt = Date()
        persist()
    }

    private func mutateSubtask(taskID: UUID, subtaskID: UUID, _ change: (inout SubTask) -> Void) {
        guard let index = allTasks.firstIndex(where: { $0.id == taskID }),
              let subIndex = allTasks[index].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        change(&allTasks[index].subtasks[subIndex])
        allTasks[index].updatedAt = Date()
        persist()
    }

    // MARK: - The One

    public func theOne(for date: Date? = nil) -> TaskItem? {
        tasks(for: date ?? selectedDate).first { $0.isTheOne && $0.status != .deferred }
    }

    /// One per day: choosing a new one clears the previous, and it moves to the top of the list.
    public func setTheOne(id: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }),
              allTasks[index].status != .deferred else { return }
        let day = dateService.normalize(allTasks[index].scheduledDate)

        for other in allTasks.indices where other != index
            && allTasks[other].isTheOne
            && dateService.normalize(allTasks[other].scheduledDate) == day {
            allTasks[other].isTheOne = false
        }
        allTasks[index].isTheOne = true
        allTasks[index].updatedAt = Date()

        var ordered = tasks(for: day).filter { $0.id != id }
        ordered.insert(allTasks[index], at: 0)
        for (order, item) in ordered.enumerated() {
            if let global = allTasks.firstIndex(where: { $0.id == item.id }) {
                allTasks[global].sortOrder = order
            }
        }
        persist()
    }

    public func clearTheOne(id: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }), allTasks[index].isTheOne else { return }
        allTasks[index].isTheOne = false
        allTasks[index].updatedAt = Date()
        persist()
    }

    public func toggleTheOne(id: UUID) {
        guard let task = allTasks.first(where: { $0.id == id }) else { return }
        if task.isTheOne { clearTheOne(id: id) } else { setTheOne(id: id) }
    }

    // MARK: - Habits

    @discardableResult
    public func addHabit(title: String, schedule: HabitSchedule, tags: [String] = [], startDate: Date? = nil) -> Habit? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let habit = Habit(
            title: trimmed,
            schedule: schedule,
            startDate: dateService.normalize(startDate ?? selectedDate),
            tags: Self.normalizedTags(tags)
        )
        habits.append(habit)
        persistHabits()
        ensureHabitOccurrences()
        return habit
    }

    /// Changes the weekdays of a habit. Open occurrences that no longer fit are dropped and the new
    /// days are filled in. Finished ones, moved exceptions and anything the user added a note,
    /// steps or The One to stay where they are.
    public func updateHabitSchedule(id: UUID, schedule: HabitSchedule) {
        guard let index = habits.firstIndex(where: { $0.id == id }), habits[index].schedule != schedule else { return }
        habits[index].schedule = schedule

        let calendar = dateService.currentCalendar
        let today = dateService.today
        removeTasks { task in
            task.habitID == id
                && task.sourceTaskID == nil
                && task.status == .todo
                && task.note == nil
                && task.subtasks.isEmpty
                && !task.isTheOne
                && dateService.normalize(task.scheduledDate) >= today
                && !schedule.isScheduled(on: task.scheduledDate, calendar: calendar)
        }
        persist()
        persistHabits()
        ensureHabitOccurrences()
    }

    /// Stops a habit. Open occurrences from today on disappear; finished ones stay as normal goals.
    public func deleteHabit(id: UUID) {
        guard habits.contains(where: { $0.id == id }) else { return }
        let today = dateService.today
        removeTasks {
            $0.habitID == id && $0.status != .done && dateService.normalize($0.scheduledDate) >= today
        }
        for index in allTasks.indices where allTasks[index].habitID == id {
            allTasks[index].habitID = nil
        }
        removalDates[id] = Date()
        habits.removeAll { $0.id == id }
        persist()
        persistHabits()
    }

    /// Creates the missing occurrences from the last seven days to the next seven, the same
    /// range the day navigation allows. Safe to call as often as needed.
    public func ensureHabitOccurrences() {
        guard !habits.isEmpty else { return }
        let calendar = dateService.currentCalendar
        let today = dateService.today
        let windowStart = dateService.normalize(calendar.date(byAdding: .day, value: -7, to: today) ?? today)
        let windowEnd = dateService.normalize(calendar.date(byAdding: .day, value: 7, to: today) ?? today)

        var existing = Set<String>()
        for task in allTasks {
            if let habitID = task.habitID {
                existing.insert("\(habitID.uuidString)|\(dateService.normalize(task.scheduledDate).timeIntervalSince1970)")
            }
        }

        var createdAny = false
        for habit in habits {
            let skipped = Set(habit.skippedDays.map { dateService.normalize($0) })
            var day = max(dateService.normalize(habit.startDate), windowStart)
            while day <= windowEnd {
                let key = "\(habit.id.uuidString)|\(day.timeIntervalSince1970)"
                if habit.schedule.isScheduled(on: day, calendar: calendar), !skipped.contains(day), !existing.contains(key) {
                    _ = insertAfterLastOpen(TaskItem(
                        id: HabitOccurrenceID.make(habitID: habit.id, day: day, calendar: calendar),
                        title: habit.title,
                        status: .todo,
                        scheduledDate: day,
                        tags: habit.tags,
                        habitID: habit.id
                    ))
                    existing.insert(key)
                    createdAny = true
                }
                day = dateService.nextDay(after: day)
            }
        }
        guard createdAny else { return }
        persist()
    }

    public func habit(for id: UUID?) -> Habit? {
        guard let id else { return nil }
        return habits.first { $0.id == id }
    }

    public func habitStats(for id: UUID) -> HabitStats {
        let today = dateService.today
        if let cached = habitStatsCache, cached.today == today {
            return cached.stats[id] ?? .empty
        }
        let byID = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var occurrences: [UUID: [Date: TaskStatus]] = [:]
        for task in allTasks {
            guard let habitID = task.habitID else { continue }
            occurrences[habitID, default: [:]][dateService.normalize(task.scheduledDate)] = effectiveHabitStatus(of: task, in: byID, today: today)
        }
        let calendar = dateService.currentCalendar
        var stats: [UUID: HabitStats] = [:]
        for habit in habits {
            stats[habit.id] = HabitCalculator.stats(
                for: habit,
                occurrences: occurrences[habit.id] ?? [:],
                today: today,
                calendar: calendar
            )
        }
        habitStatsCache = (today, stats)
        return stats[id] ?? .empty
    }

    /// What an occurrence means for the streak. A moved occurrence is judged by where it ended up:
    /// done there counts as done on its original day, still open is "not yet" (shown as
    /// `.deferred`, which the streak ignores), and anything else is a miss.
    private func effectiveHabitStatus(of task: TaskItem, in byID: [UUID: TaskItem], today: Date) -> TaskStatus {
        guard task.status == .deferred else { return task.status }

        var cursor = task
        var hops = 0
        while cursor.status == .deferred, hops < 60,
              let next = cursor.deferredToTaskID.flatMap({ byID[$0] }) {
            cursor = next
            hops += 1
        }

        switch cursor.status {
        case .done:
            return .done
        case .todo, .inProgress:
            return dateService.normalize(cursor.scheduledDate) >= today ? .deferred : .todo
        case .deferred:
            // The chain ends without a copy: the day was skipped.
            return .todo
        }
    }

    private func loadHabits() {
        do {
            habits = try habitPersistence.loadHabits()
        } catch {
            lastErrorMessage = L("Failed to load habits: %@", error.localizedDescription)
        }
    }

    private func persistHabits() {
        do {
            try habitPersistence.saveHabits(habits)
        } catch {
            lastErrorMessage = L("Failed to save habits: %@", error.localizedDescription)
        }
    }

    // MARK: - Day wrap-up

    /// Open goals that can be pushed to tomorrow. Habits stay out: they live and die with their day.
    public func wrapUpCandidates(for date: Date? = nil) -> [TaskItem] {
        tasks(for: date ?? selectedDate).filter {
            ($0.status == .todo || $0.status == .inProgress) && $0.habitID == nil
        }
    }

    /// Moves every open goal of the day to tomorrow. Returns the ids so the move can be undone.
    @discardableResult
    public func deferRemaining(for date: Date? = nil) -> [UUID] {
        let ids = wrapUpCandidates(for: date).map(\.id)
        for id in ids { deferTask(id: id) }
        return ids
    }

    /// Brings goals moved by `deferRemaining` back; their tomorrow copies are removed if untouched.
    public func undoDeferral(ids: [UUID]) {
        for id in ids { updateTaskStatus(id: id, newStatus: .todo) }
    }

    public func daySummary(for date: Date? = nil) -> DaySummary {
        let day = dateService.normalize(date ?? selectedDate)
        let dayTasks = tasks(for: day)
        let progress = TaskProgress(tasks: dayTasks)
        let theOne = dayTasks.first { $0.isTheOne && $0.status != .deferred }
        let summary = tracking
        return DaySummary(
            total: progress.totalCount,
            done: progress.completedCount,
            remainingGoals: dayTasks.filter { ($0.status == .todo || $0.status == .inProgress) && $0.habitID == nil }.count,
            remainingHabits: dayTasks.filter { ($0.status == .todo || $0.status == .inProgress) && $0.habitID != nil }.count,
            theOneTitle: theOne?.title,
            theOneDone: theOne?.status == .done,
            streak: summary.currentStreak,
            isStreakCountedToday: summary.isTodayCounted
        )
    }

    // MARK: - Focus timer

    public var runningTimerTaskID: UUID? {
        allTasks.first { $0.timerStartedAt != nil }?.id
    }

    /// Starts the clock on a goal. Only one runs at a time: any other is stopped and keeps its time.
    /// A goal that was still "to do" becomes "in progress".
    @discardableResult
    public func startTimer(id: UUID, isPomodoro: Bool = false, at now: Date = Date()) -> Bool {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else { return false }
        let status = allTasks[index].status
        guard status == .todo || status == .inProgress else { return false }
        if allTasks[index].timerStartedAt != nil { return true }

        for other in allTasks.indices where other != index && allTasks[other].timerStartedAt != nil {
            bankTimer(at: other, now: now)
        }
        if status == .todo {
            updateTaskStatus(id: id, newStatus: .inProgress)
        }
        guard let started = allTasks.firstIndex(where: { $0.id == id }) else { return false }
        allTasks[started].timerStartedAt = now
        allTasks[started].timerIsPomodoro = isPomodoro
        allTasks[started].updatedAt = now
        timerOrigin?.save(LocalTimerMarker(taskID: id, startedAt: now))
        persist()
        return true
    }

    public func pauseTimer(id: UUID, at now: Date = Date()) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }), allTasks[index].timerStartedAt != nil else { return }
        bankTimer(at: index, now: now)
        persist()
    }

    public func pauseRunningTimer(at now: Date = Date()) {
        if let id = runningTimerTaskID { pauseTimer(id: id, at: now) }
    }

    /// Called while a timer runs so a crash or force quit loses at most the last half minute:
    /// on relaunch the time is credited up to this checkpoint (`updatedAt`).
    public func timerHeartbeat(at now: Date = Date()) {
        guard let index = allTasks.firstIndex(where: { $0.timerStartedAt != nil }),
              isTimerStartedHere(allTasks[index].id) else { return }
        allTasks[index].updatedAt = now
        persist()
    }

    public func resetFocusTime(id: UUID) {
        guard let index = allTasks.firstIndex(where: { $0.id == id }) else { return }
        allTasks[index].focusSessions = []
        allTasks[index].timerStartedAt = nil
        allTasks[index].timerIsPomodoro = false
        allTasks[index].updatedAt = Date()
        persist()
    }

    /// Moves the running stretch into `focusSessions`. Stretches under a second are noise.
    private func bankTimer(at index: Int, now: Date) {
        guard let started = allTasks[index].timerStartedAt else { return }
        let seconds = now.timeIntervalSince(started)
        if seconds >= 1 {
            allTasks[index].focusSessions.append(
                FocusSession(start: started, seconds: seconds, isPomodoro: allTasks[index].timerIsPomodoro)
            )
        }
        allTasks[index].timerStartedAt = nil
        allTasks[index].timerIsPomodoro = false
        allTasks[index].updatedAt = now
    }

    /// A running timer that was started on this device, as opposed to one that arrived through
    /// sync. With no record kept (a store built without one) every timer counts as ours.
    public func isTimerStartedHere(_ id: UUID) -> Bool {
        guard let timerOrigin else { return true }
        guard let marker = timerOrigin.load(), marker.taskID == id,
              let started = allTasks.first(where: { $0.id == id })?.timerStartedAt else { return false }
        return abs(started.timeIntervalSince(marker.startedAt)) < 1
    }

    /// A timer left running this long was almost certainly forgotten, not worked on.
    public static let forgottenTimerAfter: TimeInterval = 12 * 3_600

    /// Stops the timers that have been running longer than `forgottenTimerAfter`, crediting only
    /// what was confirmed by the last checkpoint. Cheap enough to call whenever the app wakes.
    public func expireForgottenTimers(at now: Date = Date()) {
        var changed = false
        for index in allTasks.indices {
            guard let started = allTasks[index].timerStartedAt,
                  now.timeIntervalSince(started) > Self.forgottenTimerAfter else { continue }
            creditUntilLastCheckpoint(at: index)
            changed = true
        }
        if changed { persist() }
    }

    /// A timer still marked as running at launch may mean the app stopped without pausing it.
    ///
    /// Only a timer this device started can be "interrupted" by this device, and only on a Mac,
    /// where it means the app quit or the computer slept: credit the time up to the last save and
    /// stop it rather than counting the hours the app was off. A phone keeps it running: the app
    /// was most likely just suspended. A timer that came from another device is never touched:
    /// stopping it here would send a stop to the device that is still running it.
    private func recoverInterruptedTimers() {
        let now = Date()
        var changed = false
        for index in allTasks.indices {
            guard let started = allTasks[index].timerStartedAt else { continue }
            let forgotten = now.timeIntervalSince(started) > Self.forgottenTimerAfter
            let interrupted = isTimerStartedHere(allTasks[index].id) && timerRelaunch == .creditToLastCheckpoint
            guard forgotten || interrupted else { continue }
            creditUntilLastCheckpoint(at: index)
            changed = true
        }
        if changed { persist() }
    }

    private func creditUntilLastCheckpoint(at index: Int) {
        guard let started = allTasks[index].timerStartedAt else { return }
        let seconds = allTasks[index].updatedAt.timeIntervalSince(started)
        if seconds >= 1 {
            allTasks[index].focusSessions.append(
                FocusSession(start: started, seconds: seconds, isPomodoro: allTasks[index].timerIsPomodoro)
            )
        }
        allTasks[index].timerStartedAt = nil
        allTasks[index].timerIsPomodoro = false
    }

    // MARK: - Cloud sync

    /// Removes goals and remembers when, for sync.
    private func removeTasks(where shouldRemove: (TaskItem) -> Bool) {
        let now = Date()
        for task in allTasks where shouldRemove(task) { removalDates[task.id] = now }
        allTasks.removeAll(where: shouldRemove)
    }

    /// When a goal or habit that is no longer here was removed, if that happened in this session.
    public func removalDate(for id: UUID) -> Date? { removalDates[id] }

    /// Sync has told the server; the dates are no longer needed.
    public func forgetRemovals(_ ids: some Sequence<UUID>) {
        for id in ids { removalDates[id] = nil }
    }

    /// Changes that arrived from another device, ready to be folded in.
    public struct RemoteChanges: Sendable {
        public var tasks: [TaskItem]
        public var deletedTaskIDs: Set<UUID>
        public var habits: [Habit]
        public var deletedHabitIDs: Set<UUID>

        public init(
            tasks: [TaskItem] = [],
            deletedTaskIDs: Set<UUID> = [],
            habits: [Habit] = [],
            deletedHabitIDs: Set<UUID> = []
        ) {
            self.tasks = tasks
            self.deletedTaskIDs = deletedTaskIDs
            self.habits = habits
            self.deletedHabitIDs = deletedHabitIDs
        }

        public var isEmpty: Bool {
            tasks.isEmpty && deletedTaskIDs.isEmpty && habits.isEmpty && deletedHabitIDs.isEmpty
        }
    }

    /// Folds in what other devices changed. It keeps each item exactly as it came (no `updatedAt`
    /// bump, so it is not mistaken for a local edit), then repairs what two devices can break
    /// together: two goals both marked "The One", two running timers, two copies of one habit day.
    public func applyRemote(_ changes: RemoteChanges) {
        guard !changes.isEmpty else { return }
        let today = dateService.today

        var tasks = allTasks
        for id in changes.deletedTaskIDs {
            cancelAutoDemote(for: id)
            cancelAutoPromote(for: id)
        }
        if !changes.deletedTaskIDs.isEmpty {
            tasks.removeAll { changes.deletedTaskIDs.contains($0.id) }
            forgetRemovals(changes.deletedTaskIDs)
        }
        var positions: [UUID: Int] = [:]
        for (index, task) in tasks.enumerated() { positions[task.id] = index }
        for item in changes.tasks {
            if let index = positions[item.id] {
                tasks[index] = item
            } else {
                positions[item.id] = tasks.count
                tasks.append(item)
            }
        }

        // A stopped habit takes its open future goals with it; finished ones stay as plain goals.
        for habitID in changes.deletedHabitIDs {
            tasks.removeAll {
                $0.habitID == habitID && $0.status != .done && dateService.normalize($0.scheduledDate) >= today
            }
            for index in tasks.indices where tasks[index].habitID == habitID {
                tasks[index].habitID = nil
            }
        }

        var merged = habits
        merged.removeAll { changes.deletedHabitIDs.contains($0.id) }
        for habit in changes.habits {
            if let index = merged.firstIndex(where: { $0.id == habit.id }) {
                merged[index] = habit
            } else {
                merged.append(habit)
            }
        }

        allTasks = tasks
        habits = merged
        reconcileAfterMerge()
        persist()
        persistHabits()
    }

    private func reconcileAfterMerge() {
        dedupeHabitOccurrences()
        reconcileTheOne()
        reconcileRunningTimers()
        ensureHabitOccurrences()
    }

    /// Two devices can end up with the same habit day twice (an old random id and a new derived
    /// one). Keep the one that carries the most progress; every device picks the same.
    private func dedupeHabitOccurrences() {
        func rank(_ status: TaskStatus) -> Int {
            switch status {
            case .done: return 4
            case .inProgress: return 3
            case .deferred: return 2
            case .todo: return 1
            }
        }
        var groups: [String: [TaskItem]] = [:]
        for task in allTasks {
            guard let habitID = task.habitID else { continue }
            let key = "\(habitID.uuidString)|\(dateService.normalize(task.scheduledDate).timeIntervalSince1970)"
            groups[key, default: []].append(task)
        }
        var losers = Set<UUID>()
        for group in groups.values where group.count > 1 {
            let winner = group.min { lhs, rhs in
                if rank(lhs.status) != rank(rhs.status) { return rank(lhs.status) > rank(rhs.status) }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            for task in group where task.id != winner?.id { losers.insert(task.id) }
        }
        guard !losers.isEmpty else { return }
        removeTasks { losers.contains($0.id) }
    }

    /// One "The One" per day: the most recently chosen wins, every device agrees.
    private func reconcileTheOne() {
        var byDay: [Date: [Int]] = [:]
        for index in allTasks.indices where allTasks[index].isTheOne && allTasks[index].status != .deferred {
            byDay[dateService.normalize(allTasks[index].scheduledDate), default: []].append(index)
        }
        for indices in byDay.values where indices.count > 1 {
            let winner = indices.max { lhs, rhs in
                if allTasks[lhs].updatedAt != allTasks[rhs].updatedAt { return allTasks[lhs].updatedAt < allTasks[rhs].updatedAt }
                return allTasks[lhs].id.uuidString < allTasks[rhs].id.uuidString
            }
            for index in indices where index != winner {
                allTasks[index].isTheOne = false
                allTasks[index].updatedAt = Date()
            }
        }
    }

    /// One timer at a time: the most recently started keeps running; the others keep the time they
    /// had until the moment it started.
    private func reconcileRunningTimers() {
        let running = allTasks.indices.filter { allTasks[$0].timerStartedAt != nil }
        guard running.count > 1 else { return }
        let winner = running.max { lhs, rhs in
            let l = allTasks[lhs].timerStartedAt ?? .distantPast, r = allTasks[rhs].timerStartedAt ?? .distantPast
            return l != r ? l < r : allTasks[lhs].id.uuidString < allTasks[rhs].id.uuidString
        }
        guard let winner, let cutoff = allTasks[winner].timerStartedAt else { return }
        for index in running where index != winner {
            bankTimer(at: index, now: cutoff)
        }
    }

    // MARK: - Date Navigation

    public func selectDate(_ date: Date) {
        selectedDate = dateService.normalize(date)
    }

    public func selectToday() {
        selectedDate = dateService.today
    }

    public func selectTomorrow() {
        selectedDate = dateService.nextDay(after: dateService.today)
    }

    public var canGoToPreviousDay: Bool {
        dateService.canNavigatePrevious(from: selectedDate)
    }

    public var canGoToNextDay: Bool {
        dateService.canNavigateNext(from: selectedDate)
    }

    public func selectPreviousDay() {
        guard canGoToPreviousDay else { return }
        selectedDate = dateService.previousDay(before: selectedDate)
    }

    public func selectNextDay() {
        guard canGoToNextDay else { return }
        selectedDate = dateService.nextDay(after: selectedDate)
    }
}
