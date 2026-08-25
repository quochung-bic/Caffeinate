import SwiftUI
import AppKit
import CaffeinateKit

/// The panel that appears when the menu bar icon is clicked — and the app's
/// primary interface.
///
/// It holds only what gets used often: how long is left, pick a duration, stop.
/// Deeper configuration lives in the Settings window. That boundary is
/// deliberate: the panel has to be readable at a glance, so every item added
/// here is an item that slows the glance down.
struct ControlPanel: View {
    @Bindable var controller: CaffeineController
    let expiryAlert: TimerExpiryAlert

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            CoffeeGauge(
                endsAt: controller.state.timerEndsAt,
                totalSeconds: controller.timerTotalSeconds,
                isActive: controller.state.isActive,
                size: 104
            )
            .padding(.top, 2)

            DurationBar(
                customMinutes: controller.settings.customDurationMinutes,
                isActive: controller.state.isActive,
                onSelect: { controller.startTimer(minutes: $0) },
                onIndefinite: { controller.startIndefinite() },
                onStop: { controller.stop() }
            )

            StatusCard(
                effectiveFlags: controller.state.effectiveFlags,
                reason: controller.state.activeReason,
                failure: controller.lastFailure
            )

            Divider()

            footer
        }
        .padding(12)
        .frame(width: 288)
        .onAppear {
            // Opening the panel means the user has seen it; the icon no longer
            // needs to flash for attention.
            expiryAlert.cancelFlashing()
        }
    }

    /// Real buttons, not blue text: both actions leave the panel (open a
    /// window, quit the app), so they have to look clickable and carry as large
    /// a hit target as every other button here.
    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                dismiss()
                showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    /// The app runs as an accessory (no Dock icon), so opening the window is
    /// not enough — it has to bring itself to the front, otherwise the Settings
    /// window appears behind whatever the user is working in and the button
    /// looks broken.
    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}

/// Groups "what is being held" and "why it is on" into one backed block,
/// instead of letting two clusters float in whitespace.
private struct StatusCard: View {
    let effectiveFlags: AssertionFlags
    let reason: ActiveReason?
    let failure: AssertionFailure?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlagGrid(effectiveFlags: effectiveFlags)

            if let reason {
                Divider()
                Label {
                    Text(reason.displayText)
                } icon: {
                    Image(systemName: reason.symbolName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let failure {
                Divider()
                Label {
                    Text(failure.message)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.2), value: reason)
    }
}
