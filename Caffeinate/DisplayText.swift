import Foundation
import CaffeinateKit

// The bridge from core data to the words on screen.
//
// `CaffeinateKit` deliberately holds no display strings: it returns types, and
// this file is the only place that turns them into something readable. The
// split is worth keeping even with a single language — it lets the core be
// tested without any notion of presentation, and means rewording the interface
// never reaches into the state machine.

/// Whole-number plural forms.
///
/// The String Catalog used to handle this. With one language it is cheaper to
/// spell out, and it keeps "1 minute" from ever rendering as "1 minutes".
enum Plural {
    static func minutes(_ count: Int) -> String {
        count == 1 ? "1 minute" : "\(count) minutes"
    }
}

extension AssertionFlags {
    /// Display name for a single flag. Combinations have no name — the user
    /// never sees one.
    var displayName: String {
        switch self {
        case .system:   "System"
        case .display:  "Display"
        case .disk:     "Disk"
        case .userIdle: "Idle"
        default:        unreachableName
        }
    }

    /// One line on what this flag actually holds. Nobody is obliged to know
    /// what a "user idle assertion" is.
    var explanation: String {
        switch self {
        case .system:   "Your Mac won’t go to sleep on its own."
        case .display:  "The display never turns off. Costs battery — only turn it on when you need to keep watching the screen."
        case .disk:     "Disks won’t spin down."
        case .userIdle: "Your Mac won’t count you as idle."
        default:        unreachableName
        }
    }

    /// Unreachable in practice: the interface only ever iterates
    /// `AssertionFlags.all`, which is single flags. Getting here would be a
    /// programming error, and a visible code beats a blank space.
    private var unreachableName: String {
        "AssertionFlags(\(rawValue))"
    }
}

extension TriggerReason {
    var displayText: String {
        switch self {
        case .app(let name):    "\(name) is running"
        case .charging:         "Plugged into power"
        case .externalDisplay:  "An external display is connected"
        }
    }
}

extension ActiveReason {
    var displayText: String {
        switch self {
        case .manual:              "Turned on manually"
        case .timer:               "Timer"
        case .trigger(let reason): reason.displayText
        }
    }

    /// A symbol to go with the reason. Four different sources should look
    /// different at a glance, not only read differently.
    var symbolName: String {
        switch self {
        case .manual:                       "hand.tap.fill"
        case .timer:                        "timer"
        case .trigger(.app):                "app.badge.checkmark"
        case .trigger(.charging):           "powerplug.fill"
        case .trigger(.externalDisplay):    "display.2"
        }
    }
}

extension AssertionFailure {
    /// The error sentence shown to the user.
    ///
    /// The first two cases deliberately spell out DIFFERENT consequences — a
    /// failed create means the Mac is no longer being kept awake, a failed
    /// release means it still is, exactly as asked. Collapsing them into one
    /// "something went wrong" would drop the very thing the user needs in order
    /// to decide what to do next.
    var message: String {
        switch self {
        case .couldNotHold(let error):
            "Couldn’t keep your Mac awake: the system refused \(error.flag.displayName) (code \(error.code)). Caffeinate turned off."
        case .couldNotRelease(let error):
            "Couldn’t release \(error.flag.displayName) (code \(error.code)). Your Mac is still being kept awake exactly as you asked."
        case .unexpected(let debugDescription):
            "Unexpected error: \(debugDescription)"
        }
    }
}

extension CaffeineController {
    /// What VoiceOver reads when it reaches the menu bar icon. The icon is the
    /// only surface that is always present, so it has to state the whole status
    /// without the user opening the panel.
    func iconAccessibilityDescription(at date: Date) -> String {
        if lastFailure != nil {
            return "Caffeinate hit an error"
        }
        guard state.isActive else {
            return "Caffeinate is off"
        }
        guard let endsAt = state.timerEndsAt else {
            return "Caffeinate is on, indefinitely"
        }
        let minutes = Int(max(0, endsAt.timeIntervalSince(date)) / 60)
        return "Caffeinate is on, \(Plural.minutes(minutes)) left"
    }
}
