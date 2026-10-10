import Foundation
import Combine

/// What the focus timer needs to know about the user's choices (Pomodoro, sound, alerts).
public protocol FocusSettings: AnyObject {
    var pomodoroEnabled: Bool { get }
    var pomodoroConfig: PomodoroConfig { get }
    var focusSound: Bool { get }
    var focusNotifications: Bool { get }
}

/// How the timer announces the end of a block when the user asked for a notification.
public protocol FocusAlerting: AnyObject {
    /// True when the system lets the app post a notification.
    func canDeliverAlerts() async -> Bool
    /// Posts a notification right away.
    func deliver(id: String, title: String, body: String) async
}

/// Runs the focus timer and the optional Pomodoro cycle on top of `TaskStore`.
///
/// The store owns the facts (which goal is being timed, banked sessions). This owns the rhythm:
/// the one-second tick, when a block ends, the break that follows, the sound / notification, and
/// pausing when the device goes to sleep. A fake clock and scheduler make all of it testable.
/// Sound, haptics and sleep notifications are platform business: the app passes them in.
@MainActor
public final class FocusController: ObservableObject {
    /// Ticks between checkpoints written to disk while a timer runs.
    public static let heartbeatEvery = 30

    /// The current Pomodoro block (focus or break). Nil in free-timer mode and between blocks.
    @Published public private(set) var pomodoro: PomodoroState?

    private let store: TaskStore
    private let preferences: FocusSettings
    private let scheduler: FocusAlerting?
    private let now: () -> Date
    private let playSound: (String) -> Void
    private let onAlert: () -> Void
    private let autoTick: Bool

    private var completedBlocks = 0
    private var ticksSinceHeartbeat = 0
    private var ticker: Timer?
    private var pendingAlert: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(
        store: TaskStore,
        preferences: FocusSettings,
        scheduler: FocusAlerting?,
        now: @escaping () -> Date = { Date() },
        playSound: @escaping (String) -> Void = { _ in },
        onAlert: @escaping () -> Void = {},
        autoTick: Bool = true
    ) {
        self.store = store
        self.preferences = preferences
        self.scheduler = scheduler
        self.now = now
        self.playSound = playSound
        self.onAlert = onAlert
        self.autoTick = autoTick

        // A timer may already be running (e.g. started from the detail page): keep ticking for it.
        store.$allTasks
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateTicker() }
            }
            .store(in: &cancellables)

        restoreFromStore()
    }

    deinit {
        ticker?.invalidate()
    }

    // MARK: - State

    public var runningTaskID: UUID? { store.runningTimerTaskID }

    /// Something is timing, or a Pomodoro block (even a paused one or a break) is on screen.
    public var isActive: Bool { runningTaskID != nil || pomodoro != nil }

    public var isBreak: Bool { pomodoro?.phase.isBreak ?? false }

    // MARK: - Actions

    /// Play / pause for a goal, as the row button does.
    public func toggle(taskID: UUID) {
        if store.runningTimerTaskID == taskID {
            pause()
        } else if let block = pomodoro, block.isPaused, block.phase == .focus, block.taskID == taskID {
            resume()
        } else {
            start(taskID: taskID)
        }
    }

    public func start(taskID: UUID) {
        let moment = now()
        let usePomodoro = preferences.pomodoroEnabled

        // Starting a goal ends a break, or a block that belonged to another goal.
        if let block = pomodoro, block.phase.isBreak || block.taskID != taskID {
            pomodoro = nil
        }
        guard store.startTimer(id: taskID, isPomodoro: usePomodoro, at: moment) else { return }

        pomodoro = usePomodoro
            ? PomodoroEngine.startFocus(taskID: taskID, completedBlocks: completedBlocks, now: moment, config: preferences.pomodoroConfig)
            : nil
        ticksSinceHeartbeat = 0
        updateTicker()
    }

    public func pause() {
        let moment = now()
        if let id = store.runningTimerTaskID {
            store.pauseTimer(id: id, at: moment)
        }
        if let block = pomodoro {
            pomodoro = PomodoroEngine.pause(block, at: moment)
        }
        updateTicker()
    }

    public func resume() {
        let moment = now()
        guard let block = pomodoro, block.isPaused else { return }
        if block.phase == .focus, let id = block.taskID {
            guard store.startTimer(id: id, isPomodoro: true, at: moment) else {
                pomodoro = nil
                updateTicker()
                return
            }
        }
        pomodoro = PomodoroEngine.resume(block, at: moment)
        updateTicker()
    }

    /// Ends the session: banks the time and forgets the cycle.
    public func stop() {
        store.pauseRunningTimer(at: now())
        pomodoro = nil
        completedBlocks = 0
        updateTicker()
    }

    public func skipBreak() {
        guard isBreak else { return }
        pomodoro = nil
        updateTicker()
    }

    public func systemWillSleep() {
        guard isActive, !(pomodoro?.isPaused ?? false) || runningTaskID != nil else { return }
        // A timer that another device is running (it arrived through sync) is not ours to pause:
        // this computer going to sleep says nothing about the phone that started it.
        if pomodoro == nil, let id = runningTaskID, !store.isTimerStartedHere(id) { return }
        pause()
    }

    /// Picks the Pomodoro block back up after the app was closed or suspended with one running.
    /// The store remembers the timer (a start time); the block itself lived only in memory.
    ///
    /// If the block ran out meanwhile, exactly the planned block is banked, as a late tick would.
    public func restoreFromStore() {
        guard pomodoro == nil, let id = store.runningTimerTaskID, store.isTimerStartedHere(id),
              let goal = store.allTasks.first(where: { $0.id == id }),
              goal.timerIsPomodoro, let started = goal.timerStartedAt else { return }

        let config = preferences.pomodoroConfig
        let block = PomodoroState(phase: .focus, startedAt: started, duration: config.focus, completedFocusBlocks: completedBlocks, taskID: id)
        if block.isFinished(at: now()) {
            store.pauseTimer(id: id, at: started.addingTimeInterval(config.focus))
        } else {
            pomodoro = block
        }
        updateTicker()
    }

    // MARK: - Ticking

    /// Called every second while something runs.
    public func tick() {
        let moment = now()

        if let block = pomodoro, block.phase == .focus, !block.isPaused, let id = block.taskID {
            let goal = store.allTasks.first { $0.id == id }
            // The goal was completed, moved, deleted, or its clock stopped by hand: the block is over.
            if goal == nil || goal?.status == .done || goal?.status == .deferred || store.runningTimerTaskID != id {
                pomodoro = nil
            }
        } else if let block = pomodoro, block.phase == .focus, block.isPaused, let id = block.taskID {
            let status = store.allTasks.first { $0.id == id }?.status
            if status == nil || status == .done || status == .deferred { pomodoro = nil }
        }

        if let block = pomodoro, block.isFinished(at: moment) {
            blockEnded(block, at: moment)
        }

        if store.runningTimerTaskID != nil {
            ticksSinceHeartbeat += 1
            if ticksSinceHeartbeat >= Self.heartbeatEvery {
                ticksSinceHeartbeat = 0
                store.timerHeartbeat(at: moment)
                store.expireForgottenTimers(at: moment)
            }
        }

        updateTicker()
    }

    private func blockEnded(_ block: PomodoroState, at moment: Date) {
        let config = preferences.pomodoroConfig
        switch block.phase {
        case .focus:
            // Bank exactly the planned block even if this tick arrived late.
            let blockEnd = block.startedAt.addingTimeInterval(block.duration)
            if let id = block.taskID { store.pauseTimer(id: id, at: blockEnd) }
            completedBlocks = block.completedFocusBlocks + 1
            pomodoro = PomodoroEngine.next(after: block, now: blockEnd, config: config)

            let minutes = Int(((pomodoro?.duration ?? 0) / 60).rounded())
            let isLong = pomodoro?.phase == .longBreak
            alert(
                title: L("Focus block done"),
                body: isLong ? L("Time for a long break: %d minutes.", minutes) : L("Take %d minutes.", minutes),
                sound: "Glass"
            )
        case .shortBreak, .longBreak:
            pomodoro = nil
            alert(title: L("Break over"), body: L("Ready for another focus block?"), sound: "Pop")
        }
    }

    private func alert(title: String, body: String, sound: String) {
        onAlert()
        if preferences.focusSound { playSound(sound) }

        guard preferences.focusNotifications, let scheduler else { return }
        pendingAlert = Task {
            guard await scheduler.canDeliverAlerts() else { return }
            await scheduler.deliver(id: "onepercent.focus", title: title, body: body)
        }
    }

    /// Waits for an alert still being delivered. For tests.
    public func settle() async {
        await pendingAlert?.value
    }

    private var needsTicker: Bool {
        store.runningTimerTaskID != nil || (pomodoro != nil && !(pomodoro?.isPaused ?? false))
    }

    private func updateTicker() {
        guard autoTick else { return }
        if needsTicker {
            guard ticker == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }
}
