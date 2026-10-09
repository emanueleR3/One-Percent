import AppKit

/// Menu bar status item controller per ONE_PERCENT_SPEC.md (Section 13)
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var notchWindowController: NotchWindowController?
    private let preferences: AppPreferences
    private let menu = NSMenu()
    private var toggleVisibilityMenuItem: NSMenuItem?
    private var hoverToggleMenuItem: NSMenuItem?

    init(notchWindowController: NotchWindowController, preferences: AppPreferences) {
        self.notchWindowController = notchWindowController
        self.preferences = preferences
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "percent",
                accessibilityDescription: "One Percent"
            )
            button.imagePosition = .imageOnly
        }

        menu.delegate = self
        buildMenu()
        item.menu = menu
        self.statusItem = item
    }

    private func buildMenu() {
        menu.removeAllItems()

        let toggleItem = NSMenuItem(
            title: isPanelVisible ? L("Hide One Percent") : L("Show One Percent"),
            action: #selector(togglePanelAction),
            keyEquivalent: "o"
        )
        toggleItem.target = self
        self.toggleVisibilityMenuItem = toggleItem
        menu.addItem(toggleItem)

        let isHoverEnabled = preferences.openOnHover
        let hoverItem = NSMenuItem(
            title: L("Open on Hover"),
            action: #selector(toggleHoverAction),
            keyEquivalent: ""
        )
        hoverItem.target = self
        hoverItem.state = isHoverEnabled ? .on : .off
        self.hoverToggleMenuItem = hoverItem
        menu.addItem(hoverItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: L("Quit One Percent"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)
    }

    private var isPanelVisible: Bool {
        notchWindowController?.isPanelVisible ?? false
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Titles are rebuilt on every open so a language change shows up at once.
        buildMenu()
        toggleVisibilityMenuItem?.title = isPanelVisible ? L("Hide One Percent") : L("Show One Percent")
        hoverToggleMenuItem?.state = preferences.openOnHover ? .on : .off
    }

    @objc private func togglePanelAction() {
        notchWindowController?.togglePanel()
    }

    @objc private func toggleHoverAction() {
        preferences.openOnHover.toggle()
        hoverToggleMenuItem?.state = preferences.openOnHover ? .on : .off
    }
}
