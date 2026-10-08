import Foundation

/// Progress metrics strictly calculated per ONE_PERCENT_SPEC.md (Section 8)
///
/// Formula:
/// completedCount = count(tasks where status == done)
/// totalCount = count(tasks where status != deferred)
/// progress = completedCount / totalCount (0 if totalCount == 0)
struct TaskProgress: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let ratio: Double
    let hasOnlyDeferredTasks: Bool

    init(tasks: [TaskItem]) {
        let completed = tasks.filter { $0.status == .done }.count
        let total = tasks.filter { $0.status != .deferred }.count

        self.completedCount = completed
        self.totalCount = total
        self.ratio = total > 0 ? Double(completed) / Double(total) : 0.0
        self.hasOnlyDeferredTasks = !tasks.isEmpty && total == 0
    }

    var percentageInt: Int {
        Int((ratio * 100.0).rounded())
    }

    var summaryText: String {
        if totalCount == 0 {
            return hasOnlyDeferredTasks ? "ALL DEFERRED TO TOMORROW" : "NO GOALS YET"
        }
        if completedCount == totalCount && totalCount > 0 {
            return "\(completedCount) OF \(totalCount) DONE • 100%"
        }
        return "\(completedCount) OF \(totalCount) DONE • \(percentageInt)%"
    }
}
