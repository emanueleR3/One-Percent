import SwiftUI
import Combine
import OnePercentCore

/// Everything the screens share: the goals, the cloud account, the chosen language.
@MainActor
final class AppModel: ObservableObject {
    /// One model per process, created on first use: a background wake-up (see `BackgroundRefresh`)
    /// may run before any screen exists, and must find the same goals and sync as the screens do.
    static let shared = AppModel()

    let store: TaskStore
    /// Nil when this build has no Supabase project (Config/Local.xcconfig): the app is then local only.
    let cloud: CloudSyncController?
    let reminders: PhoneReminders
    let signature: SignatureWatch
    let focusSettings: PhoneFocusSettings
    let focus: FocusController
    let focusAlerts: FocusBackgroundAlerts
    let liveActivity: FocusLiveActivityController
    private(set) var widgetBridge: WidgetBridge?

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

        // A timer is a start time: it keeps counting while the app is suspended or closed, so a
        // launch must never stop one (and never one that the Mac started).
        #if DEBUG
        let store = demo
            ? TaskStore(
                persistence: DemoPersistence(), dateService: nil, habitPersistence: InMemoryHabitPersistence(),
                timerRelaunch: .keepRunning, timerOrigin: InMemoryTimerOrigin()
            )
            : TaskStore(timerRelaunch: .keepRunning, timerOrigin: UserDefaultsTimerOrigin())
        #else
        let store = TaskStore(timerRelaunch: .keepRunning, timerOrigin: UserDefaultsTimerOrigin())
        #endif
        self.store = store

        // The session lives in the Keychain: the app keeps one stable identity across updates.
        // The demo shows the sign-in form even without a project; it never signs in or syncs.
        let demoProject = demo ? SupabaseConfig(url: URL(string: "https://demo.invalid")!, publishableKey: "demo") : nil
        self.cloud = (SupabaseConfig.fromBundle() ?? demoProject).map { config in
            let auth = SupabaseAuth(config: config, secrets: demo ? InMemorySecretStore() : KeychainSecretStore())
            let engine = SyncEngine(
                store: store,
                transport: SupabaseTransport(config: config, auth: auth),
                persistence: demo ? InMemorySyncStatePersistence() : FileSyncStatePersistence()
            )
            return CloudSyncController(
                auth: auth,
                engine: engine,
                realtime: SupabaseRealtime(config: config, auth: auth),
                beforeFirstSync: { SyncBackup.make() }
            )
        }
        self.reminders = PhoneReminders(store: store)
        self.signature = SignatureWatch(calendar: { store.dateService.currentCalendar })
        let focusSettings = PhoneFocusSettings()
        self.focusSettings = focusSettings
        // The end-of-block notification is scheduled for the exact moment (so it arrives while the
        // app sleeps); the controller itself only taps the phone when a block ends on screen.
        let focus = FocusController(store: store, preferences: focusSettings, scheduler: nil, onAlert: { Haptics.success() })
        self.focus = focus
        self.focusAlerts = FocusBackgroundAlerts(focus: focus, settings: focusSettings)
        self.liveActivity = FocusLiveActivityController(store: store, focus: focus, settings: focusSettings)
        applyLanguage()
        // Demo data must never reach the real widget.
        if !demo { widgetBridge = WidgetBridge(store: store) }
        #if DEBUG
        if demo { DemoData.fill(store, italian: language == .italian) }
        #endif
    }

    private func applyLanguage() {
        let resolved = language.resolve()
        Localizer.shared.setLanguage(resolved)
        store.dateService.setLocale(resolved.locale)
        reminders.languageDidChange()
        if !isDemo { Task { await signature.refresh() } }
        widgetBridge?.refresh()
    }

    /// Picks up a saved session and starts syncing.
    func start() async {
        if isDemo { return }
        reminders.start()
        await reminders.refreshAuthorization()
        await signature.refresh()
        liveActivity.reconcile()
        await cloud?.start()
    }

    /// Leaving the screen: if a timer runs (here or on the Mac), ask iOS for a quiet wake-up later
    /// to correct the clock on the Lock Screen should it be stopped elsewhere. Nothing to wake for
    /// otherwise.
    func enteredBackground() {
        if isDemo { return }
        if store.runningTimerTaskID != nil {
            BackgroundRefresh.schedule()
        } else {
            BackgroundRefresh.cancel()
        }
    }

    /// The body of a background wake-up: pull what changed, drop a forgotten timer, bring the
    /// Lock Screen clock in line, and ask for the next wake-up if a timer is still running.
    func backgroundRefresh() async {
        if isDemo { return }
        await cloud?.syncOnce()
        store.expireForgottenTimers()
        await liveActivity.reconcileNow()
        enteredBackground()
    }

    /// Back on screen: a new day may have begun, and the other devices may have changed things.
    func becameActive() {
        if isDemo { return }
        store.dateService.refreshToday()
        store.ensureHabitOccurrences()
        store.expireForgottenTimers()
        focus.restoreFromStore()
        focus.tick()   // a block may have ended while the app slept
        liveActivity.reconcile()
        reminders.scheduleRefresh()
        Task { await signature.refresh() }
        if let cloud { Task { await cloud.syncNow() } }
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
