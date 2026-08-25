import Testing
@testable import CaffeinateKit

@Suite("AssertionFlags")
struct AssertionFlagsTests {

    @Test("by default holds the system only, leaving the display to macOS")
    func defaultFlags() {
        #expect(AssertionFlags.default == [.system])
    }

    @Test("all lists exactly the four single flags, with no duplicates")
    func allEnumeratesFourSingleFlags() {
        #expect(AssertionFlags.all.count == 4)
        #expect(Set(AssertionFlags.all.map(\.rawValue)).count == 4)
        for flag in AssertionFlags.all {
            #expect(flag.rawValue.nonzeroBitCount == 1)
        }
    }

    @Test("every single flag has its own identifier, combinations have none")
    func identifiersAreDistinctForSingleFlags() {
        let ids = AssertionFlags.all.map(\.identifier)
        #expect(ids == ["system", "display", "disk", "userIdle"])
        // These identifiers key the display text in the app layer and label log
        // output, so they have to stay stable; changing one breaks both the
        // wording and diagnosability.
        #expect(AssertionFlags([.system, .display]).identifier == nil)
        #expect(AssertionFlags([]).identifier == nil)
    }

    @Test("set subtraction yields the difference")
    func setSubtraction() {
        let desired: AssertionFlags = [.system, .display, .disk]
        let held: AssertionFlags = [.system, .userIdle]
        #expect(desired.subtracting(held) == [.display, .disk])
        #expect(held.subtracting(desired) == [.userIdle])
    }
}
