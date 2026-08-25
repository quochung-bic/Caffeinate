import Foundation
import Testing
@testable import CaffeinateKit

@Suite("reduce")
struct ReduceTests {

    private let future = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("the initial state is inactive")
    func initialStateIsInactive() {
        let state = CaffeineState()
        #expect(!state.isActive)
        #expect(state.activeReason == nil)
        #expect(state.effectiveFlags == [])
    }

    @Test("turning on manually activates and applies the configured flags")
    func manualActivates() {
        var state = CaffeineState()
        state.flags = [.system, .disk]

        state = reduce(state, .toggledManually(true))

        #expect(state.isActive)
        #expect(state.activeReason == .manual)
        #expect(state.effectiveFlags == [.system, .disk])
    }

    @Test("a timer expiring while manual is on leaves it active")
    func stillActiveAfterTimerExpiresIfManual() {
        var state = CaffeineState()
        state = reduce(state, .toggledManually(true))
        state = reduce(state, .startedTimer(until: future))

        state = reduce(state, .timerExpired)

        #expect(state.timerEndsAt == nil)
        #expect(state.isActive)
        #expect(state.activeReason == .manual)
    }

    @Test("choosing indefinite during a timer clears that timer for good")
    func manualOnClearsRunningTimer() {
        var state = CaffeineState()
        state = reduce(state, .startedTimer(until: future))

        state = reduce(state, .toggledManually(true))

        // No end date is left for the UI to draw a countdown from.
        #expect(state.timerEndsAt == nil)
        #expect(state.activeReason == .manual)

        // And the old timer does not come back to life when manual goes off.
        state = reduce(state, .toggledManually(false))
        #expect(!state.isActive)
    }

    @Test("a trigger clearing while a timer runs stays active, with the timer as the reason")
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

    @Test("turning manual off while a trigger still holds does NOT switch off")
    func manualOffDoesNotOverrideActiveTrigger() {
        var state = CaffeineState()
        state = reduce(state, .toggledManually(true))
        state = reduce(state, .triggerFired(.charging))

        state = reduce(state, .toggledManually(false))

        #expect(!state.manual)
        #expect(state.isActive)
        #expect(state.activeReason == .trigger(.charging))
    }

    @Test("stopAll clears every source, automation rules included")
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

    @Test("with several triggers at once, clearing one leaves it active")
    func multipleTriggers() {
        var state = CaffeineState()
        state = reduce(state, .triggerFired(.charging))
        state = reduce(state, .triggerFired(.externalDisplay))

        state = reduce(state, .triggerCleared(.charging))

        #expect(state.isActive)
        #expect(state.triggerReasons == [.externalDisplay])
    }

    @Test("changing flags while active updates effectiveFlags and stays active")
    func flagsChangeWhileActive() {
        var state = CaffeineState()
        state = reduce(state, .toggledManually(true))

        state = reduce(state, .flagsChanged([.system, .display, .userIdle]))

        #expect(state.isActive)
        #expect(state.effectiveFlags == [.system, .display, .userIdle])
    }

    @Test("changing flags while inactive leaves effectiveFlags empty")
    func flagsChangeWhileInactive() {
        var state = CaffeineState()

        state = reduce(state, .flagsChanged([.system, .disk]))

        #expect(!state.isActive)
        #expect(state.flags == [.system, .disk])
        #expect(state.effectiveFlags == [])
    }

    @Test("reason precedence: manual over timer, timer over trigger")
    func reasonPriority() {
        var state = CaffeineState()
        state = reduce(state, .triggerFired(.charging))
        state = reduce(state, .startedTimer(until: future))
        #expect(state.activeReason == .timer(until: future))

        state = reduce(state, .toggledManually(true))
        #expect(state.activeReason == .manual)
    }

    @Test("isActive always agrees with activeReason != nil")
    func isActiveMatchesActiveReason() {
        // 1: empty state — inactive.
        var state = CaffeineState()
        #expect(state.isActive == (state.activeReason != nil))

        // 2: manual only.
        state = reduce(state, .toggledManually(true))
        #expect(state.isActive == (state.activeReason != nil))

        // 3: timer only.
        state = CaffeineState()
        state = reduce(state, .startedTimer(until: future))
        #expect(state.isActive == (state.activeReason != nil))

        // 4: trigger only.
        state = CaffeineState()
        state = reduce(state, .triggerFired(.charging))
        #expect(state.isActive == (state.activeReason != nil))

        // 5: all three at once.
        state = CaffeineState()
        state = reduce(state, .toggledManually(true))
        state = reduce(state, .startedTimer(until: future))
        state = reduce(state, .triggerFired(.externalDisplay))
        #expect(state.isActive == (state.activeReason != nil))

        // 6: cleared from a fully populated state.
        state = reduce(state, .stopAll)
        #expect(state.isActive == (state.activeReason != nil))
    }
}
