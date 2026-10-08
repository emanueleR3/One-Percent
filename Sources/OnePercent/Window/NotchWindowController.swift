import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class NotchWindowController {
    private let positionResolver = NotchPositionResolver()
    private let hoverMonitor = HoverMonitor()
    private var panel: NotchPanel?
    private var notificationTokens: [NSObjectProtocol] = []
    private var visibilityGeneration = 0

    func start() {
        configurePanelIfNeeded()
        hoverMonitor.onShow = { [weak self] in
            self?.showPanel()
        }
        hoverMonitor.onHide = { [weak self] in
            self?.hidePanel()
        }
        installScreenObservers()
        refreshGeometry()
        hoverMonitor.start()
    }

    func stop() {
        hoverMonitor.stop()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        panel?.orderOut(nil)
    }

    private func configurePanelIfNeeded() {
        guard panel == nil else {
            return
        }

        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: NotchPositionResolver.preferredPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: IslandView())
        panel.orderOut(nil)
        self.panel = panel
    }

    private func installScreenObservers() {
        guard notificationTokens.isEmpty else {
            return
        }

        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshGeometry()
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshGeometry()
                }
            }
        )
    }

    private func refreshGeometry() {
        guard let panel, let geometry = positionResolver.resolve() else {
            return
        }

        panel.setFrame(geometry.expandedFrame, display: false)
        hoverMonitor.update(
            activationRect: geometry.activationRect,
            interactiveRect: geometry.expandedFrame.insetBy(dx: -2, dy: -2)
        )
    }

    private func showPanel() {
        refreshGeometry()
        guard let panel else {
            return
        }

        visibilityGeneration += 1
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        animate(panel: panel, toAlpha: 1, duration: 0.2, completion: nil)
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else {
            return
        }

        visibilityGeneration += 1
        let generation = visibilityGeneration
        animate(panel: panel, toAlpha: 0, duration: 0.16) { [weak self, weak panel] in
            guard let self, let panel, self.visibilityGeneration == generation else {
                return
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func animate(panel: NSPanel, toAlpha alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)?) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = alpha
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            completion?()
        }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
