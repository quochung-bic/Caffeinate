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
