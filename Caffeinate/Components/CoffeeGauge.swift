import SwiftUI

/// The coffee cup plus the time remaining. No progress ring: the coffee level
/// IS the progress bar, and adding a ring would say the same thing twice.
///
/// The time is always recomputed from `endsAt` rather than counted down in a
/// variable, so sleeping and waking never leaves the number wrong.
///
/// # Three clocks, not one
///
/// This block used to sit inside ONE `TimelineView` running at 24 fps, so every
/// frame rebuilt the accessibility element wrapping it. The cost was not just
/// CPU: the accessibility tree never settled, VoiceOver lost its anchor, and a
/// UI test query against it ran until it timed out.
///
/// Now each part ticks at the rate it actually needs:
/// - the cup (steam plus coffee level): 20 fps, and stopped entirely when inactive;
/// - the countdown number: 1 Hz, and only present when a timer really exists;
/// - the accessibility label: NO clock at all — it says "timer until 15:47"
///   rather than "14 minutes left", so it holds still for the whole timer. A
///   label that changes every second is a label VoiceOver reads over and over,
///   which is worse than none.
struct CoffeeGauge: View {
    let endsAt: Date?
    let totalSeconds: TimeInterval
    let isActive: Bool
    var size: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Contract with `SmokeTests`.
    static let accessibilityIdentifier = "caffeine-gauge"

    /// 20 fps, not 24 or 60.
    ///
    /// Steam is slow, organic motion; at 20 fps the eye cannot tell it from 60,
    /// while the machine draws three times less. For an app whose whole reason
    /// to exist is power management, burning GPU to smooth a wisp of steam
    /// would contradict itself.
    private static let animatedInterval = 1.0 / 20.0

    var body: some View {
        VStack(spacing: size * 0.04) {
            cup
            readout
        }
        .animation(.easeOut(duration: 0.45), value: mode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // A fixed identifier so the UI tests can go straight to this element
        // instead of scanning the tree by label: the tree is animating, and a
        // broad query has to wait for it to settle, which it never does.
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    // MARK: - Cup

    private var cup: some View {
        // With reduced motion the steam is off, so only the coffee level needs
        // updating — 1 Hz is plenty. While inactive the timeline stops entirely
        // rather than redrawing a motionless cup.
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1 : Self.animatedInterval,
                paused: !isActive
            )
        ) { context in
            CoffeeCup(
                fill: fill(at: context.date),
                isActive: isActive,
                steamPhase: context.date.timeIntervalSinceReferenceDate * 0.3,
                showSteam: isActive && !reduceMotion,
                size: size
            )
        }
        .accessibilityHidden(true)
    }

    // MARK: - Numbers

    @ViewBuilder
    private var readout: some View {
        if let endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                readout(remaining: max(0, endsAt.timeIntervalSince(context.date)))
            }
        } else {
            // With no timer there is nothing to count: "∞" and "—" hold still,
            // so no timeline is created at all.
            readout(remaining: nil)
        }
    }

    private func readout(remaining: TimeInterval?) -> some View {
        VStack(spacing: 2) {
            Text(numberLabel(remaining: remaining))
                .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(caption)
                .font(.system(size: max(9, size * 0.062), weight: .semibold))
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Derived

    private enum Mode: Int { case off, indefinite, countdown }

    private var mode: Mode {
        guard isActive else { return .off }
        return endsAt == nil ? .indefinite : .countdown
    }

    private func fill(at now: Date) -> Double {
        guard isActive else { return 0 }
        guard let endsAt, totalSeconds > 0 else { return 1 }
        let remaining = max(0, endsAt.timeIntervalSince(now))
        return min(max(remaining / totalSeconds, 0), 1)
    }

    private func numberLabel(remaining: TimeInterval?) -> String {
        guard let remaining else { return isActive ? "∞" : "—" }
        let total = Int(remaining)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var caption: String {
        switch mode {
        case .countdown:    "left"
        case .indefinite:   "indefinite"
        case .off:          "off"
        }
    }

    /// This label is a contract with the UI tests — it is the most reliable way
    /// to read the active state from outside the process. Change the wording
    /// here and `SmokeTests` has to change with it.
    private var accessibilityLabel: Text {
        switch mode {
        case .off:
            Text("Off")
        case .indefinite:
            Text("On, indefinitely")
        case .countdown:
            // The end time rather than the time remaining: more precise when
            // read aloud, and it holds still for the whole timer.
            Text("On, timer until \(endsAtLabel)")
        }
    }

    private var endsAtLabel: String {
        endsAt?.formatted(date: .omitted, time: .shortened) ?? ""
    }
}
