import Foundation
import AppKit
import Combine

/// Keeps the system's pending notifications in sync with the user's reminder settings and the
/// current state of the day, so the wording ("3 goals left") is never stale when it fires.
///
/// Reminders are scheduled two days ahead as one-shot requests and rebuilt after every change
/// (debounced). Quiet by design: banner only, no sound, and nothing at all when there is nothing
/// useful to say.
@MainActor
final class ReminderCoordinator: ObservableObject {
    @Published private(set) var authorization: NotificationAuthorization = .notDetermined

    /// Called when the user taps the notification body.
    var onOpenRequested: (() -> Void)? {
        get { scheduler.onOpenRequested }
        set { scheduler.onOpenRequested = newValue }
    }

    private static let identifierPrefix = "onepercent.reminder."

    private let store: TaskStore
    private let preferences: AppPreferences
    private let scheduler: NotificationScheduling
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var refreshTask: Task<Void, Never>?

    init(
        store: TaskStore,
        preferences: AppPreferences,
        scheduler: NotificationScheduling,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.preferences = preferences
        self.scheduler = scheduler
        self.now = now
    }

    deinit {
        observers.forEach { $0.0.removeObserver($0.1) }
    }

    func start() {
        scheduler.start()
        scheduler.onMoveToTomorrow = { [weak self] in
            guard let self else { return }
            self.store.deferRemaining(for: self.store.dateService.today)
            self.scheduleRefresh()
        }

        store.$allTasks
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)
        preferences.objectWillChange
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        let sources: [(NotificationCenter, Notification.Name)] = [
            (.default, .NSCalendarDayChanged),
            (.default, NSApplication.didBecomeActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        ]
        for (center, name) in sources {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            }
            observers.append((center, token))
        }

        scheduleRefresh()
    }

    /// Asks macOS for permission. Called when the user turns notifications on, never earlier.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = await scheduler.requestAuthorization()
        await refreshAuthorization()
        scheduleRefresh()
        return granted
    }

    func refreshAuthorization() async {
        authorization = await scheduler.authorizationStatus()
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Rebuilds every pending reminder from scratch.
    func refresh() async {
        await refreshAuthorization()
        scheduler.removePending(ids: allIdentifiers())
        guard preferences.anyReminderEnabled, authorization == .authorized else { return }

        let calendar = store.dateService.currentCalendar
        let current = now()
        let today = store.dateService.normalize(current)
        let tomorrow = store.dateService.nextDay(after: today)
        let summaries = [today: store.daySummary(for: today), tomorrow: store.daySummary(for: tomorrow)]

        for kind in ReminderKind.allCases {
            let slot = preferences.slot(for: kind)
            guard slot.isEnabled else { continue }
            for fire in ReminderPlanner.fireDates(minutes: slot.minutes, now: current, calendar: calendar, days: 2) {
                let day = calendar.startOfDay(for: fire)
                guard let summary = summaries[day] else { continue }
                let seed = calendar.ordinality(of: .day, in: .year, for: fire) ?? 0
                guard let content = ReminderPlanner.content(for: kind, summary: summary, variantSeed: seed) else { continue }

                await scheduler.schedule(
                    ReminderRequest(
                        id: identifier(kind, day: day),
                        title: content.title,
                        body: content.body,
                        fireDate: fire,
                        isWrapUp: kind == .wrapUp
                    ),
                    calendar: calendar
                )
            }
        }
    }

    // MARK: - Identifiers

    private func identifier(_ kind: ReminderKind, day: Date) -> String {
        "\(Self.identifierPrefix)\(kind.rawValue).\(store.dateService.dayKey(for: day))"
    }

    private func allIdentifiers() -> [String] {
        let today = store.dateService.normalize(now())
        let days = (0...2).map { offset in
            store.dateService.currentCalendar.date(byAdding: .day, value: offset, to: today) ?? today
        }
        return ReminderKind.allCases.flatMap { kind in days.map { identifier(kind, day: $0) } }
    }
}
