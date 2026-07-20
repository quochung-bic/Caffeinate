import Testing
@testable import CaffeinateKit

@Suite("AssertionFlags")
struct AssertionFlagsTests {

    @Test("mặc định chỉ giữ hệ thống, màn hình để macOS tự quyết")
    func defaultFlags() {
        #expect(AssertionFlags.default == [.system])
    }

    @Test("all liệt kê đúng bốn cờ đơn, không trùng lặp")
    func allEnumeratesFourSingleFlags() {
        #expect(AssertionFlags.all.count == 4)
        #expect(Set(AssertionFlags.all.map(\.rawValue)).count == 4)
        for flag in AssertionFlags.all {
            #expect(flag.rawValue.nonzeroBitCount == 1)
        }
    }

    @Test("mỗi cờ đơn có mã định danh riêng, tổ hợp thì không có")
    func identifiersAreDistinctForSingleFlags() {
        let ids = AssertionFlags.all.map(\.identifier)
        #expect(ids == ["system", "display", "disk", "userIdle"])
        // Mã này là khoá tra chuỗi hiển thị ở tầng app và là nhãn trong log,
        // nên nó phải ổn định; đổi nó là làm hỏng bản dịch lẫn khả năng chẩn đoán.
        #expect(AssertionFlags([.system, .display]).identifier == nil)
        #expect(AssertionFlags([]).identifier == nil)
    }

    @Test("phép trừ tập hợp cho ra phần chênh lệch")
    func setSubtraction() {
        let desired: AssertionFlags = [.system, .display, .disk]
        let held: AssertionFlags = [.system, .userIdle]
        #expect(desired.subtracting(held) == [.display, .disk])
        #expect(held.subtracting(desired) == [.userIdle])
    }
}
