import SwiftUI
import CaffeinateKit

/// The menu bar icon.
///
/// # Why there is no `TimelineView` here
///
/// A `MenuBarExtra` label is not an ordinary view: SwiftUI renders it into an
/// `NSStatusItem`, and inside that frame `TimelineView` does NOT tick.
/// Measured, not guessed — over eight seconds of an active countdown, a label
/// built on `TimelineView(.periodic(by: 1))` redrew twice, both times because
/// state changed. The icon sat at full for the whole timer, losing the one
/// thing that earns it a place on the menu bar.
///
/// The only reliable way to make the label redraw is to read an `@Observable`
/// property that genuinely changes: `controller.now`, ticked by the controller
/// and running only while a timer exists. Outside a countdown this view never
/// reads `now`, so it has no time-based dependency at all — it redraws only
/// when state changes.
struct MenuBarLabel: View {
    let controller: CaffeineController
    let expiryAlert: TimerExpiryAlert

    var body: some View {
        Image(nsImage: nsImage(at: controller.isCountingDown ? controller.now : .now))
    }

    private func nsImage(at date: Date) -> NSImage {
        let description = controller.iconAccessibilityDescription(at: date)
        // The "off" beat of the expiry flash.
        if expiryAlert.isFlashing {
            return MenuBarIcon.blankImage(accessibilityDescription: description)
        }
        return MenuBarIcon.cachedImage(
            for: controller.iconState(at: date),
            accessibilityDescription: description
        )
    }
}
