import Foundation

/// Implements exact deferral / rollover rules specified in ONE_PERCENT_SPEC.md (Section 7)
public struct TaskRolloverService {
    public enum RolloverResult {
        case success(updatedTask: TaskItem, newDeferredTask: TaskItem)
        case ignoredAlreadyDeferred(existingNewTaskID: UUID)
        case rejectedCompletedTask
        case taskNotFound
    }

    /// Defers a task occurrence to the subsequent day.
    /// - Parameters:
    ///   - task: The original task occurrence to defer
    ///   - nextDate: The target date (typically the day after task.scheduledDate)
    /// - Returns: A `RolloverResult` reflecting the outcome.
    public static func deferTask(
        _ task: TaskItem,
        to nextDate: Date,
        now: Date = Date()
    ) -> RolloverResult {
        // Section 7.3: A completed task cannot be deferred without explicitly changing its status first
        guard task.status != .done else {
            return .rejectedCompletedTask
        }

        // Section 7.3: Prevent duplicate deferrals (idempotency)
        if let existingDeferredID = task.deferredToTaskID {
            return .ignoredAlreadyDeferred(existingNewTaskID: existingDeferredID)
        }

        let newID = UUID()
        var updatedOriginal = task
        updatedOriginal.status = .deferred
        updatedOriginal.deferredAt = now
        updatedOriginal.deferredToTaskID = newID
        updatedOriginal.updatedAt = now

        let newDeferred = TaskItem(
            id: newID,
            title: task.title,
            status: .todo,
            scheduledDate: nextDate,
            createdAt: now,
            updatedAt: now,
            sourceTaskID: task.id,
            deferredToTaskID: nil,
            deferredAt: nil,
            // Details travel with the goal; "The One" is a fresh choice for the new day.
            tags: task.tags,
            note: task.note,
            subtasks: task.subtasks,
            // A habit moved to tomorrow stays a habit occurrence, as a one-off: it still counts
            // for the streak, but the schedule itself never changes.
            habitID: task.habitID
        )

        return .success(updatedTask: updatedOriginal, newDeferredTask: newDeferred)
    }
}
