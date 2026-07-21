/// Một luật tự động độc lập. Chỉ báo bật/tắt, không biết gì về phần còn lại.
@MainActor
public protocol Trigger: AnyObject {
    var onChange: (@MainActor (TriggerReason, Bool) -> Void)? { get set }
    func start()
    func stop()
}

/// Gom các trigger lại và dịch chúng thành CaffeineEvent.
/// Không suy luận gì thêm — việc hợp nhất là của reduce.
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
