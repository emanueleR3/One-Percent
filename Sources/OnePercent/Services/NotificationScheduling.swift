import Foundation
import UserNotifications

enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// One reminder, as plain data: what to say and when.
struct ReminderRequest: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var fireDate: Date
    /// Wrap-up reminders carry a "Move to tomorrow" action.
    var isWrapUp: Bool
}

/// The slice of `UNUserNotificationCenter` the app needs, so scheduling can be tested with a fake.
@MainActor
protocol NotificationScheduling: AnyObject {
    var onMoveToTomorrow: (() -> Void)? { get set }
    var onOpenRequested: (() -> Void)? { get set }

    func start()
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func removePending(ids: [String])
    func schedule(_ request: ReminderRequest, calendar: Calendar) async
}

/// Real implementation on top of the system notification center.
@MainActor
final class SystemNotificationCenter: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    var onMoveToTomorrow: (() -> Void)?
    var onOpenRequested: (() -> Void)?

    private static let categoryID = "ONEPERCENT_WRAPUP"
    private static let moveActionID = "ONEPERCENT_MOVE_TO_TOMORROW"
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func start() {
        center.delegate = self
        let move = UNNotificationAction(identifier: Self.moveActionID, title: "Move to tomorrow", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [move],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    func removePending(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func schedule(_ request: ReminderRequest, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = nil
        if request.isWrapUp { content.categoryIdentifier = Self.categoryID }

        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await MainActor.run {
            if action == Self.moveActionID {
                onMoveToTomorrow?()
            } else if action == UNNotificationDefaultActionIdentifier {
                onOpenRequested?()
            }
        }
    }
}
