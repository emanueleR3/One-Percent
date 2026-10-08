import AppKit

/// Event-driven hover tracking. A global monitor covers other applications and a local
/// monitor covers One Percent when a control in the panel becomes key.
@MainActor
final class HoverMonitor {
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

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

    private func evaluateCurrentMouseLocation() {
        guard !activationRect.isEmpty, !interactiveRect.isEmpty else {
            return
        }

        let location = NSEvent.mouseLocation
        let isInActivationArea = activationRect.contains(location)
        let isInInteractiveArea = state.isExpanded && interactiveRect.contains(location)
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
                scheduleHide()

            case .cancelScheduledHide:
                closeWorkItem?.cancel()
                closeWorkItem = nil

            case .hide:
                closeWorkItem = nil
                onHide?()
            }
        }
    }

    private func scheduleHide() {
        closeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.apply(self.state.closeDelayElapsed())
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: workItem)
    }
}
