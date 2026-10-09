import Foundation

/// One stretch of focused work on a goal, banked when the timer stops.
public struct FocusSession: Codable, Equatable, Sendable {
    public var start: Date
    public var seconds: TimeInterval
    /// True when it was a Pomodoro focus block rather than free-running time.
    public var isPomodoro: Bool

    public init(start: Date, seconds: TimeInterval, isPomodoro: Bool = false) {
        self.start = start
        self.seconds = seconds
        self.isPomodoro = isPomodoro
    }
}
