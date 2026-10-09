import Foundation
import Combine
import UserNotifications
import OnePercentCore

/// Gentle local reminders (morning plan, afternoon check-in, evening wrap-up).
///
/// They are rebuilt from the day's real state every time something changes, for the next few days,
/// so the wording ("3 goals left") is right when it fires. Banner only, no sound, and nothing at
/// all when there is nothing useful to say. All of it works without a paid developer account:
/// these are local notifications, not push.
@MainActor
final class PhoneReminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    struct Slot: Codable, Equatable {
        var isEnabled: Bool
        /// Minutes after midnight, local time.
        var minutes: Int
    }

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled); changed() } }
    @Published private(set) var slots: [ReminderKind: Slot]
    @Published private(set) var isBlocked = false

    private enum Keys {
        static let enabled = "remindersEnabled"
        static let slots = "reminderSlots"
    }

    private static let identifierPrefix = "onepercent.reminder."
    private static let category = "ONEPERCENT_WRAPUP"
    private static let moveAction = "ONEPERCENT_MOVE_TO_TOMORROW"
    private static let daysAhead = 3

    private let store: TaskStore
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(store: TaskStore) {
        self.store = store
        self.isEnabled = defaults.bool(forKey: Keys.enabled)
        let stored = defaults.data(forKey: Keys.slots).flatMap { try? JSONDecoder().decode([String: Slot].self, from: $0) } ?? [:]
        func slot(_ kind: ReminderKind, _ fallback: Slot) -> Slot { stored[kind.rawValue] ?? fallback }
        self.slots = [
            .morning: slot(.morning, Slot(isEnabled: false, minutes: 9 * 60)),
            .afternoon: slot(.afternoon, Slot(isEnabled: false, minutes: 15 * 60)),
            .wrapUp: slot(.wrapUp, Slot(isEnabled: true, minutes: 21 * 60))
        ]
        super.init()
    }

    func start() {
        center.delegate = self
        registerCategories()
        store.$allTasks.dropFirst().sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &cancellables)
        scheduleRefresh()
    }

    /// Action titles are registered once; call again after a language change.
    func languageDidChange() {
        registerCategories()
        scheduleRefresh()
    }

    func slot(_ kind: ReminderKind) -> Slot { slots[kind] ?? Slot(isEnabled: false, minutes: 9 * 60) }

    func setSlot(_ kind: ReminderKind, _ slot: Slot) {
        slots[kind] = slot
        let encoded = Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) { defaults.set(data, forKey: Keys.slots) }
        changed()
    }

    /// Turning reminders on is when iOS is asked for permission, never earlier.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
            isBlocked = !granted
            isEnabled = granted
        } else {
            isEnabled = false
        }
    }

    func refreshAuthorization() async {
        let status = await center.notificationSettings().authorizationStatus
        isBlocked = status == .denied
        if isBlocked && isEnabled { isEnabled = false }
    }

    // MARK: Scheduling

    private func changed() { scheduleRefresh() }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.rebuild()
        }
    }

    private func rebuild() async {
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers())
        guard isEnabled, slots.values.contains(where: \.isEnabled) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let calendar = store.dateService.currentCalendar
        let now = Date()
        var summaries: [Date: DaySummary] = [:]
        for kind in ReminderKind.allCases {
            let slot = slot(kind)
            guard slot.isEnabled else { continue }
            for fire in ReminderPlanner.fireDates(minutes: slot.minutes, now: now, calendar: calendar, days: Self.daysAhead) {
                let day = store.dateService.normalize(fire)
                let summary = summaries[day] ?? store.daySummary(for: day)
                summaries[day] = summary
                let seed = calendar.ordinality(of: .day, in: .year, for: fire) ?? 0
                guard let content = ReminderPlanner.content(for: kind, summary: summary, variantSeed: seed) else { continue }

                let message = UNMutableNotificationContent()
                message.title = content.title
                message.body = content.body
                if kind == .wrapUp { message.categoryIdentifier = Self.category }
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(
                    identifier: identifier(kind, day: day),
                    content: message,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
                try? await center.add(request)
            }
        }
    }

    private func identifier(_ kind: ReminderKind, day: Date) -> String {
        "\(Self.identifierPrefix)\(kind.rawValue).\(store.dateService.dayKey(for: day))"
    }

    private func allIdentifiers() -> [String] {
        let today = store.dateService.normalize(Date())
        let calendar = store.dateService.currentCalendar
        let days = (0...(Self.daysAhead + 1)).map { calendar.date(byAdding: .day, value: $0, to: today) ?? today }
        return ReminderKind.allCases.flatMap { kind in days.map { identifier(kind, day: store.dateService.normalize($0)) } }
    }

    private func registerCategories() {
        let move = UNNotificationAction(identifier: Self.moveAction, title: L("Move to tomorrow"), options: [])
        let category = UNNotificationCategory(identifier: Self.category, actions: [move], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.moveAction else { return }
        await MainActor.run {
            _ = store.deferRemaining(for: store.dateService.today)
            scheduleRefresh()
        }
    }
}
