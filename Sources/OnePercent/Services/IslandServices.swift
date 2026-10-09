import Foundation
import OnePercentCore

/// Everything the panel needs besides the task store, bundled so views take one parameter.
@MainActor
struct IslandServices {
    let preferences: AppPreferences
    /// Nil when not running as an app bundle (tests, `swift run`): notifications need a bundle.
    let reminders: ReminderCoordinator?
    let launchAtLogin: LaunchAtLoginController
    let smartAdd: SmartAddService
    /// Focus timer and Pomodoro.
    let focus: FocusController
    /// Cloud sync with the other devices. Nil when not running as an app bundle (tests, `swift run`).
    var cloud: CloudSyncController? = nil
}
