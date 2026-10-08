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

        // 1. Application Menu ("One Percent")
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

        // 2. Edit Menu ("Edit")
        // Required for macOS responder chain to route ⌘X (Cut), ⌘C (Copy), ⌘V (Paste), ⌘A (Select All), ⌘Z (Undo)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(redoItem)

        editMenu.addItem(NSMenuItem.separator())

        let cutItem = NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(selectAllItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        application.mainMenu = mainMenu
    }
}
