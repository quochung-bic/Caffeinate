import Foundation

/// Vì sao một luật tự động đang yêu cầu giữ máy thức.
///
/// `.app` mang theo tên hiển thị mà macOS trả về cho ứng dụng đó — đây là dữ
/// liệu lấy từ hệ thống, không phải chuỗi giao diện do app này viết ra, nên nó
/// nằm ở đây là đúng chỗ.
public enum TriggerReason: Hashable, Sendable {
    case app(String)
    case charging
    case externalDisplay
}

extension TriggerReason: Comparable {
    /// Thứ tự ưu tiên khi nhiều luật cùng đúng: cái nào NÓI ĐƯỢC NHIỀU NHẤT thì
    /// hiện trước. "Xcode đang chạy" hữu ích hơn hẳn "đang cắm sạc".
    ///
    /// Trước đây thứ tự này lấy từ việc sắp xếp chuỗi tiếng Việt — nghĩa là đổi
    /// ngôn ngữ giao diện sẽ lặng lẽ đổi luôn lý do nào được hiển thị. Xếp hạng
    /// tường minh ở đây làm thứ tự độc lập với ngôn ngữ.
    private var priority: (Int, String) {
        switch self {
        case .app(let name):    (0, name)
        case .charging:         (1, "")
        case .externalDisplay:  (2, "")
        }
    }

    public static func < (lhs: TriggerReason, rhs: TriggerReason) -> Bool {
        lhs.priority < rhs.priority
    }
}

/// Nguồn kích hoạt đang thắng, dùng để hiển thị "Tự bật do: ...".
public enum ActiveReason: Equatable, Sendable {
    case manual
    case timer(until: Date)
    case trigger(TriggerReason)
}

/// Toàn bộ trạng thái của app. Nguồn sự thật duy nhất.
public struct CaffeineState: Equatable, Sendable {
    public var manual: Bool = false
    public var timerEndsAt: Date? = nil
    public var triggerReasons: Set<TriggerReason> = []
    /// Bộ cờ người dùng đã cấu hình — áp dụng khi và chỉ khi đang hoạt động.
    public var flags: AssertionFlags = .default

    public init() {}

    public var isActive: Bool {
        activeReason != nil
    }

    /// Bộ cờ thực sự gửi xuống IOKit.
    public var effectiveFlags: AssertionFlags {
        isActive ? flags : []
    }

    /// Ưu tiên: thủ công > hẹn giờ > luật tự động.
    public var activeReason: ActiveReason? {
        if manual { return .manual }
        if let endsAt = timerEndsAt { return .timer(until: endsAt) }
        // Sắp xếp để lý do hiển thị ổn định giữa các lần đọc và giữa các ngôn ngữ.
        if let first = triggerReasons.min() { return .trigger(first) }
        return nil
    }
}
