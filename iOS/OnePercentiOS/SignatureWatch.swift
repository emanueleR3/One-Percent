import Foundation
import UserNotifications
import OnePercentCore

/// Knows when this copy of the app stops opening, and warns the evening before.
///
/// A free Apple ID signs the app for 7 days (the Mac renews it by itself, see
/// `Scripts/iphone-autorefresh.sh`). The date is read from the profile inside the app, so it is
/// the real one, and the warning is a local notification rebuilt every time the app opens: once
/// the signature has been renewed, the next launch moves the warning to the new date.
@MainActor
final class SignatureWatch: ObservableObject {
    static let identifier = "onepercent.signature"

    /// Nil for a copy without a profile (the simulator, the App Store): there is nothing to show.
    @Published private(set) var expires: Date?
    @Published var warnsBefore: Bool {
        didSet {
            defaults.set(warnsBefore, forKey: Keys.warns)
            Task { await refresh() }
        }
    }

    private enum Keys { static let warns = "signatureWarning" }

    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private let calendar: () -> Calendar

    init(bundle: Bundle = .main, calendar: @escaping () -> Calendar) {
        self.expires = ProvisioningProfile.expirationDate(bundle: bundle)
        self.warnsBefore = defaults.object(forKey: Keys.warns) as? Bool ?? true
        self.calendar = calendar
    }

    var daysLeft: Int? {
        expires.map { SigningExpiryPlanner.daysLeft(expires: $0, now: Date(), calendar: calendar()) }
    }

    /// True from the last day: the row in Settings turns orange.
    var isClose: Bool { daysLeft.map { $0 <= 1 } ?? false }

    /// Re-reads nothing from disk (the profile only changes with a reinstall, which restarts the
    /// app); it rebuilds the warning from the current date, wording and permission.
    func refresh() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard warnsBefore, let expires else { return }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized else { return }

        let calendar = calendar()
        guard let fire = SigningExpiryPlanner.warningDate(expires: expires, now: Date(), calendar: calendar) else { return }

        let message = UNMutableNotificationContent()
        message.title = L("One Percent stops opening soon")
        let time = LocalizedDates.string(expires, template: "jm", calendar: calendar)
        message.body = L("Its signature runs out tomorrow at %@. The Mac renews it by itself; if it has not, plug the iPhone in and run install-iphone.sh.", time)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: message,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        try? await center.add(request)
    }
}
