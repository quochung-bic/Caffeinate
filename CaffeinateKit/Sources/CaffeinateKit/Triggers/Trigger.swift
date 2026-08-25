/// One self-contained automation rule. It only reports on/off, and knows
/// nothing about the rest of the system.
@MainActor
public protocol Trigger: AnyObject {
    var onChange: (@MainActor (TriggerReason, Bool) -> Void)? { get set }
    func start()
    func stop()
}

/// Collects the triggers and translates them into CaffeineEvents.
/// It infers nothing further — combining them is reduce's job.
@MainActor
public final class TriggerEngine {
    private let triggers: [any Trigger]
    private var isRunning = false

    public var onEvent: ((CaffeineEvent) -> Void)?

    public init(triggers: [any Trigger]) {
        self.triggers = triggers
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        for trigger in triggers {
            trigger.onChange = { [weak self] reason, active in
                guard let self, self.isRunning else { return }
                self.onEvent?(active ? .triggerFired(reason) : .triggerCleared(reason))
            }
            trigger.start()
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        for trigger in triggers {
            trigger.stop()
            trigger.onChange = nil
        }
    }
}
