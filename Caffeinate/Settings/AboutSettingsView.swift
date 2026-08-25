import SwiftUI
import AppKit

/// A static tab: reads no state and changes none. Explains what the app does
/// and the parts that are easy to misread.
struct AboutSettingsView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                section("How to use it") {
                    bullet("Click the coffee cup in the menu bar to open the control panel.")
                    bullet("Pick a duration — when it runs out, your Mac goes back to normal on its own.")
                    bullet("Choose \"Indefinite\" when you don’t know how long you’ll need it.")
                    bullet("Click \"Stop\" to end it right away, even while an automatic rule is running.")
                }

                section("The coffee level is the progress bar") {
                    paragraph("""
                        The cup is full the moment you turn it on and drains as \
                        the countdown runs. The same shape, shrunk down, is the \
                        menu bar icon — so one glance tells you how much is left \
                        without opening anything.
                        """)
                }

                section("When the timer runs out") {
                    paragraph("""
                        Caffeinate tells you three independent ways — a \
                        notification banner, one chime, and a blinking menu bar \
                        icon — because any single one of them can go silent: \
                        banners get blocked by Do Not Disturb, sound is useless \
                        when your headphones are in another room, and the icon \
                        only helps if you happen to be looking at the menu bar.
                        """)
                }

                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Caffeinate")
                    .font(.title2.bold())
                Text("Keeps your Mac awake, for exactly as long as you want.")
                    .foregroundStyle(.secondary)
                Text(Self.versionText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    /// Read from the bundle rather than hard-coded: a version number copied by
    /// hand into source is a version number that eventually goes stale.
    private static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    private func section(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
    }
}
