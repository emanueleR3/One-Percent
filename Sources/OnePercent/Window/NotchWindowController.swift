import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class NotchWindowController {
    let taskStore: TaskStore
    private let services: IslandServices
    private let positionResolver = NotchPositionResolver()
    private let hoverMonitor = HoverMonitor()
    private let indicator: NotchIndicatorController
    private var preferenceObserver: AnyCancellable?
    private var interactionLock = InteractionLock()
    private var menuObservers: [NSObjectProtocol] = []
    private var panel: NotchPanel?
    private var activationWindow: NSWindow?
    private var notificationTokens: [NSObjectProtocol] = []
    private var visibilityGeneration = 0
    private var currentPanelHeight: CGFloat = IslandMetrics.standardPanelHeight

    private let presentationState = IslandPresentationState()

    var isHoverEnabled: Bool {
        get { hoverMonitor.isEnabled }
        set { hoverMonitor.isEnabled = newValue }
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true && presentationState.isExpanded
    }

    init(taskStore: TaskStore, services: IslandServices) {
        self.taskStore = taskStore
        self.services = services
        self.indicator = NotchIndicatorController(
            store: taskStore,
            focus: services.focus,
            preferences: services.preferences
        )
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
        installMenuTracking()
        applyHoverTiming()
        refreshGeometry()
        hoverMonitor.start()

        // Display, position, indicator and hover timing all come from Settings: re-apply when any changes.
        preferenceObserver = services.preferences.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyHoverTiming()
                self?.refreshGeometry()
            }
    }

    private func applyHoverTiming() {
        hoverMonitor.openDelay = services.preferences.openDelay
        hoverMonitor.closeDelay = services.preferences.closeDelay
    }

    func stop() {
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        preferenceObserver = nil
        indicator.hide()
        hoverMonitor.stop()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        activationWindow?.orderOut(nil)
        activationWindow = nil
        panel?.orderOut(nil)
    }

    func setInteractionLocked(_ locked: Bool) {
        interactionLock.keyboard = locked
        hoverMonitor.setInteractionLocked(locked)
        if locked {
            activateForInput()
        }
    }

    /// Menus (the status menu on a row, a right-click menu, the repeat picker) are separate windows
    /// that often reach past the panel. While one is open the panel stays where it is.
    private func installMenuTracking() {
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.interactionLock.menuDidBeginTracking()
                self.hoverMonitor.setHeldOpen(self.interactionLock.isMenuHolding)
            }
        })
        menuObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.interactionLock.menuDidEndTracking()
                self.hoverMonitor.setHeldOpen(self.interactionLock.isMenuHolding)
            }
        })
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
        taskStore.ensureHabitOccurrences()
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
        panel.makeKey()

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

        let initialWidth = IslandMetrics.panelWidth + NotchPositionResolver.defaultHeadroom * 2
        let initialHeight = currentPanelHeight + NotchPositionResolver.defaultHeadroom
        let initialSize = NSSize(width: initialWidth, height: initialHeight)
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
        panel.contentView = FirstMouseHostingView(
            rootView: IslandView(
                store: taskStore,
                presentationState: presentationState,
                services: services,
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
        let preferences = services.preferences
        guard let panel, let geometry = positionResolver.resolve(
            panelHeight: currentPanelHeight,
            panelWidth: IslandMetrics.panelWidth,
            selection: preferences.screenSelection,
            anchor: preferences.panelAnchor
        ) else {
            indicator.update(geometry: nil)
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

        // The ring beside the notch counts as part of the notch: pointing at it opens the panel too.
        let indicatorZone = indicator.update(geometry: geometry)
        let hotZone = indicatorZone.map { geometry.activationRect.union($0) } ?? geometry.activationRect
        updateActivationWindow(for: hotZone)

        // The interactive rectangle covers the expanded panel PLUS the entire notch
        // all the way to the top of the screen, so moving to the top never closes the panel.
        let screenTop = hotZone.maxY
        let combinedMinX = min(geometry.expandedFrame.minX, hotZone.minX) - 4
        let combinedMaxX = max(geometry.expandedFrame.maxX, hotZone.maxX) + 4
        let combinedMinY = geometry.expandedFrame.minY - 4
        let fullInteractiveRect = NSRect(
            x: combinedMinX,
            y: combinedMinY,
            width: combinedMaxX - combinedMinX,
            height: (screenTop - combinedMinY) + 15
        )

        hoverMonitor.update(
            activationRect: hotZone,
            interactiveRect: fullInteractiveRect
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

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
