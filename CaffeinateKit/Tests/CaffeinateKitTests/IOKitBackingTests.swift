import Foundation
import Testing
@testable import CaffeinateKit

@Suite("IOKitBacking", .serialized)
struct IOKitBackingTests {

    @Test("tạo rồi giải phóng được cả bốn loại assertion thật")
    func createAndReleaseEachFlag() throws {
        let backing = IOKitBacking()

        for flag in AssertionFlags.all {
            let id = try backing.create(flag, reason: "CaffeinateKit test")
            #expect(id != 0)
            try backing.release(id)
        }
    }

    @Test("assertion đã tạo hiện ra trong pmset")
    func assertionIsVisibleToSystem() throws {
        let backing = IOKitBacking()
        let id = try backing.create(.display, reason: "CaffeinateKitProbe")

        let output = shell("/usr/bin/pmset", ["-g", "assertions"])
        try backing.release(id)

        #expect(output.contains("CaffeinateKitProbe"))
    }

    /// Bài test trên dùng chuỗi ASCII tự chế nên KHÔNG bắt được lỗi thật: bản
    /// phát hành từng đặt tên assertion bằng tiếng Việt có dấu, IOKit nhận
    /// không báo lỗi nhưng pmset in ra `named: ""` — người dùng không còn cách
    /// nào nhận ra assertion nào là của app. Phải kiểm chính chuỗi dùng thật.
    @Test("tên assertion dùng thật đọc được trong pmset, không rỗng")
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
