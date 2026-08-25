import Foundation
import IOKit.pwr_mgt

/// The real IOKit implementation. This is the ONLY place in the codebase that
/// calls IOKit power management.
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
            // Empty flag set: at this level only the ID survives, and it no
            // longer says which flag it belonged to. AssertionManager knows,
            // and re-wraps the error with the right flag.
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
                "assertionType(for:) takes single flags only, got: \(flag.rawValue)"
            )
        }
    }
}
