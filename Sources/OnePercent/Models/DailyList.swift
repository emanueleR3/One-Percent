import Foundation

/// Logical daily list representing goals scheduled for a specific date (Section 5.3)
struct DailyList: Identifiable, Equatable, Sendable {
    var id: String { dateKey }
    let dateKey: String
    let date: Date
    let tasks: [TaskItem]

    var progress: TaskProgress {
        TaskProgress(tasks: tasks)
    }

    init(date: Date, tasks: [TaskItem], calendar: Calendar = .autoupdatingCurrent) {
        let normalized = calendar.startOfDay(for: date)
        self.date = normalized

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateKey = formatter.string(from: normalized)

        self.tasks = tasks.sorted { $0.createdAt < $1.createdAt }
    }
}
