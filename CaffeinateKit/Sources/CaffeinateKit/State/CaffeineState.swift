import Foundation

/// Why an automation rule is asking to keep the Mac awake.
///
/// `.app` carries the display name macOS reports for that application — data
/// read from the system rather than interface text written by this app, so it
/// belongs here.
public enum TriggerReason: Hashable, Sendable {
    case app(String)
    case charging
    case externalDisplay
}

extension TriggerReason: Comparable {
    /// Precedence when several rules hold at once: whichever SAYS THE MOST wins.
    /// "Xcode is running" is far more useful than "plugged in".
    ///
    /// This ordering used to fall out of sorting the display strings, which
    /// meant the interface language silently decided which reason was shown.
    /// Ranking explicitly here keeps the order independent of wording.
    private var priority: (Int, String) {
        switch self {
        case .app(let name):    (0, name)
        case .charging:         (1, "")
        case .externalDisplay:  (2, "")
        }
    }

    public static func < (lhs: TriggerReason, rhs: TriggerReason) -> Bool {
        lhs.priority < rhs.priority
    }
}

/// The winning source, used to show "On because: …".
public enum ActiveReason: Equatable, Sendable {
    case manual
    case timer(until: Date)
    case trigger(TriggerReason)
}

/// The app's entire state. The single source of truth.
public struct CaffeineState: Equatable, Sendable {
    public var manual: Bool = false
    public var timerEndsAt: Date? = nil
    public var triggerReasons: Set<TriggerReason> = []
    /// The flags the user configured — applied if and only if active.
    public var flags: AssertionFlags = .default

    public init() {}

    public var isActive: Bool {
        activeReason != nil
    }

    /// The flags actually sent down to IOKit.
    public var effectiveFlags: AssertionFlags {
        isActive ? flags : []
    }

    /// Precedence: manual > timer > automation rule.
    public var activeReason: ActiveReason? {
        if manual { return .manual }
        if let endsAt = timerEndsAt { return .timer(until: endsAt) }
        // Sorted so the reason shown is stable from one read to the next.
        if let first = triggerReasons.min() { return .trigger(first) }
        return nil
    }
}
