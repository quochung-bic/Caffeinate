import Foundation

/// Mọi thứ có thể làm trạng thái thay đổi. Không có đường nào khác.
public enum CaffeineEvent: Equatable, Sendable {
    case toggledManually(Bool)
    case startedTimer(until: Date)
    case timerExpired
    case triggerFired(TriggerReason)
    case triggerCleared(TriggerReason)
    case flagsChanged(AssertionFlags)
    /// Tắt dứt khoát mọi nguồn, kể cả luật tự động đang đúng.
    case stopAll
}
