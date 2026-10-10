import ActivityKit
import Combine
import Foundation
import OnePercentCore

/// Mirrors the timer onto the Lock Screen and the Dynamic Island, so it stays visible after the app
/// is closed. It needs no paid account: the activity is started and updated by the app itself.
///
/// It shows any running timer, the one started here and the one the Mac started. iOS only lets an
/// app START an activity while it is on screen, so a timer begun on the Mac appears in the island
/// the next time the app is opened (or at once, if it is open). Once showing, it is updated
/// whenever the app hears of a change, and corrected when the app next wakes.
@MainActor
final class FocusLiveActivityController {
    private let store: TaskStore
    private let focus: FocusController
    private let settings: PhoneFocusSettings
    private var cancellables = Set<AnyCancellable>()
    private var inFlight: Task<Void, Never>?

    init(store: TaskStore, focus: FocusController, settings: PhoneFocusSettings) {
        self.store = store
        self.focus = focus
        self.settings = settings

        store.$allTasks.map { _ in () }
            .merge(with: focus.$pomodoro.map { _ in () })
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.reconcile() }
            .store(in: &cancellables)
    }

    /// Brings the activity in line with the timer: start, update or end it. Safe to call anytime;
    /// the app calls it at launch too, which also adopts an activity left by the previous run.
    func reconcile() {
        let wanted = desired(at: Date())
        let previous = inFlight
        inFlight = Task { [weak self] in
            await previous?.value
            await self?.apply(wanted)
        }
    }

    /// `reconcile()`, and waits until ActivityKit has been told. For a background wake-up, which
    /// must not report itself finished while the update is still on its way.
    func reconcileNow() async {
        reconcile()
        await inFlight?.value
    }

    // MARK: What should be showing

    private struct Wanted {
        var title: String
        var state: FocusActivityAttributes.ContentState
    }

    private func goal(_ id: UUID?) -> TaskItem? {
        id.flatMap { id in store.allTasks.first { $0.id == id } }
    }

    private func desired(at now: Date) -> Wanted? {
        let config = settings.pomodoroConfig

        if let block = focus.pomodoro {
            let title = goal(block.taskID)?.title ?? L("Focus")
            let end = block.startedAt.addingTimeInterval(block.duration)
            let label: String
            if block.phase.isBreak {
                label = block.phase == .longBreak ? L("Long break") : L("Break")
            } else {
                let position = L("Focus %d of %d", block.blockNumber(in: config), config.roundsBeforeLongBreak)
                label = block.isPaused ? L("Paused") + " · " + position : position
            }
            let state = FocusActivityAttributes.ContentState(
                kind: block.isPaused ? .paused : .countdown,
                label: label,
                start: block.startedAt,
                end: end,
                frozen: block.pausedRemaining,
                isBreak: block.phase.isBreak
            )
            return Wanted(title: title, state: state)
        }

        guard let id = store.runningTimerTaskID,
              let running = goal(id), let started = running.timerStartedAt else { return nil }
        // The clock shows all the time on the goal, as the app does: begin it that far before now.
        let banked = running.timeSpent(at: started)
        let state = FocusActivityAttributes.ContentState(
            kind: .stopwatch, label: L("Focus"), start: started.addingTimeInterval(-banked),
            end: nil, frozen: nil, isBreak: false
        )
        return Wanted(title: running.title, state: state)
    }

    // MARK: Talking to ActivityKit

    private func apply(_ wanted: Wanted?) async {
        let existing = Activity<FocusActivityAttributes>.activities
        guard let wanted else {
            for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }

        if let current = existing.first(where: { $0.attributes.title == wanted.title }) {
            for other in existing where other.id != current.id { await other.end(nil, dismissalPolicy: .immediate) }
            await current.update(ActivityContent(state: wanted.state, staleDate: nil))
            return
        }

        for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(
            attributes: FocusActivityAttributes(title: wanted.title),
            content: ActivityContent(state: wanted.state, staleDate: nil),
            pushType: nil
        )
    }
}
