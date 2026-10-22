import Foundation
import AppKit
import Combine
import OnePercentCore

@MainActor
final class AppDependencies {
    let dateService: DateService
    let persistenceController: PersistenceController
    let taskStore: TaskStore
    let preferences: AppPreferences
    let services: IslandServices
    let notchWindowController: NotchWindowController
    let menuBarController: MenuBarController
    private let focusSleepGuard: FocusSleepGuard

    private var cancellables = Set<AnyCancellable>()

    var reminders: ReminderCoordinator? { services.reminders }

    private static func apply(language: AppLanguage, to dateService: DateService) {
        Localizer.shared.setLanguage(language)
        dateService.setLocale(language.locale)
    }

    private static func makeCloudSync(store: TaskStore, config: SupabaseConfig) -> CloudSyncController {
        // The session lives in a private file: an ad-hoc signed app would get a Keychain prompt on every update.
        let auth = SupabaseAuth(config: config, secrets: FileSecretStore())
        let engine = SyncEngine(
            store: store,
            transport: SupabaseTransport(config: config, auth: auth),
            persistence: FileSyncStatePersistence()
        )
        return CloudSyncController(
            auth: auth,
            engine: engine,
            realtime: SupabaseRealtime(config: config, auth: auth),
            // Copy the goal and habit files before this Mac first merges with the cloud.
            beforeFirstSync: { SyncBackup.make() }
        )
    }

    init(
        persistenceController: PersistenceController = PersistenceController(),
        dateService: DateService? = nil
    ) {
        let dateSvc = dateService ?? DateService()
        self.dateService = dateSvc
        self.persistenceController = persistenceController
        let store = TaskStore(
            persistence: persistenceController,
            dateService: dateSvc,
            habitPersistence: HabitPersistenceController(),
            // A timer left running when the app stopped is credited up to its last checkpoint, but
            // only if this Mac started it: one that arrived from the phone is not ours to stop.
            timerRelaunch: .creditToLastCheckpoint,
            timerOrigin: UserDefaultsTimerOrigin()
        )
        self.taskStore = store

        let preferences = AppPreferences()
        self.preferences = preferences
        Self.apply(language: preferences.resolvedLanguage(), to: dateSvc)

        // System notifications need a real app bundle; a bare `swift run` binary has none. One
        // center serves both the daily reminders and the focus alerts.
        let notifications: SystemNotificationCenter? = Bundle.main.bundleURL.pathExtension == "app"
            ? SystemNotificationCenter()
            : nil
        let reminders = notifications.map {
            ReminderCoordinator(store: store, preferences: preferences, scheduler: $0)
        }

        // Cloud sync talks to the real server, so (like notifications) it only runs in the app bundle,
        // and only when the build was given a Supabase project (Config/Local.xcconfig).
        let cloud: CloudSyncController? = Bundle.main.bundleURL.pathExtension == "app"
            ? SupabaseConfig.fromBundle().map { Self.makeCloudSync(store: store, config: $0) }
            : nil

        let focus = FocusController(
            store: store,
            preferences: preferences,
            scheduler: notifications,
            playSound: { name in NSSound(named: NSSound.Name(name))?.play() },
            onAlert: { IslandHaptics.success() }
        )
        self.focusSleepGuard = FocusSleepGuard(focus: focus)

        let services = IslandServices(
            preferences: preferences,
            reminders: reminders,
            launchAtLogin: LaunchAtLoginController(),
            smartAdd: SmartAddService(),
            focus: focus,
            cloud: cloud
        )
        self.services = services
        // A session saved by an earlier run starts syncing right away.
        if let cloud { Task { await cloud.start() } }

        let windowController = NotchWindowController(taskStore: store, services: services)
        self.notchWindowController = windowController
        self.menuBarController = MenuBarController(notchWindowController: windowController, preferences: preferences)

        reminders?.onOpenRequested = { [weak windowController] in
            windowController?.showPanel()
        }

        // The language is picked in Settings and applies at once: texts, dates, both menus and the
        // pending reminders all follow.
        preferences.$language
            .dropFirst()
            .sink { [weak dateSvc] choice in
                // `@Published` emits before the property changes, so use the value it hands over.
                guard let dateSvc else { return }
                Self.apply(language: choice.resolve(), to: dateSvc)
                OnePercentApplication.rebuildApplicationMenu()
                reminders?.languageDidChange()
            }
            .store(in: &cancellables)

        // Preferences are the single source of truth for "open on hover"; the menu item and the
        // settings page both write to it.
        preferences.$openOnHover
            .sink { [weak windowController] enabled in
                windowController?.isHoverEnabled = enabled
            }
            .store(in: &cancellables)
    }
}
