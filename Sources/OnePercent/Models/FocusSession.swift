import Foundation

/// One stretch of focused work on a goal, banked when the timer stops.
struct FocusSession: Codable, Equatable, Sendable {
    var start: Date
    var seconds: TimeInterval
    /// True when it was a Pomodoro focus block rather than free-running time.
    var isPomodoro: Bool

    init(start: Date, seconds: TimeInterval, isPomodoro: Bool = false) {
        self.start = start
        self.seconds = seconds
        self.isPomodoro = isPomodoro
    }
}
