import Foundation

/// Dates written in the language chosen in Settings (not the macOS one), using each language's own
/// word order: "Fri, Oct 9" in English, "ven 9 ott" in Italian.
enum LocalizedDates {
    private static let lock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    /// `template` is a `setLocalizedDateFormatFromTemplate` skeleton such as "EEEMMMd".
    static func string(_ date: Date, template: String, calendar: Calendar = .current) -> String {
        let locale = calendar.locale ?? Localizer.shared.language.locale
        let key = "\(locale.identifier)|\(template)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[key] { return cached.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter.string(from: date)
    }
}
