import SwiftUI
import CaffeinateKit

/// "Automatic" — three independent on/off rules.
struct AutomationSettingsView: View {
    @Bindable var controller: CaffeineController

    var body: some View {
        Form {
            Section {
                // `.accessibilityLabel` on EVERY Toggle in this window is
                // mandatory, even where the label is already a plain string: in
                // a `Form` on macOS the label is drawn as its own run of text
                // beside the switch rather than attached to it, so VoiceOver
                // reads them all as "switch, off" with nothing to tell them
                // apart.
                Toggle("An app from the list is running",
                       isOn: $controller.settings.appTriggerEnabled)
                    .accessibilityLabel(Text("An app from the list is running"))

                AppTriggerList(bundleIDs: $controller.settings.triggerAppBundleIDs)
                    .disabled(!controller.settings.appTriggerEnabled)
            } header: {
                Text("Turn on automatically when")
            }

            Section {
                Toggle("Plugged into power",
                       isOn: $controller.settings.chargingTriggerEnabled)
                    .accessibilityLabel(Text("Plugged into power"))
                Toggle("An external display is connected",
                       isOn: $controller.settings.externalDisplayTriggerEnabled)
                    .accessibilityLabel(Text("An external display is connected"))
            } footer: {
                Text("""
                    Stop always wins: it clears even the rules that are \
                    currently true. A rule only comes back when its condition \
                    genuinely happens again — unplug and plug back in, not a \
                    few seconds later.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
