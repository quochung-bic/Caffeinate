/// The four aspects of "stay awake" that can be switched on independently.
/// Each single flag maps to one IOKit assertion.
///
/// There is deliberately no `displayName` here. This type is data, not
/// presentation: attaching user-facing text would force the core to know about
/// how things are shown. Display names live in the app layer.
public struct AssertionFlags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let system   = AssertionFlags(rawValue: 1 << 0)
    public static let display  = AssertionFlags(rawValue: 1 << 1)
    public static let disk     = AssertionFlags(rawValue: 1 << 2)
    public static let userIdle = AssertionFlags(rawValue: 1 << 3)

    /// Starting configuration: keep the system awake, nothing more. Let macOS
    /// turn the display off on the user's own schedule — keeping the screen lit
    /// is expensive and rarely wanted, so it has to be opted into.
    public static let `default`: AssertionFlags = [.system]

    /// The four single flags, in the canonical order used everywhere (UI,
    /// tests, diagnostics). Ordered from "rarely unwanted" to "rarely wanted".
    public static let all: [AssertionFlags] = [.system, .display, .disk, .userIdle]

    /// Stable identifier, used by the app layer to look up display text and by
    /// logging and diagnostics. Meaningful only for single flags; combinations
    /// return `nil`.
    public var identifier: String? {
        switch self {
        case .system:   "system"
        case .display:  "display"
        case .disk:     "disk"
        case .userIdle: "userIdle"
        default:        nil
        }
    }
}
