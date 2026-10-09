import Foundation

struct PomodoroConfig: Equatable, Sendable {
    var focus: TimeInterval
    var shortBreak: TimeInterval
    var longBreak: TimeInterval
    var roundsBeforeLongBreak: Int

    init(focus: TimeInterval = 25 * 60, shortBreak: TimeInterval = 5 * 60, longBreak: TimeInterval = 15 * 60, roundsBeforeLongBreak: Int = 4) {
        self.focus = min(max(focus, 60), 120 * 60)
        self.shortBreak = min(max(shortBreak, 60), 120 * 60)
        self.longBreak = min(max(longBreak, 60), 120 * 60)
        self.roundsBeforeLongBreak = max(1, roundsBeforeLongBreak)
    }
}

enum PomodoroPhase: Equatable, Sendable {
    case focus
    case shortBreak
    case longBreak

    var isBreak: Bool { self != .focus }
}

/// One block of the Pomodoro cycle. A value type, so the state machine is plain data.
struct PomodoroState: Equatable, Sendable {
    var phase: PomodoroPhase
    var startedAt: Date
    var duration: TimeInterval
    /// Focus blocks finished before this one in the current cycle.
    var completedFocusBlocks: Int
    var taskID: UUID?
    /// Non-nil while paused: what was left on the clock.
    var pausedRemaining: TimeInterval?

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, startedAt.addingTimeInterval(duration).timeIntervalSince(now))
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    func isFinished(at now: Date) -> Bool {
        !isPaused && remaining(at: now) <= 0
    }

    /// 1-based position of this focus block inside the cycle: "2 of 4".
    func blockNumber(in config: PomodoroConfig) -> Int {
        completedFocusBlocks % config.roundsBeforeLongBreak + 1
    }
}

/// Pure Pomodoro rules: focus, short break, and a long one after every N blocks. After a break the
/// cycle waits for the user instead of silently starting the next block.
enum PomodoroEngine {
    static func startFocus(taskID: UUID?, completedBlocks: Int, now: Date, config: PomodoroConfig) -> PomodoroState {
        PomodoroState(
            phase: .focus,
            startedAt: now,
            duration: config.focus,
            completedFocusBlocks: completedBlocks,
            taskID: taskID,
            pausedRemaining: nil
        )
    }

    static func pause(_ state: PomodoroState, at now: Date) -> PomodoroState {
        guard !state.isPaused else { return state }
        var paused = state
        paused.pausedRemaining = state.remaining(at: now)
        return paused
    }

    static func resume(_ state: PomodoroState, at now: Date) -> PomodoroState {
        guard let left = state.pausedRemaining else { return state }
        var running = state
        running.pausedRemaining = nil
        running.startedAt = now.addingTimeInterval(left - state.duration)
        return running
    }

    /// What comes after a finished block, or nil when the user should decide.
    static func next(after state: PomodoroState, now: Date, config: PomodoroConfig) -> PomodoroState? {
        guard state.phase == .focus else { return nil }
        let completed = state.completedFocusBlocks + 1
        let isLong = completed % config.roundsBeforeLongBreak == 0
        return PomodoroState(
            phase: isLong ? .longBreak : .shortBreak,
            startedAt: now,
            duration: isLong ? config.longBreak : config.shortBreak,
            completedFocusBlocks: completed,
            taskID: state.taskID,
            pausedRemaining: nil
        )
    }
}
