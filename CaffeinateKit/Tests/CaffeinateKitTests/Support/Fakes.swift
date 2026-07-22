import Foundation
@testable import CaffeinateKit

/// Ghi lại chuỗi lệnh gửi tới IOKit để test kiểm chứng.
final class FakeBacking: PowerAssertionBacking, @unchecked Sendable {
    enum Call: Equatable {
        case create(AssertionFlags)
        case release(UInt32)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var nextID: UInt32 = 1
    private var idToFlag: [UInt32: AssertionFlags] = [:]

    /// Cờ nào sẽ khiến create ném lỗi.
    var failingFlags: AssertionFlags = []

    /// ID nào sẽ khiến release ném lỗi.
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

    /// Trạng thái active gần nhất đã báo cho mỗi lý do — mô phỏng baseline
    /// nội bộ của trigger thật (`PowerSourceTrigger.isCharging`,
    /// `ExternalDisplayTrigger.hasExternal`, dictionary `reported` của
    /// `AppRunningTrigger`).
    private var lastReported: [TriggerReason: Bool] = [:]

    func start() { started = true }
    func stop() { stopped = true }

    /// Giả lập trigger đổi trạng thái. Chỉ gọi `onChange` khi trạng thái
    /// THỰC SỰ đổi so với lần báo trước cho cùng lý do — giống hệt guard
    /// "chỉ báo khi thực sự đổi" mà mọi trigger thật đều có (xem
    /// `PowerSourceTrigger.refresh()`, `ExternalDisplayTrigger.refresh()`,
    /// diff dictionary trong `AppRunningTrigger.refresh()`). Gọi lại
    /// `fire(reason, active: true)` hai lần liên tiếp không tạo ra sự kiện
    /// thứ hai — phải có một `active: false` chen giữa để mô phỏng chuyển
    /// tiếp thật.
    func fire(_ reason: TriggerReason, active: Bool) {
        guard lastReported[reason] != active else { return }
        lastReported[reason] = active
        onChange?(reason, active)
    }
}

/// SettingsStoring trong bộ nhớ — không chạm UserDefaults, để test cô lập
/// và không rò rỉ trạng thái giữa các lần chạy.
final class InMemorySettingsStore: SettingsStoring {
    var settings: Settings

    init(settings: Settings = Settings()) {
        self.settings = settings
    }
}
