import Foundation
import IOKit.pwr_mgt

/// Cài đặt thật trên IOKit. Đây là chỗ DUY NHẤT trong codebase gọi IOKit
/// power management.
public struct IOKitBacking: PowerAssertionBacking {

    public init() {}

    public func create(_ flag: AssertionFlags, reason: String) throws -> UInt32 {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            Self.assertionType(for: flag) as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            throw AssertionError(flag: flag, code: result)
        }
        return id
    }

    public func release(_ id: UInt32) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else {
            // Cờ để rỗng: ở tầng này chỉ còn cái ID, không còn biết nó thuộc cờ
            // nào. AssertionManager biết, và nó bọc lại lỗi với cờ đúng.
            throw AssertionError(flag: [], code: result)
        }
    }

    private static func assertionType(for flag: AssertionFlags) -> String {
        switch flag {
        case .system:   kIOPMAssertionTypeNoIdleSleep
        case .display:  kIOPMAssertionTypeNoDisplaySleep
        case .disk:     kIOPMAssertPreventDiskIdle
        case .userIdle: kIOPMAssertionTypePreventUserIdleSystemSleep
        default:
            preconditionFailure(
                "assertionType(for:) chỉ nhận cờ đơn, nhận được: \(flag.rawValue)"
            )
        }
    }
}
