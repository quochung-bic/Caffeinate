import Foundation
import Testing
@testable import CaffeinateKit

@Suite("reduce")
struct ReduceTests {

    private let future = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("trạng thái khởi điểm không hoạt động")
    func initialStateIsInactive() {
        let state = CaffeineState()
        #expect(!state.isActive)
        #expect(state.activeReason == nil)
        #expect(state.effectiveFlags == [])
    }

    @Test("bật thủ công thì hoạt động và áp dụng bộ cờ đã cấu hình")
    func manualActivates() {
        var state = CaffeineState()
        state.flags = [.system, .disk]

        state = reduce(state, .toggledManually(true))

        #expect(state.isActive)
        #expect(state.activeReason == .manual)
        #expect(state.effectiveFlags == [.system, .disk])
    }

    @Test("hết giờ khi vẫn bật thủ công thì vẫn hoạt động")
    func stillActiveAfterTimerExpiresIfManual() {
        var state = CaffeineState()
        state = reduce(state, .toggledManually(true))
        state = reduce(state, .startedTimer(until: future))

        state = reduce(state, .timerExpired)

        #expect(state.timerEndsAt == nil)
        #expect(state.isActive)
        #expect(state.activeReason == .manual)
    }

    @Test("chọn không giới hạn khi đang hẹn giờ thì xoá hẳn hẹn giờ")
    func manualOnClearsRunningTimer() {
        var state = CaffeineState()
        state = reduce(state, .startedTimer(until: future))

        state = reduce(state, .toggledManually(true))

        // Không còn mốc hết hạn nào để UI vẽ vòng đếm ngược.
        #expect(state.timerEndsAt == nil)
        #expect(state.activeReason == .manual)

        // Và hẹn giờ cũ không sống lại khi tắt thủ công.
        state = reduce(state, .toggledManually(false))
        #expect(!state.isActive)
    }

    @Test("trigger tắt khi timer còn chạy thì vẫn hoạt động, lý do đổi sang timer")
    func triggerClearedButTimerKeepsItActive() {
        var state = CaffeineState()
        state = reduce(state, .triggerFired(.app("Xcode")))
        #expect(state.activeReason == .trigger(.app("Xcode")))

        state = reduce(state, .startedTimer(until: future))
        state = reduce(state, .triggerCleared(.app("Xcode")))

        #expect(state.isActive)
        #expect(state.activeReason == .timer(until: future))
        #expect(state.triggerReasons.isEmpty)
    }

    @Test("tắt thủ công khi trigger vẫn đúng thì KHÔNG tắt")
    func manualOffDoesNotOverrideActiveTrigger() {
        var state = CaffeineState()
        state = reduce(state, .toggledManually(true))
        state = reduce(state, .triggerFired(.charging))

        state = reduce(state, .toggledManually(false))

        #expect(!state.manual)
        #expect(state.isActive)
        #expect(state.activeReason == .trigger(.charging))
    }

    @Test("stopAll xoá sạch mọi nguồn kích hoạt kể cả trigger")
    func stopAllClearsEverything() {
        var state = CaffeineState()
        state = reduce(state, .toggledManually(true))
        state = reduce(state, .startedTimer(until: future))
        state = reduce(state, .triggerFired(.externalDisplay))

        state = reduce(state, .stopAll)

        #expect(!state.isActive)
        #expect(state.activeReason == nil)
        #expect(state.triggerReasons.isEmpty)
        #expect(state.timerEndsAt == nil)
    }

    @Test("nhiều trigger cùng lúc, tắt một cái thì vẫn hoạt động")
    func multipleTriggers() {
        var state = CaffeineState()
        state = reduce(state, .triggerFired(.charging))
        state = reduce(state, .triggerFired(.externalDisplay))

        state = reduce(state, .triggerCleared(.charging))

        #expect(state.isActive)
        #expect(state.triggerReasons == [.externalDisplay])
    }

    @Test("đổi cờ lúc đang hoạt động thì effectiveFlags đổi theo, vẫn hoạt động")
    func flagsChangeWhileActive() {
        var state = CaffeineState()
        state = reduce(state, .toggledManually(true))

        state = reduce(state, .flagsChanged([.system, .display, .userIdle]))

        #expect(state.isActive)
        #expect(state.effectiveFlags == [.system, .display, .userIdle])
    }

    @Test("đổi cờ lúc không hoạt động thì effectiveFlags vẫn rỗng")
    func flagsChangeWhileInactive() {
        var state = CaffeineState()

        state = reduce(state, .flagsChanged([.system, .disk]))

        #expect(!state.isActive)
        #expect(state.flags == [.system, .disk])
        #expect(state.effectiveFlags == [])
    }

    @Test("ưu tiên lý do: thủ công trên timer, timer trên trigger")
    func reasonPriority() {
        var state = CaffeineState()
        state = reduce(state, .triggerFired(.charging))
        state = reduce(state, .startedTimer(until: future))
        #expect(state.activeReason == .timer(until: future))

        state = reduce(state, .toggledManually(true))
        #expect(state.activeReason == .manual)
    }

    @Test("isActive luôn khớp với activeReason != nil")
    func isActiveMatchesActiveReason() {
        // Test 1: trạng thái rỗng — không hoạt động
        var state = CaffeineState()
        #expect(state.isActive == (state.activeReason != nil))

        // Test 2: chỉ bật thủ công
        state = reduce(state, .toggledManually(true))
        #expect(state.isActive == (state.activeReason != nil))

        // Test 3: chỉ timer
        state = CaffeineState()
        state = reduce(state, .startedTimer(until: future))
        #expect(state.isActive == (state.activeReason != nil))

        // Test 4: chỉ trigger
        state = CaffeineState()
        state = reduce(state, .triggerFired(.charging))
        #expect(state.isActive == (state.activeReason != nil))

        // Test 5: tất cả ba cùng lúc
        state = CaffeineState()
        state = reduce(state, .toggledManually(true))
        state = reduce(state, .startedTimer(until: future))
        state = reduce(state, .triggerFired(.externalDisplay))
        #expect(state.isActive == (state.activeReason != nil))

        // Test 6: xoá toàn bộ từ trạng thái đầy đủ
        state = reduce(state, .stopAll)
        #expect(state.isActive == (state.activeReason != nil))
    }
}
