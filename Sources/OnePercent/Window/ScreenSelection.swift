import AppKit
import CoreGraphics
import OnePercentCore

/// Which display hosts the notch panel.
enum ScreenSelection: Equatable, Sendable {
    /// The built-in display (it has the notch), else the one with the menu bar.
    case automatic
    /// Always the display that has the menu bar.
    case main
    /// A specific display, by its stable UUID.
    case display(String)

    /// Compact form kept in `UserDefaults`.
    init(stored: String) {
        switch stored {
        case "", "automatic": self = .automatic
        case "main": self = .main
        default: self = .display(stored)
        }
    }

    var stored: String {
        switch self {
        case .automatic: return "automatic"
        case .main: return "main"
        case .display(let id): return id
        }
    }
}

struct ScreenDescriptor: Equatable, Sendable {
    let id: String
    let isBuiltIn: Bool
    let isMenuBarScreen: Bool
}

/// Pure choice of display, so it can be tested without monitors attached.
enum ScreenChooser {
    static func choose(from screens: [ScreenDescriptor], selection: ScreenSelection) -> String? {
        guard !screens.isEmpty else { return nil }

        func automatic() -> String? {
            screens.first(where: \.isBuiltIn)?.id
                ?? screens.first(where: \.isMenuBarScreen)?.id
                ?? screens.first?.id
        }

        switch selection {
        case .automatic:
            return automatic()
        case .main:
            return screens.first(where: \.isMenuBarScreen)?.id ?? automatic()
        case .display(let id):
            // An unplugged display falls back to the automatic choice instead of hiding the app.
            return screens.contains(where: { $0.id == id }) ? id : automatic()
        }
    }
}

/// What Settings lists when offering a display.
struct DisplayInfo: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let hasNotch: Bool
}

extension NSScreen {
    /// Survives reconnecting the monitor, unlike `CGDirectDisplayID`.
    var stableDisplayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

enum DisplayCatalog {
    @MainActor
    static func connected() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.stableDisplayID else { return nil }
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(CGDirectDisplayID(number)) != 0,
                hasNotch: screen.safeAreaInsets.top > 0
            )
        }
    }
}
