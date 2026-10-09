import AppKit
import OnePercentCore

/// Pauses the timer when the Mac goes to sleep or the screen locks, so the hours the lid was closed
/// are not counted as work.
@MainActor
final class FocusSleepGuard {
    private var observers: [NSObjectProtocol] = []

    init(focus: FocusController) {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak focus] _ in
                Task { @MainActor [weak focus] in focus?.systemWillSleep() }
            })
        }
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
