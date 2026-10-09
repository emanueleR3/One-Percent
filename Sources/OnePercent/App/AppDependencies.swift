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

        // System notifications need a real app bundle; a bare `swift run` binary has none.
        let reminders: ReminderCoordinator? = Bundle.main.bundleURL.pathExtension == "app"
            ? ReminderCoordinator(store: store, preferences: preferences, scheduler: SystemNotificationCenter())
            : nil

        let services = IslandServices(
            preferences: preferences,
            reminders: reminders,
            launchAtLogin: LaunchAtLoginController(),
            smartAdd: SmartAddService()
        )
        self.services = services

        let windowController = NotchWindowController(taskStore: store, services: services)
        self.notchWindowController = windowController
        self.menuBarController = MenuBarController(notchWindowController: windowController, preferences: preferences)

        reminders?.onOpenRequested = { [weak windowController] in
            windowController?.showPanel()
        }

        // Preferences are the single source of truth for "open on hover"; the menu item and the
        // settings page both write to it.
        preferences.$openOnHover
            .sink { [weak windowController] enabled in
                windowController?.isHoverEnabled = enabled
            }
            .store(in: &cancellables)
    }
}
