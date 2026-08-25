import Foundation
import Testing
@testable import CaffeinateKit

/// Builds a trigger set following the production rules (app / charging /
/// external display, according to settings) but out of `FakeTrigger`s, and
/// keeps a reference to the MOST RECENT trigger of each kind — because
/// `rebuildTriggers()` creates new triggers every time settings change, exactly
/// as production always creates fresh `AppRunningTrigger` /
/// `PowerSourceTrigger` / `ExternalDisplayTrigger` instances. This is the only
/// seam needed to make `CaffeineController` testable without touching IOKit,
/// NSWorkspace or NSScreen.
@MainActor
private final class TriggerSpy {
    private(set) var appTrigger: FakeTrigger?
    private(set) var chargingTrigger: FakeTrigger?
    private(set) var externalDisplayTrigger: FakeTrigger?

    func makeTriggers(for settings: Settings) -> [any Trigger] {
        var triggers: [any Trigger] = []

        if settings.appTriggerEnabled, !settings.triggerAppBundleIDs.isEmpty {
            let t = FakeTrigger()
            appTrigger = t
            triggers.append(t)
        } else {
            appTrigger = nil
        }

        if settings.chargingTriggerEnabled {
            let t = FakeTrigger()
            chargingTrigger = t
            triggers.append(t)
        } else {
            chargingTrigger = nil
        }

        if settings.externalDisplayTriggerEnabled {
            let t = FakeTrigger()
            externalDisplayTrigger = t
            triggers.append(t)
        } else {
            externalDisplayTrigger = nil
        }

        return triggers
    }
}

@Suite("CaffeineController")
@MainActor
struct CaffeineControllerTests {

    private func makeController(
        settings: Settings = Settings(),
        backing: FakeBacking = FakeBacking(),
        spy: TriggerSpy = TriggerSpy()
    ) -> CaffeineController {
        let store = InMemorySettingsStore(settings: settings)
        return CaffeineController(
            assertions: AssertionManager(backing: backing, reason: "Test"),
            store: store,
            triggerFactory: { spy.makeTriggers(for: $0) }
        )
    }

    // MARK: - a) Reconfiguring drains a stale trigger reason (the fba522a case)

    @Test("disabling the app trigger drains its reason, keeps charging, and stays active")
    func reconfigureDrainsStaleTriggerReason() {
        var settings = Settings()
        settings.appTriggerEnabled = true
        settings.triggerAppBundleIDs = ["com.example.app"]
        settings.chargingTriggerEnabled = true

        let spy = TriggerSpy()
        let controller = makeController(settings: settings, spy: spy)

        spy.appTrigger?.fire(.app("Example App"), active: true)
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.triggerReasons == [.app("Example App"), .charging])
        #expect(controller.state.isActive)

        // Disabling the app trigger in settings runs rebuildTriggers(). The old
        // trigger set (both app and charging) is stopped and EVERY old reason is
        // drained first, regardless of which ones remain valid under the new
        // configuration — this is precisely where the fba522a case used to
        // break: the app reason was skipped and stranded forever, because
        // draining only happened when the new trigger set was empty.
        controller.settings.appTriggerEnabled = false

        // The app trigger is gone from the new set, so .app(...) is withdrawn
        // for good.
        #expect(!controller.state.triggerReasons.contains(.app("Example App")))
        #expect(spy.appTrigger == nil)

        // A NEW charging trigger is created (settings still enable it). In
        // production, TriggerEngine.start() calls refresh() immediately and the
        // real trigger (PowerSourceTrigger) re-emits .triggerFired if the
        // condition still holds — FakeTrigger does not do that by itself, so we
        // model that refresh() with one explicit fire.
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.triggerReasons == [.charging])
        #expect(controller.state.isActive)
    }

    // MARK: - b) A failed create forces inactive, sets lastFailure, releases all

    @Test("a create failing midway forces inactive, records lastFailure, and releases what it made")
    func createFailureForcesInactiveAndReleasesAll() {
        let backing = FakeBacking()
        backing.failingFlags = [.userIdle]
        var settings = Settings()
        settings.flags = [.display, .userIdle]

        let controller = makeController(settings: settings, backing: backing)

        controller.toggle()

        #expect(controller.state.isActive == false)
        #expect(controller.state.manual == false)
        #expect(controller.lastFailure != nil)
        // .display is created first (id 1), then .userIdle throws, so the
        // rollback releases .display again. Nothing stays held.
        #expect(backing.calls == [.create(.display), .release(1)])
    }

    // MARK: - c) Timer expiry with manual still on stays active

    @Test("a timer expiring while manual is still on leaves the app active")
    func timerExpiryWithManualStillOnStaysActive() {
        let controller = makeController()

        controller.send(.toggledManually(true))
        controller.send(.startedTimer(until: Date().addingTimeInterval(60)))
        #expect(controller.state.isActive)

        controller.send(.timerExpired)

        #expect(controller.state.timerEndsAt == nil)
        #expect(controller.state.manual)
        #expect(controller.state.isActive)
    }

    // MARK: - d) Stop is decisive — no bounce-back while the condition is
    // unchanged, but a genuine recurrence does resume. See the doc comment on
    // `CaffeineController.toggle()` for the full semantics.

    @Test("Stop clears trigger reasons decisively: no bounce-back unchanged, but a real recurrence resumes")
    func stopIsDecisiveNoBounceBackButRecurrenceResumes() {
        var settings = Settings()
        settings.chargingTriggerEnabled = true
        let spy = TriggerSpy()
        let controller = makeController(settings: settings, spy: spy)

        spy.chargingTrigger?.fire(.charging, active: true)
        #expect(controller.state.isActive)
        #expect(controller.state.triggerReasons == [.charging])

        // Stop decisively: clear manual, timer and every trigger reason,
        // including one that is still physically true (still plugged in).
        controller.toggle()
        #expect(controller.state.isActive == false)
        #expect(controller.state.triggerReasons.isEmpty)

        // "Unchanged": a real trigger (e.g. PowerSourceTrigger.refresh()) only
        // calls onChange when the condition ACTUALLY changes (`guard charging
        // != isCharging else { return }`) — a status tick identical to the last
        // one emits nothing at all. FakeTrigger models that same guard (see
        // Fakes.swift): the baseline in spy.chargingTrigger is still `true`
        // from the first fire (stopAll above never touched it, exactly like the
        // real trigger), so calling fire(.charging, active: true) again — same
        // state, with no active:false in between — is swallowed by the guard and
        // NOT forwarded to the controller. This is a real assertion: remove the
        // guard (or stop stopAll from clearing triggerReasons) and this test
        // FAILS, because the controller would switch back on.
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.isActive == false)
        #expect(controller.state.triggerReasons.isEmpty)

        // A genuine recurrence (unplug, then plug back in): the real trigger
        // sees a false→true transition and calls onChange again. Modelled here
        // by an active:false followed by an active:true.
        spy.chargingTrigger?.fire(.charging, active: false)
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.isActive)
        #expect(controller.state.triggerReasons == [.charging])
    }
}

// MARK: - Timers and icon state
//
// Countdown behaviour cannot be verified through XCUITest (a 1 Hz tick means
// the app is never "idle" in the way that tool demands), so it is covered here
// instead — deterministically, with no need to wait on a real clock.

@Suite("CaffeineController — timers")
@MainActor
struct CaffeineControllerTimerTests {

    private func makeController(settings: Settings = Settings()) -> CaffeineController {
        CaffeineController(
            assertions: AssertionManager(backing: FakeBacking(), reason: "Test"),
            store: InMemorySettingsStore(settings: settings),
            triggerFactory: { _ in [] }
        )
    }

    @Test("starting a timer sets the end date, activates, and enters countdown mode")
    func startTimerEntersCountdown() throws {
        let controller = makeController()
        #expect(controller.isCountingDown == false)

        let before = Date()
        controller.startTimer(minutes: 15)

        let endsAt = try #require(controller.state.timerEndsAt)
        #expect(controller.state.isActive)
        #expect(controller.isCountingDown)
        #expect(controller.timerTotalSeconds == 900)
        // Allow a small tolerance: the end date is computed from Date() inside.
        #expect(abs(endsAt.timeIntervalSince(before) - 900) < 2)
    }

    @Test("out-of-range durations are clamped — public API cannot assume the caller checked")
    func startTimerClampsMinutes() {
        let controller = makeController()

        controller.startTimer(minutes: 100_000)
        #expect(controller.timerTotalSeconds == TimeInterval(480 * 60))

        controller.startTimer(minutes: -5)
        #expect(controller.timerTotalSeconds == TimeInterval(1 * 60))
    }

    @Test("the coffee level drains over time: full at the start, empty at the end")
    func iconProgressDrainsOverTime() throws {
        let controller = makeController()
        controller.startTimer(minutes: 60)
        let endsAt = try #require(controller.state.timerEndsAt)
        let startedAt = endsAt.addingTimeInterval(-3_600)

        let full = try #require(controller.iconState(at: startedAt).progress)
        let half = try #require(controller.iconState(at: startedAt.addingTimeInterval(1_800)).progress)
        let empty = try #require(controller.iconState(at: endsAt).progress)

        #expect(full == 1.0)
        #expect(abs(half - 0.5) < 0.05)
        #expect(empty == 0.0)

        // Past the end it clamps to empty rather than going negative.
        #expect(controller.iconState(at: endsAt.addingTimeInterval(600)).progress == 0.0)
    }

    @Test("running indefinitely leaves the icon with no level to drain")
    func indefiniteHasNoProgress() {
        let controller = makeController()
        controller.startIndefinite()

        #expect(controller.state.isActive)
        #expect(controller.isCountingDown == false)
        #expect(controller.iconState(at: .now).progress == nil)
        // The total must be cleared, or the next draw still divides by the old one.
        #expect(controller.timerTotalSeconds == 0)
    }

    @Test("switching from a timer to indefinite wipes the old end date")
    func indefiniteClearsRunningTimer() {
        let controller = makeController()
        controller.startTimer(minutes: 30)
        #expect(controller.isCountingDown)

        controller.startIndefinite()

        #expect(controller.state.timerEndsAt == nil)
        #expect(controller.isCountingDown == false)
        #expect(controller.timerTotalSeconds == 0)
    }

    @Test("stopping resets everything: not active, not counting down, no end date")
    func stopClearsEverything() {
        let controller = makeController()
        controller.startTimer(minutes: 30)

        controller.stop()

        #expect(controller.state.isActive == false)
        #expect(controller.state.timerEndsAt == nil)
        #expect(controller.isCountingDown == false)
        #expect(controller.timerTotalSeconds == 0)
        #expect(controller.iconState(at: .now).isActive == false)
    }

    @Test("a failure surfaces in the icon state so the user sees it on the menu bar")
    func failureShowsInIconState() {
        let backing = FakeBacking()
        backing.failingFlags = [.system]
        let controller = CaffeineController(
            assertions: AssertionManager(backing: backing, reason: "Test"),
            store: InMemorySettingsStore(settings: Settings()),
            triggerFactory: { _ in [] }
        )

        controller.startIndefinite()

        #expect(controller.lastFailure != nil)
        #expect(controller.iconState(at: .now).hasError)
    }
}
