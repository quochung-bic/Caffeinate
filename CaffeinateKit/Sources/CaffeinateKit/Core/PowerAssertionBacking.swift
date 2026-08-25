/// A raw IOKit error from creating or releasing an assertion.
///
/// Deliberately no `localizedDescription`: wording shown to the user is the app
/// layer's job. This type carries only the facts that layer needs to build a
/// sentence — which flag, and which IOReturn code.
public struct AssertionError: Error, Equatable, Sendable {
    public let flag: AssertionFlags
    public let code: Int32

    public init(flag: AssertionFlags, code: Int32) {
        self.flag = flag
        self.code = code
    }
}

/// What went wrong, and how the consequences differ.
///
/// Telling these two apart matters and is not decoration: after a failed
/// create the app is NOT holding the Mac awake (state was forced off), whereas
/// after a failed release it IS still holding exactly what the user asked for.
/// The user needs to read two different sentences.
public enum AssertionFailure: Error, Equatable, Sendable {
    /// An assertion could not be created. State has been forced off.
    case couldNotHold(AssertionError)
    /// An old assertion could not be released. The flags just requested remain valid.
    case couldNotRelease(AssertionError)
    /// An error that did not come from IOKit. The raw description is kept so it
    /// stays traceable; the app layer wraps it in a sentence rather than
    /// printing it bare.
    case unexpected(debugDescription: String)
}

/// Abstraction over IOKit so tests never touch the real system.
public protocol PowerAssertionBacking: Sendable {
    func create(_ flag: AssertionFlags, reason: String) throws -> UInt32
    func release(_ id: UInt32) throws
}
