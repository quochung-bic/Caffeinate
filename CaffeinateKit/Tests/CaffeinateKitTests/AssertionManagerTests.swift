import Testing
@testable import CaffeinateKit

@Suite("AssertionManager")
struct AssertionManagerTests {

    private func makeManager() -> (AssertionManager, FakeBacking) {
        let backing = FakeBacking()
        return (AssertionManager(backing: backing, reason: "Test"), backing)
    }

    @Test("bật từ rỗng thì tạo đúng các assertion được yêu cầu")
    func createsRequestedAssertions() throws {
        let (manager, backing) = makeManager()

        try manager.set(flags: [.system, .display])

        #expect(backing.calls == [.create(.system), .create(.display)])
        #expect(manager.heldFlags == [.system, .display])
    }

    @Test("đổi cờ lúc đang giữ thì chỉ tạo/huỷ phần chênh lệch")
    func onlyAppliesDelta() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.reset()

        // Bỏ .display, thêm .disk. .system phải được giữ nguyên, không đụng tới.
        try manager.set(flags: [.system, .disk])

        #expect(backing.calls == [.create(.disk), .release(2)])
        #expect(manager.heldFlags == [.system, .disk])
    }

    @Test("gọi lại với cùng bộ cờ thì không sinh lệnh nào")
    func idempotent() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .disk])
        backing.reset()

        try manager.set(flags: [.system, .disk])

        #expect(backing.calls.isEmpty)
        #expect(manager.heldFlags == [.system, .disk])
    }

    @Test("đặt về rỗng thì giải phóng hết")
    func releasesAll() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.reset()

        try manager.set(flags: [])

        #expect(backing.calls == [.release(1), .release(2)])
        #expect(manager.heldFlags == [])
    }

    @Test("create thất bại thì giải phóng sạch và ném lỗi, không để lại trạng thái nửa vời")
    func rollsBackOnFailure() throws {
        let (manager, backing) = makeManager()
        backing.failingFlags = [.disk]

        #expect(throws: AssertionError.self) {
            try manager.set(flags: [.system, .display, .disk])
        }

        // .system và .display đã tạo (id 1, 2) phải được huỷ lại.
        #expect(backing.calls == [
            .create(.system), .create(.display), .release(1), .release(2),
        ])
        #expect(manager.heldFlags == [])
    }

    @Test("release thất bại trong set(flags:) thì ghi lại lỗi, vẫn bỏ cờ khỏi heldFlags, và không ném")
    func recordsReleaseFailureDuringSet() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.failingReleaseIDs = [2] // id của .display

        try manager.set(flags: [.system])

        #expect(manager.heldFlags == [.system])
        #expect(manager.lastReleaseError?.flag == .display)
    }

    @Test("release thất bại trong releaseAll() thì ghi lại lỗi")
    func recordsReleaseFailureDuringReleaseAll() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.failingReleaseIDs = [1] // id của .system

        manager.releaseAll()

        #expect(manager.heldFlags == [])
        #expect(manager.lastReleaseError?.flag == .system)
    }

    @Test("một lượt giải phóng thành công hoàn toàn sau đó thì xoá lỗi cũ")
    func clearsReleaseErrorAfterSuccessfulCycle() throws {
        let (manager, backing) = makeManager()
        try manager.set(flags: [.system, .display])
        backing.failingReleaseIDs = [2] // id của .display
        try manager.set(flags: [.system])
        #expect(manager.lastReleaseError != nil)

        // Lượt sau, release .system thành công hoàn toàn -> lỗi cũ phải biến mất.
        backing.failingReleaseIDs = []
        try manager.set(flags: [])

        #expect(manager.lastReleaseError == nil)
        #expect(manager.heldFlags == [])
    }

    @Test("set(flags:) chỉ tạo (không release) thì không xoá lỗi release cũ")
    func doesNotClearErrorOnCreateOnlyOperation() throws {
        let (manager, backing) = makeManager()
        // Bước 1: tạo một số cờ
        try manager.set(flags: [.system, .display])

        // Bước 2: gây lỗi release để đặt lastReleaseError
        backing.failingReleaseIDs = [2] // id của .display
        try manager.set(flags: [.system])
        #expect(manager.lastReleaseError != nil)

        // Bước 3: chỉ tạo cờ mới, không release cờ nào
        // lastReleaseError phải vẫn tồn tại (không được xoá)
        backing.failingReleaseIDs = []
        try manager.set(flags: [.system, .disk])

        #expect(manager.lastReleaseError != nil)
        #expect(manager.heldFlags == [.system, .disk])
    }
}
