import SwiftUI
import CaffeinateKit

/// "Startup" — launch with macOS, and whether to turn on immediately.
struct StartupSettingsView: View {
    @Bindable var controller: CaffeineController
    @State private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                // See the comment in AutomationSettingsView: in a `Form` on
                // macOS a Toggle's label does not become the switch's
                // accessibility label, so it has to be set by hand everywhere.
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .accessibilityLabel(Text("Launch at login"))

                Toggle("Turn on as soon as the app starts",
                       isOn: $controller.settings.activateOnLaunch)
                    .disabled(!launchAtLogin.isEnabled)
                    .accessibilityLabel(Text("Turn on as soon as the app starts"))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if !launchAtLogin.isEnabled {
                        // This constraint has to be stated: an option greyed out
                        // without explanation just looks broken.
                        Text("""
                            Turn on "Launch at login" first — if the app doesn’t \
                            start when you log in, that option has no effect.
                            """)
                    }

                    if let error = launchAtLogin.lastError {
                        Label {
                            Text(error)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
