import Foundation

/// The two reasons the panel must not close on its own: someone is typing in it, or a menu is open.
struct InteractionLock: Equatable {
    /// A text field needs the keyboard (adding a goal, a note...). The panel also takes focus.
    var keyboard = false
    /// Menus being tracked right now; more than one when a submenu is open.
    var menuTrackingDepth = 0

    var isKeyboardLocked: Bool { keyboard }
    var isMenuHolding: Bool { menuTrackingDepth > 0 }

    mutating func menuDidBeginTracking() {
        menuTrackingDepth += 1
    }

    mutating func menuDidEndTracking() {
        menuTrackingDepth = max(0, menuTrackingDepth - 1)
    }
}
