import BackgroundTasks
import Foundation

/// A short, invisible wake-up while a timer runs, so the Lock Screen / Dynamic Island clock can be
/// corrected when the timer was stopped somewhere else (the Mac) while this app was asleep.
///
/// It never opens the app or shows anything: iOS starts the process in the background for a few
/// seconds, the app pulls the latest state and updates the activity, and it goes back to sleep.
/// iOS alone decides when (it rations these wake-ups by battery, network and how often the app is
/// used), so this is best effort: minutes to hours, never instant. It works with a free account.
enum BackgroundRefresh {
    static let identifier = "com.example.onepercent.refresh"

    /// How soon the system may run it at the earliest.
    private static let earliest: TimeInterval = 15 * 60

    /// Must be called before the app finishes launching.
    static func register(run: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            let work = Task { @MainActor in
                await run()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// Asks for the next wake-up. Replaces any earlier request.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliest)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Nothing is timing: no reason to wake the phone.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}
