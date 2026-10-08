import AppKit

/// AppKit owns the application lifecycle so launch never creates a conventional SwiftUI
/// window. SwiftUI is used only inside the dedicated notch panel.
@main
@MainActor
final class OnePercentApplication: NSObject {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.regular)
        configureApplicationMenu(for: application)
        application.run()
    }

    private static func configureApplicationMenu(for application: NSApplication) {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "One Percent")
        let quitItem = NSMenuItem(
            title: "Quit One Percent",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = application
        applicationMenu.addItem(quitItem)
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        application.mainMenu = mainMenu
    }
}
