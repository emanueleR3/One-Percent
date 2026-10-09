import Foundation
import Combine
import UserNotifications
import OnePercentCore

/// The timer and Pomodoro choices, kept in UserDefaults.
final class PhoneFocusSettings: ObservableObject, FocusSettings {
    @Published var pomodoroEnabled: Bool { didSet { defaults.set(pomodoroEnabled, forKey: "pomodoroEnabled") } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes") } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    @Published var pomodoroRounds: Int { didSet { defaults.set(pomodoroRounds, forKey: "pomodoroRounds") } }
    @Published var focusNotifications: Bool { didSet { defaults.set(focusNotifications, forKey: "focusNotifications") } }

    /// The notification carries its own sound on the iPhone.
    var focusSound: Bool { false }

    var pomodoroConfig: PomodoroConfig {
        PomodoroConfig(
            focus: TimeInterval(focusMinutes * 60),
            shortBreak: TimeInterval(shortBreakMinutes * 60),
            longBreak: TimeInterval(longBreakMinutes * 60),
            roundsBeforeLongBreak: pomodoroRounds
        )
    }

    private let defaults = UserDefaults.standard

    init() {
        let stored = UserDefaults.standard
        func int(_ key: String, _ fallback: Int) -> Int { stored.object(forKey: key) as? Int ?? fallback }
        pomodoroEnabled = stored.bool(forKey: "pomodoroEnabled")
        focusMinutes = int("focusMinutes", 25)
        shortBreakMinutes = int("shortBreakMinutes", 5)
        longBreakMinutes = int("longBreakMinutes", 15)
        pomodoroRounds = int("pomodoroRounds", 4)
        focusNotifications = stored.bool(forKey: "focusNotifications")
    }
}

/// Announces the end of a Pomodoro block with a notification scheduled for that exact moment, so it
/// arrives even when the app is asleep. It follows the timer: pausing or stopping cancels it, and
/// every new block (a break after a focus block, the next focus block) schedules the next one.
@MainActor
final class FocusBackgroundAlerts {
    static let identifier = "onepercent.focus.block"

    private let settings: PhoneFocusSettings
    private let center = UNUserNotificationCenter.current()
    private var subscription: AnyCancellable?

    init(focus: FocusController, settings: PhoneFocusSettings) {
        self.settings = settings
        subscription = focus.$pomodoro.sink { [weak self] state in
            // `@Published` emits before the property changes: use the value it hands over.
            self?.update(for: state)
        }
    }

    /// Asks iOS for permission, when the user turns the alert on.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func update(for state: PomodoroState?) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard settings.focusNotifications, let state, !state.isPaused else { return }

        let end = state.startedAt.addingTimeInterval(state.duration)
        let wait = end.timeIntervalSinceNow
        guard wait > 1 else { return }

        let content = UNMutableNotificationContent()
        switch state.phase {
        case .focus:
            content.title = L("Focus block done")
            if let next = PomodoroEngine.next(after: state, now: end, config: settings.pomodoroConfig) {
                let minutes = Int((next.duration / 60).rounded())
                content.body = next.phase == .longBreak ? L("Time for a long break: %d minutes.", minutes) : L("Take %d minutes.", minutes)
            }
        case .shortBreak, .longBreak:
            content.title = L("Break over")
            content.body = L("Ready for another focus block?")
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
        )
        center.add(request)
    }
}
