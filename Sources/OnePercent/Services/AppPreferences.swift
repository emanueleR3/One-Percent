import Foundation
import Combine
import OnePercentCore

/// User-facing settings, persisted in `UserDefaults`. Reads fall back to defaults when a stored
/// value is missing or unreadable, so a bad write can never lock the app out.
@MainActor
final class AppPreferences: ObservableObject {
    struct ReminderSlot: Codable, Equatable, Sendable {
        var isEnabled: Bool
        /// Minutes after midnight, local time.
        var minutes: Int
    }

    private enum Keys {
        static let wrapUp = "wrapUp"
        static let morning = "morning"
        static let afternoon = "afternoon"
        static let notifications = "notificationsEnabled"
        static let openOnHover = "openOnHover"
        static let smartAdd = "smartAddEnabled"
        static let tagColors = "tagColors"
        static let wrapUpDismissedDay = "wrapUpDismissedDay"
        static let indicatorEnabled = "indicatorEnabled"
        static let indicatorShowsTimer = "indicatorShowsTimer"
        static let virtualNotchWidth = "virtualNotchWidth"
        static let virtualNotchHeight = "virtualNotchHeight"
        static let screenSelection = "screenSelection"
        static let panelAnchor = "panelAnchor"
        static let openDelay = "openDelay"
        static let closeDelay = "closeDelay"
        static let pomodoroEnabled = "pomodoroEnabled"
        static let focusMinutes = "focusMinutes"
        static let shortBreakMinutes = "shortBreakMinutes"
        static let longBreakMinutes = "longBreakMinutes"
        static let pomodoroRounds = "pomodoroRounds"
        static let focusSound = "focusSound"
        static let focusNotifications = "focusNotifications"
        static let language = "language"
    }

    /// Longest open / close delay offered, in seconds.
    static let maxDelay: Double = 2.0

    private let defaults: UserDefaults

    @Published var wrapUp: ReminderSlot { didSet { store(wrapUp, for: Keys.wrapUp) } }
    @Published var morning: ReminderSlot { didSet { store(morning, for: Keys.morning) } }
    @Published var afternoon: ReminderSlot { didSet { store(afternoon, for: Keys.afternoon) } }
    /// Master switch for system notifications. Off until the user turns it on, which is also when
    /// macOS is asked for permission, so nothing pops up at first launch.
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) } }
    @Published var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Keys.openOnHover) } }
    @Published var smartAddEnabled: Bool { didSet { defaults.set(smartAddEnabled, forKey: Keys.smartAdd) } }
    @Published private(set) var tagColors: [String: Int] { didSet { store(tagColors, for: Keys.tagColors) } }

    // MARK: Language

    /// Follow macOS, or force English / Italian. Applied live: no relaunch needed.
    @Published var language: LanguageChoice { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }

    func resolvedLanguage(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        language.resolve(preferred: preferred)
    }

    // MARK: Notch

    /// The virtual notch: a black notch drawn over the real one, showing today's progress on both
    /// sides while the panel is closed. (Stored under the old "indicator" keys.)
    @Published var indicatorEnabled: Bool { didSet { defaults.set(indicatorEnabled, forKey: Keys.indicatorEnabled) } }
    /// Also show the running timer / Pomodoro countdown there.
    @Published var indicatorShowsTimer: Bool { didSet { defaults.set(indicatorShowsTimer, forKey: Keys.indicatorShowsTimer) } }
    /// Size of the virtual notch in points; 0 means "match this display automatically".
    @Published var virtualNotchWidth: Double { didSet { defaults.set(virtualNotchWidth, forKey: Keys.virtualNotchWidth) } }
    @Published var virtualNotchHeight: Double { didSet { defaults.set(virtualNotchHeight, forKey: Keys.virtualNotchHeight) } }
    @Published var screenSelection: ScreenSelection { didSet { defaults.set(screenSelection.stored, forKey: Keys.screenSelection) } }
    /// Panel position on displays without a notch.
    @Published var panelAnchor: PanelAnchor { didSet { defaults.set(panelAnchor.rawValue, forKey: Keys.panelAnchor) } }
    @Published var openDelay: Double {
        didSet {
            let clamped = Self.clampDelay(openDelay)
            if clamped != openDelay { openDelay = clamped; return }
            defaults.set(openDelay, forKey: Keys.openDelay)
        }
    }
    @Published var closeDelay: Double {
        didSet {
            let clamped = Self.clampDelay(closeDelay)
            if clamped != closeDelay { closeDelay = clamped; return }
            defaults.set(closeDelay, forKey: Keys.closeDelay)
        }
    }

    // MARK: Focus

    @Published var pomodoroEnabled: Bool { didSet { defaults.set(pomodoroEnabled, forKey: Keys.pomodoroEnabled) } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Keys.focusMinutes) } }
    @Published var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: Keys.shortBreakMinutes) } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Keys.longBreakMinutes) } }
    @Published var pomodoroRounds: Int { didSet { defaults.set(pomodoroRounds, forKey: Keys.pomodoroRounds) } }
    @Published var focusSound: Bool { didSet { defaults.set(focusSound, forKey: Keys.focusSound) } }
    /// A system notification when a block ends. Off until the user turns it on (which asks permission).
    @Published var focusNotifications: Bool { didSet { defaults.set(focusNotifications, forKey: Keys.focusNotifications) } }

    var pomodoroConfig: PomodoroConfig {
        PomodoroConfig(
            focus: TimeInterval(focusMinutes) * 60,
            shortBreak: TimeInterval(shortBreakMinutes) * 60,
            longBreak: TimeInterval(longBreakMinutes) * 60,
            roundsBeforeLongBreak: pomodoroRounds
        )
    }
    /// 0 stays "automatic"; anything else is kept to a size that can still be drawn.
    static func clampNotchSize(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return min(600, max(16, value))
    }


    private static func clampDelay(_ value: Double) -> Double {
        min(max(value, 0), maxDelay)
    }
    @Published private(set) var wrapUpDismissedDay: String? {
        didSet { defaults.set(wrapUpDismissedDay, forKey: Keys.wrapUpDismissedDay) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.wrapUp = Self.load(ReminderSlot.self, key: Keys.wrapUp, in: defaults) ?? .init(isEnabled: true, minutes: 21 * 60)
        self.morning = Self.load(ReminderSlot.self, key: Keys.morning, in: defaults) ?? .init(isEnabled: false, minutes: 9 * 60)
        self.afternoon = Self.load(ReminderSlot.self, key: Keys.afternoon, in: defaults) ?? .init(isEnabled: false, minutes: 15 * 60)
        self.notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? false
        self.openOnHover = defaults.object(forKey: Keys.openOnHover) as? Bool ?? true
        self.smartAddEnabled = defaults.object(forKey: Keys.smartAdd) as? Bool ?? true
        self.tagColors = Self.load([String: Int].self, key: Keys.tagColors, in: defaults) ?? [:]
        self.wrapUpDismissedDay = defaults.string(forKey: Keys.wrapUpDismissedDay)

        self.language = defaults.string(forKey: Keys.language).flatMap(LanguageChoice.init(rawValue:)) ?? .system
        self.indicatorEnabled = defaults.object(forKey: Keys.indicatorEnabled) as? Bool ?? true
        self.indicatorShowsTimer = defaults.object(forKey: Keys.indicatorShowsTimer) as? Bool ?? true
        self.virtualNotchWidth = Self.clampNotchSize(defaults.object(forKey: Keys.virtualNotchWidth) as? Double ?? 0)
        self.virtualNotchHeight = Self.clampNotchSize(defaults.object(forKey: Keys.virtualNotchHeight) as? Double ?? 0)
        self.screenSelection = ScreenSelection(stored: defaults.string(forKey: Keys.screenSelection) ?? "automatic")
        self.panelAnchor = defaults.string(forKey: Keys.panelAnchor).flatMap(PanelAnchor.init(rawValue:)) ?? .center
        self.openDelay = Self.clampDelay(defaults.object(forKey: Keys.openDelay) as? Double ?? 0)
        self.closeDelay = Self.clampDelay(defaults.object(forKey: Keys.closeDelay) as? Double ?? 0.16)

        self.pomodoroEnabled = defaults.object(forKey: Keys.pomodoroEnabled) as? Bool ?? false
        self.focusMinutes = defaults.object(forKey: Keys.focusMinutes) as? Int ?? 25
        self.shortBreakMinutes = defaults.object(forKey: Keys.shortBreakMinutes) as? Int ?? 5
        self.longBreakMinutes = defaults.object(forKey: Keys.longBreakMinutes) as? Int ?? 15
        self.pomodoroRounds = defaults.object(forKey: Keys.pomodoroRounds) as? Int ?? 4
        self.focusSound = defaults.object(forKey: Keys.focusSound) as? Bool ?? true
        self.focusNotifications = defaults.object(forKey: Keys.focusNotifications) as? Bool ?? false
    }

    var anyReminderEnabled: Bool {
        notificationsEnabled && (wrapUp.isEnabled || morning.isEnabled || afternoon.isEnabled)
    }

    func slot(for kind: ReminderKind) -> ReminderSlot {
        switch kind {
        case .morning: return morning
        case .afternoon: return afternoon
        case .wrapUp: return wrapUp
        }
    }

    // MARK: - Wrap-up prompt

    func isWrapUpDismissed(dayKey: String) -> Bool {
        wrapUpDismissedDay == dayKey
    }

    func dismissWrapUp(dayKey: String) {
        wrapUpDismissedDay = dayKey
    }

    // MARK: - Tag colors

    func tagColorIndex(for tag: String) -> Int {
        tagColors[tag] ?? TagPalette.defaultIndex(for: tag)
    }

    func setTagColor(_ tag: String, index: Int) {
        tagColors[tag] = ((index % TagPalette.count) + TagPalette.count) % TagPalette.count
    }

    func cycleTagColor(_ tag: String) {
        setTagColor(tag, index: tagColorIndex(for: tag) + 1)
    }

    func removeTagColor(_ tag: String) {
        tagColors.removeValue(forKey: tag)
    }

    // MARK: - Storage

    private func store<T: Encodable>(_ value: T, for key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, in defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
