/// Lỗi thô từ IOKit khi tạo hoặc giải phóng một assertion.
///
/// Cố ý KHÔNG có `localizedDescription`: câu chữ hiển thị cho người dùng là
/// việc của tầng app, nơi có String Catalog. Ở đây chỉ giữ đủ dữ kiện để tầng
/// đó dựng câu — cờ nào và mã IOReturn bao nhiêu.
public struct AssertionError: Error, Equatable, Sendable {
    public let flag: AssertionFlags
    public let code: Int32

    public init(flag: AssertionFlags, code: Int32) {
        self.flag = flag
        self.code = code
    }
}

/// Chuyện gì đã hỏng, và hậu quả của nó khác nhau thế nào.
///
/// Phân biệt hai ca này là quan trọng chứ không phải trang trí: create hỏng thì
/// app KHÔNG còn giữ máy thức (đã ép về tắt), release hỏng thì app VẪN đang giữ
/// đúng những gì người dùng yêu cầu. Người dùng cần đọc ra hai câu khác nhau.
public enum AssertionFailure: Error, Equatable, Sendable {
    /// Không tạo được assertion. Trạng thái đã bị ép về tắt.
    case couldNotHold(AssertionError)
    /// Không giải phóng được một assertion cũ. Những cờ vừa yêu cầu vẫn hợp lệ.
    case couldNotRelease(AssertionError)
    /// Lỗi không tới từ IOKit. Giữ nguyên mô tả thô để còn lần ra được;
    /// tầng app bọc nó trong một câu đã dịch chứ không in trần ra.
    case unexpected(debugDescription: String)
}

/// Lớp trừu tượng trên IOKit để test không cần đụng hệ thống thật.
public protocol PowerAssertionBacking: Sendable {
    func create(_ flag: AssertionFlags, reason: String) throws -> UInt32
    func release(_ id: UInt32) throws
}
