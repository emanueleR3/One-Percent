import ActivityKit
import Foundation

/// The timer on the Lock Screen and in the Dynamic Island.
///
/// Nothing here has to be updated once a second: the clock is drawn by the system from a date
/// (`Text(date, style: .timer)`), so it keeps running while the app is suspended or closed. The app
/// only writes a new state when something changes: started, paused, resumed, a break begins, stopped.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Kind: String, Codable, Hashable {
            /// Counts up from `start`.
            case stopwatch
            /// Counts down from `start` to `end`.
            case countdown
            /// Frozen at `frozen` seconds.
            case paused
        }

        var kind: Kind
        /// Already localized in the app's language: "Focus 2 of 4", "Break", "Paused".
        var label: String
        var start: Date
        var end: Date?
        var frozen: TimeInterval?
        var isBreak: Bool
    }

    /// The goal's title. A different goal is a different activity.
    var title: String
}
