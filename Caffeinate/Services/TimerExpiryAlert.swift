import AppKit
import Observation
import UserNotifications

/// Tells the user the timer has finished, three independent ways, because each
/// one can go silent on its own: a banner gets blocked by Do Not Disturb or
/// refused permission, sound is meaningless when the headphones are in another
/// room, and a flashing icon only helps if you happen to be looking at the menu
/// bar.
///
/// The banner deliberately carries NO sound: the chime is played here, so
/// whether or not the banner is blocked there is exactly one chime, never two.
@MainActor
@Observable
final class TimerExpiryAlert {
    /// Toggles while flashing; the menu bar label reads it to swap the icon.
    private(set) var isFlashing = false

    @ObservationIgnored private var flashTask: Task<Void, Never>?
    /// Incremented at the start of each new flashing run. An abandoned Task
    /// must not clean up on behalf of the next one — otherwise the old run
    /// clears the `isFlashing` flag the new one just set, and drops the
    /// reference to the new Task so a later `cancelFlashing()` has nothing to
    /// cancel.
    @ObservationIgnored private var flashGeneration = 0
    @ObservationIgnored private var authorizationRequested = false
    @ObservationIgnored private let presenter = ForegroundPresenter()

    /// How many flashes. Not infinite: an icon blinking forever on the menu bar
    /// is an irritation long after the message has landed.
    private static let flashCount = 6
    private static let flashInterval = Duration.milliseconds(280)

    /// Ask for notification permission when the user starts their FIRST timer,
    /// not at launch: asking right as they do the thing that leads to a
    /// notification is the moment the request makes sense. Asking at expiry
    /// would be too late — the permission dialog would appear instead of the
    /// notification itself.
    func prepareForTimer() {
        guard !authorizationRequested else { return }
        authorizationRequested = true

        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error {
                // Do not swallow it: without a banner there is still the chime
                // and the flashing icon, but the reason has to be visible in
                // the log.
                NSLog("Caffeinate: notification authorization failed: %@", error.localizedDescription)
            }
        }
    }

    /// `stillActive` means the timer ended but an automation rule is still
    /// holding the Mac awake. Say what is actually happening rather than
    /// asserting "your Mac can sleep now".
    func fire(stillActive: Bool) {
        playSound()
        startFlashing()
        postNotification(stillActive: stillActive)
    }

    func cancelFlashing() {
        flashTask?.cancel()
        flashTask = nil
        flashGeneration += 1
        isFlashing = false
    }

    private func playSound() {
        NSSound(named: "Glass")?.play()
    }

    private func startFlashing() {
        flashTask?.cancel()
        flashGeneration += 1
        let generation = flashGeneration

        flashTask = Task { [weak self] in
            for _ in 0..<Self.flashCount {
                guard !Task.isCancelled else { return }
                self?.isFlashing = true
                try? await Task.sleep(for: Self.flashInterval)
                guard !Task.isCancelled else { return }
                self?.isFlashing = false
                try? await Task.sleep(for: Self.flashInterval)
            }
            // Only clean up if this is still the current run.
            guard let self, self.flashGeneration == generation else { return }
            self.isFlashing = false
            self.flashTask = nil
        }
    }

    private func postNotification(stillActive: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Time’s up"
        content.body = stillActive
            ? "The timer finished, but an automatic rule is still keeping your Mac awake."
            : "Caffeinate turned off. Your Mac can sleep normally again."

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Caffeinate: posting the notification failed: %@", error.localizedDescription)
            }
        }
    }
}

/// By default macOS suppresses banners while the app is in the foreground —
/// sensible for an app with windows, wrong for this one: an open Settings
/// window does not mean the user is looking at it, and nothing in there reports
/// that the timer ended.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // No .sound: the chime comes from TimerExpiryAlert, so even a blocked
        // banner leaves exactly one.
        [.banner, .list]
    }
}
