import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class NotchWindowController {
    let taskStore: TaskStore
    private let positionResolver = NotchPositionResolver()
    private let hoverMonitor = HoverMonitor()
    private var panel: NotchPanel?
    private var activationWindow: NSWindow?
    private var notificationTokens: [NSObjectProtocol] = []
    private var visibilityGeneration = 0
    private var currentPanelHeight: CGFloat = IslandMetrics.minPanelHeight

    private let presentationState = IslandPresentationState()

    var isHoverEnabled: Bool {
        get { hoverMonitor.isEnabled }
        set { hoverMonitor.isEnabled = newValue }
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true && presentationState.isExpanded
    }

    init(taskStore: TaskStore) {
        self.taskStore = taskStore
    }

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
        activationWindow?.orderOut(nil)
        activationWindow = nil
        panel?.orderOut(nil)
    }

    func setInteractionLocked(_ locked: Bool) {
        hoverMonitor.setInteractionLocked(locked)
        if locked {
            activateForInput()
        }
    }

    func activateForInput() {
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
    }

    func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        taskStore.dateService.refreshToday()
        refreshGeometry()
        guard let panel else {
            return
        }

        hoverMonitor.forceExpanded()
        visibilityGeneration += 1
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        withAnimation(IslandAnimations.dropletExpandSpring) {
            presentationState.isExpanded = true
        }
    }

    func hidePanel() {
        guard let panel, panel.isVisible else {
            return
        }

        visibilityGeneration += 1
        let generation = visibilityGeneration

        withAnimation(IslandAnimations.dropletCollapseSpring) {
            presentationState.isExpanded = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + IslandAnimations.hideDuration) { [weak self, weak panel] in
            guard let self, let panel, self.visibilityGeneration == generation else {
                return
            }
            panel.orderOut(nil)
            self.hoverMonitor.forceClosed()
        }
    }

    func updateContentHeight(_ newHeight: CGFloat) {
        let clamped = min(IslandMetrics.maxPanelHeight, max(IslandMetrics.minPanelHeight, newHeight))
        guard abs(currentPanelHeight - clamped) > 1 else { return }
        currentPanelHeight = clamped
        refreshGeometry(animated: panel?.isVisible == true)
    }

    private func configurePanelIfNeeded() {
        guard panel == nil else {
            return
        }

        let initialSize = NSSize(width: IslandMetrics.panelWidth, height: currentPanelHeight)
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
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
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(
            rootView: IslandView(
                store: taskStore,
                presentationState: presentationState,
                onHeightChange: { [weak self] newHeight in
                    self?.updateContentHeight(newHeight)
                },
                onInteractionChange: { [weak self] isInteracting in
                    self?.setInteractionLocked(isInteracting)
                }
            )
        )
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

    private func refreshGeometry(animated: Bool = false) {
        guard let panel, let geometry = positionResolver.resolve(
            panelHeight: currentPanelHeight,
            panelWidth: IslandMetrics.panelWidth
        ) else {
            return
        }

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(geometry.expandedFrame, display: true)
            }
        } else {
            panel.setFrame(geometry.expandedFrame, display: true)
        }

        updateActivationWindow(for: geometry.activationRect)

        hoverMonitor.update(
            activationRect: geometry.activationRect,
            interactiveRect: geometry.expandedFrame.insetBy(dx: -2, dy: -2)
        )
    }

    private func updateActivationWindow(for rect: NSRect) {
        if let window = activationWindow {
            window.setFrame(rect, display: true)
        } else {
            let window = NSWindow(
                contentRect: rect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            window.ignoresMouseEvents = false

            let trackingView = ActivationTrackingView(frame: NSRect(origin: .zero, size: rect.size))
            trackingView.onMouseEnter = { [weak self] in
                self?.hoverMonitor.handleDirectActivationEntry()
            }
            trackingView.onMouseExit = { [weak self] in
                self?.hoverMonitor.evaluateCurrentMouseLocation()
            }
            window.contentView = trackingView
            window.orderFrontRegardless()
            self.activationWindow = window
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
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class ActivationTrackingView: NSView {
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }
}
