/// Pure hover policy kept independent from AppKit so the timing boundary can be tested.
struct HoverStateMachine {
    enum Action: Equatable {
        case show
        case scheduleHide
        case cancelScheduledHide
        case hide
    }

    private(set) var isExpanded = false
    private(set) var isCloseScheduled = false

    mutating func update(pointerIsInside: Bool) -> [Action] {
        if pointerIsInside {
            if isCloseScheduled {
                isCloseScheduled = false
                return [.cancelScheduledHide]
            }

            if !isExpanded {
                isExpanded = true
                return [.show]
            }

            return []
        }

        guard isExpanded, !isCloseScheduled else {
            return []
        }

        isCloseScheduled = true
        return [.scheduleHide]
    }

    mutating func closeDelayElapsed() -> [Action] {
        guard isExpanded, isCloseScheduled else {
            return []
        }

        isCloseScheduled = false
        isExpanded = false
        return [.hide]
    }

    mutating func reset() {
        isExpanded = false
        isCloseScheduled = false
    }
}
