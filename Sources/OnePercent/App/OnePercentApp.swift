import AppKit
import OnePercentCore

/// AppKit owns the application lifecycle so launch never creates a conventional SwiftUI
/// window. SwiftUI is used only inside the dedicated notch panel.
@main
@MainActor
final class OnePercentApplication: NSObject {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        configureApplicationMenu(for: application)
        configureApplicationIcon(for: application)
        application.run()
    }

    /// Rebuilds the app menu so its titles follow the language chosen in Settings.
    static func rebuildApplicationMenu() {
        configureApplicationMenu(for: NSApplication.shared)
    }

    private static func configureApplicationMenu(for application: NSApplication) {
        let mainMenu = NSMenu()

        // 1. Application Menu ("One Percent")
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu(title: L("One Percent"))
        let aboutItem = NSMenuItem(
            title: L("About One Percent"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = application
        applicationMenu.addItem(aboutItem)
        applicationMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: L("Quit One Percent"),
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
        let editMenu = NSMenu(title: L("Edit"))

        let undoItem = NSMenuItem(
            title: L("Undo"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: L("Redo"),
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(redoItem)

        editMenu.addItem(NSMenuItem.separator())

        let cutItem = NSMenuItem(
            title: L("Cut"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(
            title: L("Copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(
            title: L("Paste"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(
            title: L("Select All"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(selectAllItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        application.mainMenu = mainMenu
    }

    private static func configureApplicationIcon(for application: NSApplication) {
        if let icon = loadAppIcon() {
            application.applicationIconImage = icon
        }
    }

    private static func loadAppIcon() -> NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }

        let possiblePaths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns").path,
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.icns").path,
            "Resources/AppIcon.icns",
            "Resources/AppIcon.png"
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let icon = NSImage(contentsOfFile: path) {
                return icon
            }
        }
        return nil
    }
}
