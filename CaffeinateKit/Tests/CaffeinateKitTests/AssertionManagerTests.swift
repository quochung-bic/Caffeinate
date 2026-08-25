import Testing
@testable import CaffeinateKit

@Suite("AssertionManager")
struct AssertionManagerTests {

    private func makeManager() -> (AssertionManager, FakeBacking) {
        let backing = FakeBacking()
        return (AssertionManager(backing: backing, reason: "Test"), backing)
    }

    @Test("turning on from empty creates exactly the assertions requested")
    func createsRequestedAssertions() throws {
        let (manager, backing) = makeManager()

        try manager.set(flags: [.system, .display])

        #expect(backing.calls == [.create(.system), .create(.display)])
        #expect(manager.heldFlags == [.system, .display])
    }

    @Test("changing flags while held applies only the difference")
    func onlyAppliesDelta() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.reset()

        // Drop .display, add .disk. .system must be left completely alone.
        try manager.set(flags: [.system, .disk])

        #expect(backing.calls == [.create(.disk), .release(2)])
        #expect(manager.heldFlags == [.system, .disk])
    }

    @Test("setting the same flags again issues no commands")
    func idempotent() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .disk])
        backing.reset()

        try manager.set(flags: [.system, .disk])

        #expect(backing.calls.isEmpty)
        #expect(manager.heldFlags == [.system, .disk])
    }

    @Test("setting an empty set releases everything")
    func releasesAll() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.reset()

        try manager.set(flags: [])

        #expect(backing.calls == [.release(1), .release(2)])
        #expect(manager.heldFlags == [])
    }

    @Test("a failed create rolls back completely and rethrows, leaving nothing half-held")
    func rollsBackOnFailure() throws {
        let (manager, backing) = makeManager()
        backing.failingFlags = [.disk]

        #expect(throws: AssertionError.self) {
            try manager.set(flags: [.system, .display, .disk])
        }

        // .system and .display were created (ids 1 and 2) and must be released
        // again. No flag stays held.
        #expect(backing.calls == [
            .create(.system), .create(.display), .release(1), .release(2),
        ])
        #expect(manager.heldFlags == [])
    }

    @Test("a failed release inside set(flags:) is recorded, still drops the flag, and does not throw")
    func recordsReleaseFailureDuringSet() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.failingReleaseIDs = [2] // id of .display

        try manager.set(flags: [.system])

        #expect(manager.heldFlags == [.system])
        #expect(manager.lastReleaseError?.flag == .display)
    }

    @Test("a failed release inside releaseAll() is recorded")
    func recordsReleaseFailureDuringReleaseAll() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.failingReleaseIDs = [1] // id of .system

        manager.releaseAll()

        #expect(manager.heldFlags == [])
        #expect(manager.lastReleaseError?.flag == .system)
    }

    @Test("a later fully successful release pass clears the recorded error")
    func clearsReleaseErrorAfterSuccessfulCycle() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.failingReleaseIDs = [2] // id of .display
        try manager.set(flags: [.system])
        #expect(manager.lastReleaseError != nil)

        // Next pass releases .system cleanly, so the old error must disappear.
        backing.failingReleaseIDs = []
        try manager.set(flags: [])

        #expect(manager.lastReleaseError == nil)
        #expect(manager.heldFlags == [])
    }

    @Test("a create-only set(flags:) leaves an earlier release error standing")
    func doesNotClearErrorOnCreateOnlyOperation() throws {
        let (manager, backing) = makeManager()
        // Step 1: hold some flags.
        try manager.set(flags: [.system, .display])

        // Step 2: force a release failure so lastReleaseError is set.
        backing.failingReleaseIDs = [2] // id of .display
        try manager.set(flags: [.system])
        #expect(manager.lastReleaseError != nil)

        // Step 3: only create a new flag, releasing nothing.
        // lastReleaseError must survive — nothing has disproved it.
        backing.failingReleaseIDs = []
        try manager.set(flags: [.system, .disk])

        #expect(manager.lastReleaseError != nil)
        #expect(manager.heldFlags == [.system, .disk])
    }
}
