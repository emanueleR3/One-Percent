import Foundation

/// What the widget shows, written by the app into the shared App Group folder.
///
/// The widget cannot read the goals itself (it is a separate process with no network session), so
/// the app hands it a small, already worded snapshot: texts are in the user's language, goals are
/// the open ones in order, the numbers are today's.
struct WidgetSnapshot: Codable, Equatable {
    struct Goal: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var isTheOne: Bool
        var isInProgress: Bool
    }

    struct Texts: Codable, Equatable {
        /// "2 of 6"
        var progress: String
        /// "4 left", "All done", "No goals"
        var status: String
        /// Shown when the snapshot belongs to an earlier day.
        var newDay: String
        var streakLabel: String
    }

    /// The local calendar day this snapshot describes, `yyyy-MM-dd`.
    var day: String
    var percent: Int
    var completed: Int
    var total: Int
    var streak: Int
    var isTodayCounted: Bool
    /// Open goals first, at most six.
    var goals: [Goal]
    var texts: Texts
    var updatedAt: Date

    static let sample = WidgetSnapshot(
        day: "2026-01-01", percent: 33, completed: 2, total: 6, streak: 4, isTodayCounted: true,
        goals: [
            Goal(id: "1", title: "33% del piano", isTheOne: true, isInProgress: true),
            Goal(id: "2", title: "Scrivere al team", isTheOne: false, isInProgress: false),
            Goal(id: "3", title: "Leggere venti pagine", isTheOne: false, isInProgress: false)
        ],
        texts: Texts(progress: "2 di 6", status: "4 rimasti", newDay: "Nuovo giorno", streakLabel: "Serie"),
        updatedAt: Date()
    )
}

/// The folder the app and the widget both can read.
enum AppGroup {
    static let identifier = "group.com.example.onepercent"
    private static let fileName = "widget-snapshot.json"

    /// Inside the container's `Library` folder (the only part tools like devicectl may look into).
    static var fileURL: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        let library = container.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        return library.appendingPathComponent(fileName)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(snapshot) {
            // Readable once the phone has been unlocked after a restart (the widget draws while it is locked), never before.
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// The local calendar day as the snapshot names it.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
