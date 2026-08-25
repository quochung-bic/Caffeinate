import Foundation
@testable import CaffeinateKit

/// Records the sequence of commands sent to IOKit so tests can assert on it.
final class FakeBacking: PowerAssertionBacking, @unchecked Sendable {
    enum Call: Equatable {
        case create(AssertionFlags)
        case release(UInt32)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var nextID: UInt32 = 1
    private var idToFlag: [UInt32: AssertionFlags] = [:]

    /// Which flags make create throw.
    var failingFlags: AssertionFlags = []

    /// Which IDs make release throw.
    var failingReleaseIDs: Set<UInt32> = []

    var calls: [Call] {
        lock.withLock { _calls }
    }

    func reset() {
        lock.withLock { _calls = [] }
    }

    func create(_ flag: AssertionFlags, reason: String) throws -> UInt32 {
        if failingFlags.contains(flag) {
            throw AssertionError(flag: flag, code: -536870212)
        }
        return lock.withLock {
            let id = nextID
            idToFlag[id] = flag
            _calls.append(.create(flag))
            nextID += 1
            return id
        }
    }

    func release(_ id: UInt32) throws {
        if failingReleaseIDs.contains(id) {
            let flag = lock.withLock { idToFlag[id] } ?? []
            throw AssertionError(flag: flag, code: -536870210)
        }
        lock.withLock { _calls.append(.release(id)) }
    }
}

@MainActor
final class FakeTrigger: Trigger {
    var onChange: (@MainActor (TriggerReason, Bool) -> Void)?
    private(set) var started = false
    private(set) var stopped = false

    /// The last active state reported for each reason — modelling the internal
    /// baseline of a real trigger (`PowerSourceTrigger.isCharging`,
    /// `ExternalDisplayTrigger.hasExternal`, `AppRunningTrigger`'s `reported`
    /// dictionary).
    private var lastReported: [TriggerReason: Bool] = [:]

    func start() { started = true }
    func stop() { stopped = true }

    /// Simulate the trigger changing state. Calls `onChange` only when the
    /// state ACTUALLY differs from the last report for that reason — the same
    /// "report only on a real change" guard every real trigger has (see
    /// `PowerSourceTrigger.refresh()`, `ExternalDisplayTrigger.refresh()`, and
    /// the dictionary diff in `AppRunningTrigger.refresh()`). Calling
    /// `fire(reason, active: true)` twice in a row produces no second event —
    /// an `active: false` has to come in between to model a real transition.
    func fire(_ reason: TriggerReason, active: Bool) {
        guard lastReported[reason] != active else { return }
        lastReported[reason] = active
        onChange?(reason, active)
    }
}

/// An in-memory SettingsStoring — never touches UserDefaults, so tests stay
/// isolated and leak no state between runs.
final class InMemorySettingsStore: SettingsStoring {
    var settings: Settings

    init(settings: Settings = Settings()) {
        self.settings = settings
    }
}
