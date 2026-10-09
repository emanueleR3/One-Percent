import Foundation
import Combine

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
    }

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
