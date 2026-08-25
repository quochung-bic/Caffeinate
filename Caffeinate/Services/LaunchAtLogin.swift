import Foundation
import Observation
import ServiceManagement

/// A wrapper around `SMAppService`.
///
/// The state is never mirrored into UserDefaults: `SMAppService.mainApp.status`
/// is the single source of truth. The user can disable the login item from
/// System Settings > General > Login Items without the app hearing about it, so
/// keeping a copy would mean displaying something wrong sooner or later.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var lastError: String?

    /// Read straight from the system every time, never cached.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = Self.explain(error, whileEnabling: enabled)
        }
    }

    /// The most common cause is not "the system went wrong" but the app running
    /// from outside /Applications — `SMAppService` refuses to register a bundle
    /// anywhere else. Say so plainly, because the user can fix that; "the
    /// operation failed" leaves them nothing to act on.
    private static func explain(_ error: any Error, whileEnabling enabling: Bool) -> String {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasPrefix("/Applications") else {
            return """
                Couldn’t change the startup setting: the app must live in \
                /Applications. It’s currently running from \(bundlePath).
                """
        }
        return enabling
            ? "Couldn’t turn on launch at login: \(error.localizedDescription)"
            : "Couldn’t turn off launch at login: \(error.localizedDescription)"
    }
}
