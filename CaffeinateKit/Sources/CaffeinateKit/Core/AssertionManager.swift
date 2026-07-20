import Foundation

/// Giữ tập assertion đang hoạt động và đồng bộ nó với bộ cờ mong muốn.
///
/// Bất biến: `held` luôn phản ánh đúng những assertion đang thực sự tồn tại.
/// Nếu một lệnh create thất bại giữa chừng, mọi assertion đã tạo trong lượt đó
/// và cả những cái đang giữ từ trước đều được giải phóng — thà tắt hẳn còn hơn
/// để người dùng tưởng đang giữ mà thực tế chỉ giữ một nửa.
public final class AssertionManager {
    /// Tên assertion mà app dùng thật.
    ///
    /// PHẢI thuần ASCII: `IOPMAssertionCreateWithName` nhận chuỗi có dấu tiếng
    /// Việt mà không báo lỗi, nhưng `pmset -g assertions` in ra `named: ""` —
    /// assertion trở nên vô danh, đúng lúc người dùng cần dùng pmset để kiểm
    /// chứng app có thật sự đang giữ máy thức hay không.
    ///
    /// Và PHẢI giữ nguyên tiếng Anh dù giao diện có đổi ngôn ngữ: đây là chuỗi
    /// hiển thị ở tầng hệ điều hành, cho công cụ dòng lệnh và cho log hệ thống,
    /// không phải cho giao diện. Dịch nó là làm hỏng khả năng chẩn đoán.
    public static let defaultReason = "Caffeinate is keeping this Mac awake"

    private let backing: PowerAssertionBacking
    private let reason: String
    private var held: [AssertionFlags: UInt32] = [:]

    /// Lỗi release gần nhất chưa được một lượt giải phóng thành công "xoá dấu".
    /// Không chỗ nào được hỏng im lặng: nếu IOKit từ chối release, người gọi
    /// (CaffeineController) phải có cách đọc ra và hiển thị cho người dùng.
    public private(set) var lastReleaseError: AssertionError?

    public init(backing: PowerAssertionBacking, reason: String) {
        self.backing = backing
        self.reason = reason
    }

    public var heldFlags: AssertionFlags {
        held.keys.reduce(into: AssertionFlags()) { $0.insert($1) }
    }

    public func set(flags desired: AssertionFlags) throws {
        let current = heldFlags
        guard desired != current else { return }

        let toCreate = AssertionFlags.all.filter {
            desired.contains($0) && !current.contains($0)
        }
        let toRelease = AssertionFlags.all.filter {
            !desired.contains($0) && current.contains($0)
        }

        for flag in toCreate {
            do {
                held[flag] = try backing.create(flag, reason: reason)
            } catch {
                releaseAll()
                throw error
            }
        }

        // Release thất bại không được ném ra ngoài: các assertion mà caller
        // vừa yêu cầu (toCreate) đã tồn tại hợp lệ, một release hỏng không
        // làm chúng vô hiệu. Lỗi được ghi lại qua lastReleaseError thay vì bị nuốt.
        release(toRelease)
    }

    /// Giải phóng mọi assertion. An toàn để gọi nhiều lần.
    public func releaseAll() {
        release(AssertionFlags.all)
    }

    /// Giải phóng một lô cờ, cập nhật `held` và `lastReleaseError`.
    /// Cờ luôn bị xoá khỏi `held` dù release có báo lỗi hay không — không
    /// retry, không để lại mục ma. `lastReleaseError` chỉ được xoá khi lô này
    /// thực sự giải phóng ít nhất một cờ và không cờ nào thất bại.
    private func release(_ flags: [AssertionFlags]) {
        var releasedAny = false
        var failed = false
        for flag in flags {
            if let id = held.removeValue(forKey: flag) {
                releasedAny = true
                do {
                    try backing.release(id)
                } catch {
                    failed = true
                    lastReleaseError = Self.releaseError(flag: flag, underlying: error)
                }
            }
        }
        if releasedAny && !failed {
            lastReleaseError = nil
        }
    }

    /// Backing chỉ biết ID nên nó ném lỗi với cờ rỗng; ở đây ta biết cờ nào,
    /// nên bọc lại cho người dùng đọc ra được thứ có nghĩa.
    private static func releaseError(flag: AssertionFlags, underlying error: Error) -> AssertionError {
        if let assertionError = error as? AssertionError {
            return AssertionError(flag: flag, code: assertionError.code)
        }
        return AssertionError(flag: flag, code: Int32(clamping: (error as NSError).code))
    }

    deinit {
        releaseAll()
    }
}
