import SwiftUI
import CaffeinateKit

/// "General" — the four keep-awake flags and the custom duration.
struct GeneralSettingsView: View {
    @Bindable var controller: CaffeineController

    var body: some View {
        Form {
            Section {
                ForEach(AssertionFlags.all, id: \.rawValue) { flag in
                    Toggle(isOn: binding(for: flag)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flag.displayName)
                            Text(flag.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // A label built from a `VStack` does not become the switch's
                    // accessibility label — it is only artwork. Without setting
                    // it by hand, VoiceOver reads all four switches identically:
                    // "switch, on".
                    .accessibilityLabel(Text(flag.displayName))
                    .accessibilityHint(Text(flag.explanation))
                }
            } header: {
                Text("What to hold while Caffeinate is on")
            } footer: {
                Text("System only, by default. That’s usually the only one you need.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $controller.settings.customDurationMinutes,
                        in: Settings.durationRange,
                        step: 5) {
                    LabeledContent {
                        Text(Plural.minutes(controller.settings.customDurationMinutes))
                            .monospacedDigit()
                    } label: {
                        Text("Custom duration")
                    }
                }
                // A `Stepper` label inside a Form on macOS is drawn as its own
                // run of text beside the control rather than attached to it, so
                // VoiceOver announces the control with no name. Set it by hand.
                .accessibilityLabel(Text("Custom duration"))
            } header: {
                Text("Timer")
            } footer: {
                Text("This shows up as the fourth button in the panel, next to 15m / 30m / 1h.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for flag: AssertionFlags) -> Binding<Bool> {
        Binding(
            get: { controller.settings.flags.contains(flag) },
            set: { isOn in
                if isOn {
                    controller.settings.flags.insert(flag)
                } else {
                    controller.settings.flags.remove(flag)
                }
            }
        )
    }
}
