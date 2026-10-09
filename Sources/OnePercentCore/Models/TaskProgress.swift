import Foundation

/// Progress metrics strictly calculated per ONE_PERCENT_SPEC.md (Section 8)
///
/// Formula:
/// completedCount = count(tasks where status == done)
/// totalCount = count(tasks where status != deferred)
/// progress = completedCount / totalCount (0 if totalCount == 0)
public struct TaskProgress: Equatable, Sendable {
    public let completedCount: Int
    public let totalCount: Int
    public let ratio: Double
    public let hasOnlyDeferredTasks: Bool

    public init(tasks: [TaskItem]) {
        let completed = tasks.filter { $0.status == .done }.count
        let total = tasks.filter { $0.status != .deferred }.count

        self.completedCount = completed
        self.totalCount = total
        self.ratio = total > 0 ? Double(completed) / Double(total) : 0.0
        self.hasOnlyDeferredTasks = !tasks.isEmpty && total == 0
    }

    public var percentageInt: Int {
        Int((ratio * 100.0).rounded())
    }

    public var summaryText: String {
        if totalCount == 0 {
            return hasOnlyDeferredTasks ? "ALL DEFERRED TO TOMORROW" : "NO GOALS YET"
        }
        if completedCount == totalCount && totalCount > 0 {
            return "\(completedCount) OF \(totalCount) DONE • 100%"
        }
        return "\(completedCount) OF \(totalCount) DONE • \(percentageInt)%"
    }
}
