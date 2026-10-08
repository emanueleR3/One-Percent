import Foundation

@MainActor
final class AppDependencies {
    let dateService: DateService
    let persistenceController: PersistenceController
    let taskStore: TaskStore
    let notchWindowController: NotchWindowController
    let menuBarController: MenuBarController

    init(
        persistenceController: PersistenceController = PersistenceController(),
        dateService: DateService? = nil
    ) {
        let dateSvc = dateService ?? DateService()
        self.dateService = dateSvc
        self.persistenceController = persistenceController
        let store = TaskStore(persistence: persistenceController, dateService: dateSvc)
        self.taskStore = store
        let windowController = NotchWindowController(taskStore: store)
        self.notchWindowController = windowController
        self.menuBarController = MenuBarController(notchWindowController: windowController)
    }
}
