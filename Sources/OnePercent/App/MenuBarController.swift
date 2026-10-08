import AppKit

/// Menu bar status item controller per ONE_PERCENT_SPEC.md (Section 13)
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var notchWindowController: NotchWindowController?
    private let menu = NSMenu()
    private var toggleVisibilityMenuItem: NSMenuItem?
    private var hoverToggleMenuItem: NSMenuItem?

    init(notchWindowController: NotchWindowController) {
        self.notchWindowController = notchWindowController
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
            title: isPanelVisible ? "Hide One Percent" : "Show One Percent",
            action: #selector(togglePanelAction),
            keyEquivalent: "o"
        )
        toggleItem.target = self
        self.toggleVisibilityMenuItem = toggleItem
        menu.addItem(toggleItem)

        let isHoverEnabled = notchWindowController?.isHoverEnabled ?? true
        let hoverItem = NSMenuItem(
            title: "Open on Hover",
            action: #selector(toggleHoverAction),
            keyEquivalent: ""
        )
        hoverItem.target = self
        hoverItem.state = isHoverEnabled ? .on : .off
        self.hoverToggleMenuItem = hoverItem
        menu.addItem(hoverItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit One Percent",
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
        toggleVisibilityMenuItem?.title = isPanelVisible ? "Hide One Percent" : "Show One Percent"
        hoverToggleMenuItem?.state = (notchWindowController?.isHoverEnabled ?? true) ? .on : .off
    }

    @objc private func togglePanelAction() {
        notchWindowController?.togglePanel()
    }

    @objc private func toggleHoverAction() {
        guard let controller = notchWindowController else { return }
        controller.isHoverEnabled.toggle()
        hoverToggleMenuItem?.state = controller.isHoverEnabled ? .on : .off
    }
}
