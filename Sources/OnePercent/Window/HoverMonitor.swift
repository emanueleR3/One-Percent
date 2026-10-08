import AppKit

/// Event-driven hover tracking. A global monitor covers other applications and a local
/// monitor covers One Percent when a control in the panel becomes key.
@MainActor
final class HoverMonitor {
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?
    var isEnabled: Bool = true
    var isInteractionLocked: Bool = false

    private let closeDelay: TimeInterval
    private var activationRect: NSRect = .zero
    private var interactiveRect: NSRect = .zero
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var closeWorkItem: DispatchWorkItem?
    private var state = HoverStateMachine()

    init(closeDelay: TimeInterval = 0.32) {
        self.closeDelay = closeDelay
    }

    func update(activationRect: NSRect, interactiveRect: NSRect) {
        self.activationRect = activationRect
        self.interactiveRect = interactiveRect
        evaluateCurrentMouseLocation()
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
        guard isEnabled || isInteractionLocked else { return }
        closeWorkItem?.cancel()
        closeWorkItem = nil
        apply(state.update(pointerIsInside: true))
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
        state.reset()
    }

    func forceExpanded() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
        _ = state.update(pointerIsInside: true)
    }

    func forceClosed() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
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

        let location = NSEvent.mouseLocation
        let isInActivationArea = activationRect.contains(location)
        let isInInteractiveArea = state.isExpanded && interactiveRect.contains(location)

        if !isEnabled && !state.isExpanded {
            return
        }

        apply(state.update(pointerIsInside: isInActivationArea || isInInteractiveArea))
    }

    private func apply(_ actions: [HoverStateMachine.Action]) {
        for action in actions {
            switch action {
            case .show:
                closeWorkItem?.cancel()
                closeWorkItem = nil
                onShow?()

            case .scheduleHide:
                if !isInteractionLocked {
                    scheduleHide()
                }

            case .cancelScheduledHide:
                closeWorkItem?.cancel()
                closeWorkItem = nil

            case .hide:
                if !isInteractionLocked {
                    closeWorkItem = nil
                    onHide?()
                }
            }
        }
    }

    private func scheduleHide() {
        closeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isInteractionLocked else {
                return
            }
            self.apply(self.state.closeDelayElapsed())
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: workItem)
    }
}
