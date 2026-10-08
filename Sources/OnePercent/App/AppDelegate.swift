import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dependencies: AppDependencies?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dependencies = AppDependencies()
        self.dependencies = dependencies
        dependencies.notchWindowController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dependencies?.notchWindowController.stop()
    }
}
