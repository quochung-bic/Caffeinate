import Foundation
import Testing
@testable import CaffeinateKit

@Suite("IOKitBacking", .serialized)
struct IOKitBackingTests {

    @Test("creates and releases all four real assertion types")
    func createAndReleaseEachFlag() throws {
        let backing = IOKitBacking()

        for flag in AssertionFlags.all {
            let id = try backing.create(flag, reason: "CaffeinateKit test")
            #expect(id != 0)
            try backing.release(id)
        }
    }

    @Test("a created assertion shows up in pmset")
    func assertionIsVisibleToSystem() throws {
        let backing = IOKitBacking()
        let id = try backing.create(.display, reason: "CaffeinateKitProbe")

        let output = shell("/usr/bin/pmset", ["-g", "assertions"])
        try backing.release(id)

        #expect(output.contains("CaffeinateKitProbe"))
    }

    /// The test above uses a made-up ASCII string, so it would NOT have caught
    /// the real bug: a shipped build once named the assertion with accented
    /// text, which IOKit accepted without complaint while `pmset` printed
    /// `named: ""` — leaving the user no way to tell which assertion was the
    /// app's. The string actually used in production has to be checked itself.
    @Test("the production assertion name is readable in pmset and not empty")
    func productionReasonIsVisibleToSystem() throws {
        let backing = IOKitBacking()
        let id = try backing.create(.display, reason: AssertionManager.defaultReason)

        let output = shell("/usr/bin/pmset", ["-g", "assertions"])
        try backing.release(id)

        #expect(output.contains(AssertionManager.defaultReason))
    }
}

private func shell(_ path: String, _ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}
