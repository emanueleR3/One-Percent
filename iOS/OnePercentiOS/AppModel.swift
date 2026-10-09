import SwiftUI
import Combine
import OnePercentCore

/// Everything the screens share: the goals, the cloud account, the chosen language.
@MainActor
final class AppModel: ObservableObject {
    let store: TaskStore
    let cloud: CloudSyncController
    let reminders: PhoneReminders

    @Published var language: LanguageChoice {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            applyLanguage()
        }
    }
    @Published private(set) var tagColors: [String: Int]

    private enum Keys {
        static let language = "language"
        static let tagColors = "tagColors"
    }

    private let defaults = UserDefaults.standard

    /// Development builds only: `-demo` runs on throwaway sample data that is never saved or synced.
    let isDemo: Bool

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        let demo = false
        #endif
        self.isDemo = demo

        let language = demo
            ? (ProcessInfo.processInfo.arguments.contains("-demoItalian") ? LanguageChoice.italian : .english)
            : (defaults.string(forKey: Keys.language).flatMap(LanguageChoice.init(rawValue:)) ?? .system)
        self.language = language
        self.tagColors = demo ? [:] : (defaults.data(forKey: Keys.tagColors)).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]

        #if DEBUG
        let store = demo
            ? TaskStore(persistence: DemoPersistence(), dateService: nil, habitPersistence: InMemoryHabitPersistence())
            : TaskStore()
        #else
        let store = TaskStore()
        #endif
        self.store = store

        // The session lives in the Keychain: the app keeps one stable identity across updates.
        let auth = SupabaseAuth(secrets: demo ? InMemorySecretStore() : KeychainSecretStore())
        let engine = SyncEngine(
            store: store,
            transport: SupabaseTransport(auth: auth),
            persistence: demo ? InMemorySyncStatePersistence() : FileSyncStatePersistence()
        )
        self.cloud = CloudSyncController(
            auth: auth,
            engine: engine,
            realtime: SupabaseRealtime(auth: auth),
            beforeFirstSync: { SyncBackup.make() }
        )
        self.reminders = PhoneReminders(store: store)
        applyLanguage()
        #if DEBUG
        if demo { DemoData.fill(store) }
        #endif
    }

    private func applyLanguage() {
        let resolved = language.resolve()
        Localizer.shared.setLanguage(resolved)
        store.dateService.setLocale(resolved.locale)
        reminders.languageDidChange()
    }

    /// Picks up a saved session and starts syncing.
    func start() async {
        if isDemo { return }
        reminders.start()
        await reminders.refreshAuthorization()
        await cloud.start()
    }

    /// Back on screen: a new day may have begun, and the other devices may have changed things.
    func becameActive() {
        if isDemo { return }
        store.dateService.refreshToday()
        store.ensureHabitOccurrences()
        reminders.scheduleRefresh()
        Task { await cloud.syncNow() }
    }

    // MARK: Tag colors

    func tagColor(_ tag: String) -> Color {
        TagColors.color(at: tagColors[tag] ?? TagColors.defaultIndex(for: tag))
    }

    func cycleTagColor(_ tag: String) {
        tagColors[tag] = ((tagColors[tag] ?? TagColors.defaultIndex(for: tag)) + 1) % TagColors.colors.count
        saveTagColors()
    }

    func forgetTagColor(_ tag: String) {
        tagColors[tag] = nil
        saveTagColors()
    }

    private func saveTagColors() {
        if let data = try? JSONEncoder().encode(tagColors) { defaults.set(data, forKey: Keys.tagColors) }
    }
}
