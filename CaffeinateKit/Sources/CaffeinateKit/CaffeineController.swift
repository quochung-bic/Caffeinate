import Foundation
import Observation

/// Source of truth for the UI, and the ONLY place that calls
/// `AssertionManager.set(flags:)`. Every change goes through
/// `send(_:) → reduce → apply()`. There is no shortcut.
///
/// It lives in the package rather than the app target because it depends on
/// neither SwiftUI nor AppKit — only Foundation, Observation and the rest of
/// CaffeinateKit — so `swift test` can exercise it with fake backings and
/// triggers instead of standing up the whole app.
@MainActor
@Observable
public final class CaffeineController {
    public private(set) var state = CaffeineState()

    /// The most recent failure, as data. The app layer turns it into a sentence.
    public private(set) var lastFailure: AssertionFailure?

    /// Total length of the current timer — needed to compute the coffee level.
    public private(set) var timerTotalSeconds: TimeInterval = 0

    /// One-second tick, running ONLY during a countdown.
    ///
    /// Why the tick lives here rather than in the view layer: a `MenuBarExtra`
    /// label does NOT drive `TimelineView`. Measured, not guessed — over eight
    /// seconds of an active timer, a label built on
    /// `TimelineView(.periodic(by: 1))` redrew twice, both times because state
    /// changed. The icon would sit at full for the whole timer, which is
    /// precisely the feature it exists for.
    ///
    /// The only reliable way to force the label to redraw is to have it read an
    /// `@Observable` property that actually changes. That property is `now`.
    ///
    /// `iconState(at:)` still takes its instant from the caller instead of
    /// reading `Date()`, so the arithmetic stays pure and testable without
    /// waiting on a real clock.
    public private(set) var now: Date = .now

    /// Called when a timer runs out on its own — not when the user stops it.
    /// The app layer uses this to notify the user; the package stays out of it
    /// because notifications and sound belong to AppKit, not to the core.
    @ObservationIgnored public var onTimerExpired: (@MainActor () -> Void)?

    /// Called whenever a timer starts. The app layer uses it to ask for
    /// notification permission at the moment the user does the thing that will
    /// lead to a notification.
    @ObservationIgnored public var onTimerStarted: (@MainActor () -> Void)?

    @ObservationIgnored private let assertions: AssertionManager
    @ObservationIgnored private let store: any SettingsStoring
    @ObservationIgnored private let triggerFactory: TriggerFactory
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    @ObservationIgnored private var engine: TriggerEngine?

    public var settings: Settings {
        didSet {
            store.settings = settings
            send(.flagsChanged(settings.flags))
            if settings.appTriggerEnabled != oldValue.appTriggerEnabled
                || settings.chargingTriggerEnabled != oldValue.chargingTriggerEnabled
                || settings.externalDisplayTriggerEnabled != oldValue.externalDisplayTriggerEnabled
                || settings.triggerAppBundleIDs != oldValue.triggerAppBundleIDs {
                rebuildTriggers()
            }
        }
    }

    /// How the trigger set is built from the current settings. Factored into a
    /// seam so tests can inject `FakeTrigger` without touching the real IOKit,
    /// NSWorkspace or NSScreen — production uses `defaultTriggerFactory`, tests
    /// pass their own factory through the designated init below.
    typealias TriggerFactory = @MainActor (Settings) -> [any Trigger]

    public convenience init(
        assertions: AssertionManager = AssertionManager(
            backing: IOKitBacking(),
            reason: AssertionManager.defaultReason
        ),
        store: any SettingsStoring = UserDefaultsSettingsStore()
    ) {
        self.init(assertions: assertions, store: store, triggerFactory: Self.defaultTriggerFactory)
    }

    /// Designated init — takes a `triggerFactory` so tests can inject fakes.
    /// Not public: module-internal only. Production goes through the
    /// convenience init above; tests reach this one via `@testable import`.
    init(
        assertions: AssertionManager,
        store: any SettingsStoring,
        triggerFactory: @escaping TriggerFactory
    ) {
        self.assertions = assertions
        self.store = store
        self.triggerFactory = triggerFactory
        self.settings = store.settings
        self.state.flags = store.settings.flags

        if store.settings.activateOnLaunch {
            send(.toggledManually(true))
        }

        rebuildTriggers()
    }

    private static let defaultTriggerFactory: TriggerFactory = { settings in
        var triggers: [any Trigger] = []
        if settings.appTriggerEnabled, !settings.triggerAppBundleIDs.isEmpty {
            triggers.append(AppRunningTrigger(bundleIDs: settings.triggerAppBundleIDs))
        }
        if settings.chargingTriggerEnabled {
            triggers.append(PowerSourceTrigger())
        }
        if settings.externalDisplayTriggerEnabled {
            triggers.append(ExternalDisplayTrigger())
        }
        return triggers
    }

    public func send(_ event: CaffeineEvent) {
        state = reduce(state, event)
        apply()
        syncTicker()
    }

    // MARK: - User actions

    /// Toggle manually.
    ///
    /// Stopping (the `state.isActive` branch, which sends `.stopAll`) is
    /// DECISIVE: it clears manual, timer and EVERY trigger reason currently in
    /// `state`, but does NOT touch each trigger's internal baseline — for
    /// example `PowerSourceTrigger.isCharging` stays `true` if the Mac is still
    /// plugged in. A trigger only emits `.triggerFired` again on a REAL
    /// false→true transition (unplug, then plug back in), not on every status
    /// event that repeats an unchanged condition. So pressing Stop while
    /// charging really does stop, and does NOT switch itself back on seconds
    /// later just because the system sent another "still charging" notice.
    ///
    /// This is deliberate. Do not "fix" it by resetting trigger baselines on
    /// stopAll: that would make the rule re-activate on the very next status
    /// update while the condition had not changed at all, destroying the
    /// decisiveness of the Stop button.
    ///
    /// One accepted edge case, deliberately not papered over: if the user
    /// afterwards changes any setting that runs `rebuildTriggers()`, the new
    /// trigger set calls `refresh()` and may find the condition still true
    /// (still charging, say) and re-activate that rule immediately. That is the
    /// consistent consequence of "rule enabled + condition true → active when
    /// evaluated from scratch", so no extra state is added to block it.
    public func toggle() {
        if state.isActive {
            stop()
        } else {
            startIndefinite()
        }
    }

    /// Stop decisively.
    public func stop() {
        cancelTimerTask()
        send(.stopAll)
    }

    /// Turn on with no time limit. This also cancels a running timer: reduce
    /// already clears `timerEndsAt`, but the timer Task would outlive it and
    /// fire a late `.timerExpired` if it were not cancelled here.
    public func startIndefinite() {
        cancelTimerTask()
        send(.toggledManually(true))
    }

    /// Stay on for `minutes`, then let the timer switch itself off.
    /// `minutes` is clamped to the valid range — this is public API, and it
    /// cannot assume the caller checked first.
    public func startTimer(minutes: Int) {
        let minutes = min(
            max(minutes, Settings.durationRange.lowerBound),
            Settings.durationRange.upperBound
        )
        timerTask?.cancel()

        let seconds = TimeInterval(minutes * 60)
        let endsAt = Date().addingTimeInterval(seconds)
        timerTotalSeconds = seconds
        send(.startedTimer(until: endsAt))
        onTimerStarted?()

        timerTask = Task { [weak self] in
            // Sleep in short legs and RE-READ THE CLOCK, rather than sleeping
            // once for the full duration. `Task.sleep` only promises "at least
            // this long", and in between the machine can sleep and wake or the
            // user can change the system clock — a single long sleep would
            // never notice that drift, whereas this corrects itself within one
            // leg at most.
            while !Task.isCancelled {
                let remaining = endsAt.timeIntervalSinceNow
                guard remaining > 0 else { break }
                try? await Task.sleep(for: .seconds(min(remaining, 60)))
            }
            guard !Task.isCancelled, let self else { return }
            self.send(.timerExpired)
            // Only runs when the timer went the full distance. Pressing Stop or
            // switching to indefinite cancels this Task, so a timer the user
            // stopped never reports "time's up".
            self.onTimerExpired?()
        }
    }

    /// Explicit teardown at app exit. Safe to call more than once.
    public func shutdown() {
        cancelTimerTask()
        tickerTask?.cancel()
        tickerTask = nil
        engine?.stop()
        engine = nil
        assertions.releaseAll()
    }

    // MARK: - Derived for the UI

    /// Whether a countdown is running. The UI uses this to know whether it
    /// needs a clock at all — with no timer, nothing changes over time.
    public var isCountingDown: Bool {
        state.timerEndsAt != nil
    }

    /// Menu bar icon state AT a given instant.
    ///
    /// Takes `date` from the caller instead of reading `Date()`: the controller
    /// used to run a Task ticking once a second purely to update a `now`
    /// property, alongside the view layer's own `TimelineView` — two clocks for
    /// one job. Now the view layer keeps the only beat, and this function is
    /// pure in time, so it is testable without waiting on a real clock.
    public func iconState(at date: Date) -> MenuBarIconState {
        MenuBarIconState(
            isActive: state.isActive,
            progress: timerProgress(at: date),
            hasError: lastFailure != nil
        )
    }

    /// nil while on indefinitely — the icon draws a full cup rather than draining.
    private func timerProgress(at date: Date) -> Double? {
        guard let endsAt = state.timerEndsAt, timerTotalSeconds > 0 else { return nil }
        return max(0, endsAt.timeIntervalSince(date)) / timerTotalSeconds
    }

    // MARK: - Internals

    /// Start the tick when a timer exists, stop it when one does not. No idling
    /// clock: outside a countdown there is nothing time-dependent to draw.
    private func syncTicker() {
        guard state.timerEndsAt != nil else {
            tickerTask?.cancel()
            tickerTask = nil
            return
        }
        guard tickerTask == nil else { return }

        now = .now
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.now = .now
            }
        }
    }

    private func cancelTimerTask() {
        timerTask?.cancel()
        timerTask = nil
        // Back to zero so the progress calculation has no stale total to divide by.
        timerTotalSeconds = 0
    }

    /// Rebuild the trigger set from the current settings. Called whenever
    /// settings change. Not public: only `settings`' didSet and this module's
    /// init reach it — the app target neither needs nor should call it
    /// directly, which would bypass the deliberate "settings changed → rebuild"
    /// path.
    func rebuildTriggers() {
        engine?.stop()

        // TriggerEngine.stop() sets isRunning = false before calling each
        // trigger's stop(), and onChange is gated on isRunning — so the "off"
        // events an old trigger tries to emit while shutting down are swallowed
        // (deliberate; see the silentAfterStop test). That is why we have to
        // drain every leftover trigger reason by hand, REGARDLESS of whether
        // the new trigger set is empty. Draining only when it is empty would
        // strand any reason the new set happens to miss — disabling the app
        // trigger while the charging trigger stays on, say — forever. Not
        // .stopAll: that would clear manual and timer too, which is not what we
        // want here. Iterate over a snapshot, because send() mutates state.
        for reason in state.triggerReasons {
            send(.triggerCleared(reason))
        }

        let triggers = triggerFactory(settings)

        guard !triggers.isEmpty else {
            engine = nil
            return
        }

        // start() calls refresh() on each trigger straight away, so any reason
        // still true under the new configuration (still charging, say) emits
        // .triggerFired again immediately — no real state is lost.
        let engine = TriggerEngine(triggers: triggers)
        engine.onEvent = { [weak self] event in
            self?.send(event)
        }
        engine.start()
        self.engine = engine
    }

    /// The only place that touches `AssertionManager`. A failed create forces
    /// the state off and reports it rather than pretending to be on. A failed
    /// release does not invalidate the flags just created successfully, so it
    /// is only reported — the state is not forced off.
    private func apply() {
        do {
            try assertions.set(flags: state.effectiveFlags)
            if let releaseError = assertions.lastReleaseError {
                lastFailure = .couldNotRelease(releaseError)
            } else {
                lastFailure = nil
            }
        } catch let error as AssertionError {
            lastFailure = .couldNotHold(error)
            state = reduce(state, .stopAll)
            assertions.releaseAll()
        } catch {
            lastFailure = .unexpected(debugDescription: String(describing: error))
            state = reduce(state, .stopAll)
            assertions.releaseAll()
        }
    }
}
