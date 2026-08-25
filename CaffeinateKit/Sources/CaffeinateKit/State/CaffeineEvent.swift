import Foundation

/// Everything that can change the state. There is no other route.
public enum CaffeineEvent: Equatable, Sendable {
    case toggledManually(Bool)
    case startedTimer(until: Date)
    case timerExpired
    case triggerFired(TriggerReason)
    case triggerCleared(TriggerReason)
    case flagsChanged(AssertionFlags)
    /// Stop every source decisively, including automation rules that still hold.
    case stopAll
}
