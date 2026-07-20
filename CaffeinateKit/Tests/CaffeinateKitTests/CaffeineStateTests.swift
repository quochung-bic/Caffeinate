import Foundation
import Testing
@testable import CaffeinateKit

@Suite("CaffeineState")
struct CaffeineStateTests {

    @Test("ưu tiên: thủ công thắng hẹn giờ, hẹn giờ thắng luật tự động")
    func activeReasonPriority() {
        var state = CaffeineState()
        state.triggerReasons = [.charging]
        #expect(state.activeReason == .trigger(.charging))

        let endsAt = Date(timeIntervalSinceReferenceDate: 1_000)
        state.timerEndsAt = endsAt
        #expect(state.activeReason == .timer(until: endsAt))

        state.manual = true
        #expect(state.activeReason == .manual)
    }

    @Test("nhiều luật cùng đúng thì lý do nói được nhiều nhất hiện trước")
    func mostInformativeTriggerWins() {
        // Thứ tự này KHÔNG được phụ thuộc vào ngôn ngữ giao diện. Trước đây nó
        // đến từ việc sắp xếp chuỗi tiếng Việt, nghĩa là chuyển app sang tiếng
        // Anh sẽ lặng lẽ đổi lý do được hiển thị.
        var state = CaffeineState()
        state.triggerReasons = [.charging, .externalDisplay, .app("Xcode")]
        #expect(state.activeReason == .trigger(.app("Xcode")))

        state.triggerReasons = [.charging, .externalDisplay]
        #expect(state.activeReason == .trigger(.charging))

        state.triggerReasons = [.externalDisplay]
        #expect(state.activeReason == .trigger(.externalDisplay))
    }

    @Test("nhiều app cùng chạy thì chọn theo tên, ổn định giữa các lần đọc")
    func multipleAppsSortStably() {
        var state = CaffeineState()
        state.triggerReasons = [.app("Xcode"), .app("Docker"), .app("Blender")]
        // Set không có thứ tự; nếu không sắp xếp tường minh thì lý do hiển thị
        // sẽ nhảy lung tung giữa các lần chạy.
        for _ in 0..<20 {
            #expect(state.activeReason == .trigger(.app("Blender")))
        }
    }

    @Test("không hoạt động thì không gửi cờ nào xuống IOKit")
    func effectiveFlagsAreEmptyWhenInactive() {
        var state = CaffeineState()
        state.flags = [.system, .display]
        #expect(state.isActive == false)
        #expect(state.effectiveFlags == [])

        state.manual = true
        #expect(state.effectiveFlags == [.system, .display])
    }
}
