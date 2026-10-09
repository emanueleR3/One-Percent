import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dependencies: AppDependencies?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dependencies = AppDependencies()
        self.dependencies = dependencies
        // The menu was built before the saved language was applied.
        OnePercentApplication.rebuildApplicationMenu()
        dependencies.notchWindowController.start()
        dependencies.reminders?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dependencies?.notchWindowController.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dependencies?.notchWindowController.showPanel()
        return true
    }
}
