/// Pure function: the next state depends only on the previous state and the
/// event. No I/O, no system clock — every instant arrives through an event.
public func reduce(_ state: CaffeineState, _ event: CaffeineEvent) -> CaffeineState {
    var next = state

    switch event {
    case .toggledManually(let on):
        next.manual = on
        // Turning on manually MEANS "no time limit", so it has to clear a
        // running timer: leaving `timerEndsAt` behind would keep the UI drawing
        // a countdown (wrong information), and switching manual off later would
        // resurrect the old timer out of nowhere. Turning manual off leaves the
        // timer alone — it is an independent source.
        if on { next.timerEndsAt = nil }

    case .startedTimer(let until):
        next.timerEndsAt = until

    case .timerExpired:
        next.timerEndsAt = nil

    case .triggerFired(let reason):
        next.triggerReasons.insert(reason)

    case .triggerCleared(let reason):
        next.triggerReasons.remove(reason)

    case .flagsChanged(let flags):
        next.flags = flags

    case .stopAll:
        next.manual = false
        next.timerEndsAt = nil
        next.triggerReasons.removeAll()
    }

    return next
}
