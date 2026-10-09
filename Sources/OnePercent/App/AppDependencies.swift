import Foundation
import Combine

@MainActor
final class AppDependencies {
    let dateService: DateService
    let persistenceController: PersistenceController
    let taskStore: TaskStore
    let preferences: AppPreferences
    let services: IslandServices
    let notchWindowController: NotchWindowController
    let menuBarController: MenuBarController

    private var cancellables = Set<AnyCancellable>()

    var reminders: ReminderCoordinator? { services.reminders }

    private static func apply(language: AppLanguage, to dateService: DateService) {
        Localizer.shared.setLanguage(language)
        dateService.setLocale(language.locale)
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
            habitPersistence: HabitPersistenceController()
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

        let services = IslandServices(
            preferences: preferences,
            reminders: reminders,
            launchAtLogin: LaunchAtLoginController(),
            smartAdd: SmartAddService(),
            focus: FocusController(store: store, preferences: preferences, scheduler: notifications)
        )
        self.services = services

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
