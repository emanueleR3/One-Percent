import AppKit
import SwiftUI
import Combine
import OnePercentCore

/// What the virtual notch view needs, updated whenever the display or the settings change.
@MainActor
final class NotchIndicatorModel: ObservableObject {
    @Published var layout: VirtualNotchLayout?
}

/// A borderless window may reach past the top of the screen, so the black shape can bleed over the
/// very edge instead of leaving a hairline.
private final class VirtualNotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The virtual notch: a black notch centred on the real one, wider than it, so the hardware covers
/// the middle and the two sides show today's progress or the running timer while the panel is
/// closed. Click-through: the activation window under it still opens the panel on hover or click.
@MainActor
final class NotchIndicatorController {
    private let model = NotchIndicatorModel()
    private let store: TaskStore
    private let focus: FocusController
    private let preferences: AppPreferences
    private var window: NSPanel?

    init(store: TaskStore, focus: FocusController, preferences: AppPreferences) {
        self.store = store
        self.focus = focus
        self.preferences = preferences
    }

    /// Places (or hides) the virtual notch. Returns the whole visible notch, which counts as part
    /// of the real one for hovering, or nil when it is off.
    @discardableResult
    func update(geometry: NotchGeometry?) -> NSRect? {
        guard preferences.indicatorEnabled, let geometry else {
            window?.orderOut(nil)
            return nil
        }

        let panel = window ?? makeWindow()
        let layout = VirtualNotchLayout.make(
            for: geometry,
            width: preferences.virtualNotchWidth,
            height: preferences.virtualNotchHeight,
            backingScale: panel.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        )
        model.layout = layout
        panel.setFrame(layout.frame, display: true)
        panel.orderFrontRegardless()
        return layout.visibleRect
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = VirtualNotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(
            rootView: NotchIndicatorView(model: model, store: store, focus: focus, preferences: preferences)
        )
        window = panel
        return panel
    }
}
