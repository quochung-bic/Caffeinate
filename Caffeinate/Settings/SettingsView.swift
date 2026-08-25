import SwiftUI
import CaffeinateKit

/// The Settings window — a secondary view whose being open or closed has no
/// bearing on whether the app is holding the Mac awake.
///
/// Four tabs rather than one long form: each tab answers exactly one question
/// ("what does it hold", "when does it turn itself on", "when does it run",
/// "what is this app"), so finding a setting never means scrolling past
/// unrelated ones.
struct SettingsView: View {
    @Bindable var controller: CaffeineController

    /// Wide enough that the tab bar always lays out flat. Any narrower and
    /// macOS 26 folds every tab into a "»" overflow button, turning four tabs
    /// into a two-level menu.
    private static let width: CGFloat = 500

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }

            AutomationSettingsView(controller: controller)
                .tabItem { Label("Automatic", systemImage: "bolt") }

            StartupSettingsView(controller: controller)
                .tabItem { Label("Startup", systemImage: "power") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Self.width)
        .background(CloseWindowShortcut())
    }
}

/// The app runs as an accessory, so it does not own the menu bar — and with no
/// menu bar there is no File > Close, which means ⌘W is dead. This hidden
/// button puts that shortcut back, because closing a macOS window with ⌘W is a
/// basic expectation.
private struct CloseWindowShortcut: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Close window") { dismiss() }
            .keyboardShortcut("w", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
