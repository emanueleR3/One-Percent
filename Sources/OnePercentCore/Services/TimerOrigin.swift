import Foundation

/// What a running timer does when the app starts again.
public enum TimerRelaunchPolicy: Sendable {
    /// Stop it and credit the time up to its last checkpoint. For a Mac: if the app was off or the
    /// computer asleep, nothing was being worked on meanwhile.
    case creditToLastCheckpoint
    /// Keep it running. A timer is a start time, not a ticking counter, and a phone app is
    /// routinely suspended or closed while the user keeps studying.
    case keepRunning
}

/// The one running timer that was started on this device, remembered across launches.
///
/// A timer started elsewhere reaches this device through sync and is not ours to stop: only the
/// device that ran it knows whether it was interrupted. Without this, a device relaunched after
/// hours would "recover" a timer it never ran and send the stop to everyone else.
public struct LocalTimerMarker: Codable, Equatable, Sendable {
    public var taskID: UUID
    public var startedAt: Date

    public init(taskID: UUID, startedAt: Date) {
        self.taskID = taskID
        self.startedAt = startedAt
    }
}

public protocol TimerOriginStoring: AnyObject {
    func load() -> LocalTimerMarker?
    func save(_ marker: LocalTimerMarker?)
}

public final class InMemoryTimerOrigin: TimerOriginStoring {
    private var marker: LocalTimerMarker?

    public init() {}

    public func load() -> LocalTimerMarker? { marker }
    public func save(_ marker: LocalTimerMarker?) { self.marker = marker }
}

/// Keeps the marker in `UserDefaults`, next to the app's other small settings.
public final class UserDefaultsTimerOrigin: TimerOriginStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "onepercent.localTimerMarker") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> LocalTimerMarker? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LocalTimerMarker.self, from: $0) }
    }

    public func save(_ marker: LocalTimerMarker?) {
        if let marker, let data = try? JSONEncoder().encode(marker) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
