import Foundation

/// When the signature on an installed copy of the app runs out.
///
/// A free Apple ID signs an app for 7 days. The signature is a provisioning profile that Xcode puts
/// inside the app as `embedded.mobileprovision`; it carries the expiry date. Apps from the App Store
/// or TestFlight have no such file, and neither does the simulator, so everything here is optional.
public enum ProvisioningProfile {
    /// The `ExpirationDate` inside an `embedded.mobileprovision` file. The file is a signed CMS
    /// envelope around an XML property list, so the list is cut out of the raw bytes.
    public static func expirationDate(in profile: Data) -> Date? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex)
        else { return nil }
        let plist = profile[start.lowerBound..<end.upperBound]
        let object = try? PropertyListSerialization.propertyList(from: Data(plist), options: [], format: nil)
        return (object as? [String: Any])?["ExpirationDate"] as? Date
    }

    /// The expiry of the app that is running, or nil when it has no profile to read.
    public static func expirationDate(bundle: Bundle = .main) -> Date? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(in: data)
    }
}

/// What to tell the user about an expiry date.
public enum SigningExpiryPlanner {
    /// The evening before the signature runs out, when a warning is sent.
    public static let warningHour = 18

    /// Whole calendar days from today to the expiry day: 0 on the day itself, negative once past.
    public static func daysLeft(expires: Date, now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        let last = calendar.startOfDay(for: expires)
        return calendar.dateComponents([.day], from: today, to: last).day ?? 0
    }

    public static func hasExpired(expires: Date, now: Date) -> Bool { expires <= now }

    /// The day before the expiry at `warningHour`, or nil when that moment is already behind us
    /// (the Settings row still shows the date in that case).
    public static func warningDate(expires: Date, now: Date, calendar: Calendar, leadTime: TimeInterval = 60) -> Date? {
        guard expires > now else { return nil }
        let expiryDay = calendar.startOfDay(for: expires)
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: expiryDay),
              let fire = calendar.date(bySettingHour: warningHour, minute: 0, second: 0, of: dayBefore),
              fire < expires,
              fire.timeIntervalSince(now) > leadTime
        else { return nil }
        return fire
    }
}
