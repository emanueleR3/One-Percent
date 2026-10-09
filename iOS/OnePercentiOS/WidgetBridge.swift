import Foundation
import Combine
import WidgetKit
import OnePercentCore

/// Keeps the widget's snapshot (a small file in the shared App Group) in step with today's goals,
/// and asks WidgetKit to redraw whenever it changes.
@MainActor
final class WidgetBridge {
    private let store: TaskStore
    private var subscriptions = Set<AnyCancellable>()

    init(store: TaskStore) {
        self.store = store
        store.$allTasks.map { _ in () }
            .merge(with: store.$habits.map { _ in () })
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    /// Rewrites the snapshot from the store as it is now (also after a language change).
    func refresh() {
        let today = store.dateService.today
        let tasks = store.tasks(for: today)
        let progress = TaskProgress(tasks: tasks)
        let summary = store.tracking

        let open = tasks.filter { $0.status == .todo || $0.status == .inProgress }
        let goals = open.prefix(6).map {
            WidgetSnapshot.Goal(id: $0.id.uuidString, title: $0.title, isTheOne: $0.isTheOne, isInProgress: $0.status == .inProgress)
        }

        let status: String
        if progress.totalCount == 0 {
            status = L("no goals")
        } else if progress.completedCount == progress.totalCount {
            status = L("All done")
        } else {
            status = L("%d left", progress.totalCount - progress.completedCount)
        }

        let snapshot = WidgetSnapshot(
            day: AppGroup.dayKey(for: Date(), calendar: store.dateService.currentCalendar),
            percent: progress.percentageInt,
            completed: progress.completedCount,
            total: progress.totalCount,
            streak: summary.currentStreak,
            isTodayCounted: summary.isTodayCounted,
            goals: Array(goals),
            texts: WidgetSnapshot.Texts(
                progress: L("%d of %d", progress.completedCount, progress.totalCount),
                status: status,
                newDay: L("Today"),
                streakLabel: L("Streak")
            ),
            updatedAt: Date()
        )
        AppGroup.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
