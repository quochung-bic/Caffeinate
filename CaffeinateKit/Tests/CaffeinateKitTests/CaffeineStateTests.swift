import Foundation
import Testing
@testable import CaffeinateKit

@Suite("CaffeineState")
struct CaffeineStateTests {

    @Test("precedence: manual beats timer, timer beats automation rules")
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

    @Test("when several rules hold, the most informative reason wins")
    func mostInformativeTriggerWins() {
        // This ordering must NOT depend on wording. It used to come from
        // sorting display strings, which meant the reason shown could change
        // with the interface language.
        var state = CaffeineState()
        state.triggerReasons = [.charging, .externalDisplay, .app("Xcode")]
        #expect(state.activeReason == .trigger(.app("Xcode")))

        state.triggerReasons = [.charging, .externalDisplay]
        #expect(state.activeReason == .trigger(.charging))

        state.triggerReasons = [.externalDisplay]
        #expect(state.activeReason == .trigger(.externalDisplay))
    }

    @Test("with several apps running, the choice is by name and stable across reads")
    func multipleAppsSortStably() {
        var state = CaffeineState()
        state.triggerReasons = [.app("Xcode"), .app("Docker"), .app("Blender")]
        // A Set has no order; without sorting explicitly, the reason shown
        // would jump around between reads.
        for _ in 0..<20 {
            #expect(state.activeReason == .trigger(.app("Blender")))
        }
    }

    @Test("while inactive, no flags are sent down to IOKit")
    func effectiveFlagsAreEmptyWhenInactive() {
        var state = CaffeineState()
        state.flags = [.system, .display]
        #expect(state.isActive == false)
        #expect(state.effectiveFlags == [])

        state.manual = true
        #expect(state.effectiveFlags == [.system, .display])
    }
}
