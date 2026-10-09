import AppKit

/// Event-driven hover tracking. A global monitor covers other applications and a local
/// monitor covers One Percent when a control in the panel becomes key.
@MainActor
final class HoverMonitor {
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?
    var isEnabled: Bool = true
    var isInteractionLocked: Bool = false
    /// True while a menu belonging to the panel is on screen. A menu is its own window and usually
    /// reaches past the panel, so the pointer inside it counts as "outside": without this the panel
    /// would close under the menu. Unlike `isInteractionLocked` it only holds an open panel.
    private(set) var isHeldOpen: Bool = false

    var closeDelay: TimeInterval
    /// How long the pointer must rest on the notch before the panel opens. 0 opens at once.
    var openDelay: TimeInterval
    private let pointerLocation: () -> NSPoint
    private var openWorkItem: DispatchWorkItem?
    private var activationRect: NSRect = .zero
    private var interactiveRect: NSRect = .zero
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var closeWorkItem: DispatchWorkItem?
    private var state = HoverStateMachine()

    init(
        closeDelay: TimeInterval = 0.16,
        openDelay: TimeInterval = 0,
        pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }
    ) {
        self.closeDelay = closeDelay
        self.openDelay = openDelay
        self.pointerLocation = pointerLocation
    }

    func update(activationRect: NSRect, interactiveRect: NSRect) {
        self.activationRect = activationRect
        self.interactiveRect = interactiveRect
        evaluateCurrentMouseLocation()
    }

    func setHeldOpen(_ held: Bool) {
        guard isHeldOpen != held else { return }
        isHeldOpen = held
        if held {
            closeWorkItem?.cancel()
            closeWorkItem = nil
        } else {
            evaluateCurrentMouseLocation()
        }
    }

    func setInteractionLocked(_ locked: Bool) {
        isInteractionLocked = locked
        if locked {
            closeWorkItem?.cancel()
            closeWorkItem = nil
        } else {
            evaluateCurrentMouseLocation()
        }
    }

    func handleDirectActivationEntry() {
        guard !isHeldOpen else { return }
        guard isEnabled || isInteractionLocked else { return }
        closeWorkItem?.cancel()
        closeWorkItem = nil
        if state.isExpanded || isInteractionLocked {
            apply(state.update(pointerIsInside: true))
        } else {
            requestOpen()
        }
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateCurrentMouseLocation()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.evaluateCurrentMouseLocation()
            }
            return event
        }

        evaluateCurrentMouseLocation()
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        globalMonitor = nil
        localMonitor = nil
        closeWorkItem?.cancel()
        closeWorkItem = nil
        cancelPendingOpen()
        state.reset()
    }

    func forceExpanded() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
        cancelPendingOpen()
        _ = state.update(pointerIsInside: true)
    }

    func forceClosed() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
        cancelPendingOpen()
        state.reset()
    }

    func evaluateCurrentMouseLocation() {
        if isInteractionLocked {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            if !state.isExpanded {
                apply(state.update(pointerIsInside: true))
            }
            return
        }

        guard !activationRect.isEmpty, !interactiveRect.isEmpty else {
            return
        }

        // A menu is open: keep an open panel as it is, and never open a closed one.
        if isHeldOpen {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            cancelPendingOpen()
            return
        }

        let location = pointerLocation()
        let isInActivationArea = activationRect.contains(location)
        let isInInteractiveArea = state.isExpanded && interactiveRect.contains(location)

        if !isEnabled && !state.isExpanded {
            return
        }

        // Opening waits for the dwell time; closing and staying open do not.
        if !state.isExpanded {
            if isInActivationArea { requestOpen() } else { cancelPendingOpen() }
            return
        }

        apply(state.update(pointerIsInside: isInActivationArea || isInInteractiveArea))
    }

    private func requestOpen() {
        guard openDelay > 0 else {
            cancelPendingOpen()
            apply(state.update(pointerIsInside: true))
            return
        }
        guard openWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openWorkItem = nil
            // Only open if the pointer is still resting on the notch.
            if self.activationRect.contains(self.pointerLocation()) {
                self.apply(self.state.update(pointerIsInside: true))
            }
        }
        openWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: workItem)
    }

    private func cancelPendingOpen() {
        openWorkItem?.cancel()
        openWorkItem = nil
    }

    private func apply(_ actions: [HoverStateMachine.Action]) {
        for action in actions {
            switch action {
            case .show:
                closeWorkItem?.cancel()
                closeWorkItem = nil
                onShow?()

            case .scheduleHide:
                if !isInteractionLocked && !isHeldOpen {
                    scheduleHide()
                }

            case .cancelScheduledHide:
                closeWorkItem?.cancel()
                closeWorkItem = nil

            case .hide:
                if !isInteractionLocked && !isHeldOpen {
                    closeWorkItem = nil
                    onHide?()
                }
            }
        }
    }

    private func scheduleHide() {
        closeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isInteractionLocked, !self.isHeldOpen else {
                return
            }
            self.apply(self.state.closeDelayElapsed())
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: workItem)
    }
}
