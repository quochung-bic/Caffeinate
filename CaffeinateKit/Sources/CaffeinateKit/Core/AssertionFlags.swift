/// Bốn khía cạnh "giữ thức" có thể bật/tắt độc lập.
/// Mỗi cờ đơn tương ứng một assertion IOKit.
///
/// Không có `displayName` ở đây — và đó là chủ ý. Kiểu này là dữ liệu, không
/// phải giao diện: gắn chuỗi tiếng Việt vào nó sẽ khoá cả package vào một ngôn
/// ngữ và buộc phần lõi phải biết về việc trình bày. Tên hiển thị nằm ở tầng
/// app, trong String Catalog.
public struct AssertionFlags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let system   = AssertionFlags(rawValue: 1 << 0)
    public static let display  = AssertionFlags(rawValue: 1 << 1)
    public static let disk     = AssertionFlags(rawValue: 1 << 2)
    public static let userIdle = AssertionFlags(rawValue: 1 << 3)

    /// Cấu hình khởi điểm: chỉ giữ hệ thống thức. Màn hình cứ để macOS tự tắt
    /// theo cài đặt của người dùng — giữ màn hình sáng là lựa chọn tốn pin và
    /// hiếm khi cần, nên nó phải là thứ người dùng chủ động bật.
    public static let `default`: AssertionFlags = [.system]

    /// Bốn cờ đơn, theo thứ tự chuẩn tắc dùng ở mọi nơi (UI, test, chẩn đoán).
    /// Thứ tự đi từ "hiếm khi không cần" tới "hiếm khi cần".
    public static let all: [AssertionFlags] = [.system, .display, .disk, .userIdle]

    /// Mã ổn định để tra cứu chuỗi hiển thị ở tầng app và để ghi log/chẩn đoán.
    /// Chỉ có nghĩa với cờ đơn; tổ hợp trả về `nil`.
    public var identifier: String? {
        switch self {
        case .system:   "system"
        case .display:  "display"
        case .disk:     "disk"
        case .userIdle: "userIdle"
        default:        nil
        }
    }
}
