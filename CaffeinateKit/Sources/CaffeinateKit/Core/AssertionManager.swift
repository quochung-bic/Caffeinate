import Foundation

/// Holds the set of live assertions and keeps it in sync with the desired flags.
///
/// Invariant: `held` always reflects the assertions that actually exist. If a
/// create fails partway through, everything created during that pass — and
/// everything held from before — is released. Better fully off than letting the
/// user believe the Mac is held awake when only half of it is.
public final class AssertionManager {
    /// The assertion name the app actually uses.
    ///
    /// MUST be pure ASCII. `IOPMAssertionCreateWithName` accepts accented text
    /// without complaint, but `pmset -g assertions` then prints `named: ""` —
    /// the assertion becomes anonymous at exactly the moment a user is using
    /// pmset to check whether the app really is holding the Mac awake.
    ///
    /// It is also never localized: this string surfaces at the OS level, for
    /// command-line tools and system logs, not in the interface. Translating it
    /// would break diagnosability.
    public static let defaultReason = "Caffeinate is keeping this Mac awake"

    private let backing: PowerAssertionBacking
    private let reason: String
    private var held: [AssertionFlags: UInt32] = [:]

    /// The most recent release error not yet cleared by a fully successful
    /// release pass. Nothing fails silently: if IOKit refuses a release, the
    /// caller (CaffeineController) must be able to read it and tell the user.
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

        // A failed release must not propagate: the assertions the caller just
        // asked for (toCreate) exist and are valid, and a botched release does
        // not invalidate them. The error is recorded via lastReleaseError
        // rather than swallowed.
        release(toRelease)
    }

    /// Release every assertion. Safe to call more than once.
    public func releaseAll() {
        release(AssertionFlags.all)
    }

    /// Release a batch of flags, updating `held` and `lastReleaseError`.
    /// A flag is always dropped from `held` whether or not its release
    /// reported an error — no retries, no ghost entries. `lastReleaseError` is
    /// cleared only when a pass actually released at least one flag and none
    /// of them failed.
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

    /// The backing only knows IDs, so it throws with an empty flag set. Here we
    /// know which flag it was, so we re-wrap the error into something the user
    /// can be told.
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
