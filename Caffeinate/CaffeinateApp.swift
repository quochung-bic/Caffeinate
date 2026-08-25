import SwiftUI
import AppKit
import CaffeinateKit

/// Caffeinate is a menu bar app: no Dock icon, no main window.
///
/// That is an architectural consequence, not a cosmetic detail — the menu bar
/// icon is the ONLY surface that always exists, so anything that has to live
/// for the whole session hangs off it. The Settings window is a secondary view
/// that can be opened and closed at any time without affecting whether the app
/// is holding the Mac awake.
///
/// An earlier version also had a main window, and nearly all of the app's
/// lifecycle complexity was in coordinating it with the panel: an
/// `NSApplicationDelegate` guessing whether to open a window at launch, an
/// `NSPanel` key-window watcher to close the window when the panel appeared,
/// and a request counter so two consecutive open requests would not swallow
/// each other. Dropping the main window dropped all three.
@main
struct CaffeinateApp: App {
    @State private var controller = CaffeineController()
    @State private var expiryAlert = TimerExpiryAlert()
    @State private var lifecycle = AppLifecycle()

    init() {
        // App.init runs on the main thread but is not marked isolated yet, so
        // say so explicitly rather than silencing the warning.
        MainActor.assumeIsolated { LaunchEnvironment.applyActivationPolicy() }
    }

    var body: some Scene {
        menuBar
        settings
    }

    private var menuBar: some Scene {
        MenuBarExtra {
            ControlPanel(controller: controller, expiryAlert: expiryAlert)
        } label: {
            MenuBarLabel(controller: controller, expiryAlert: expiryAlert)
                .task {
                    lifecycle.install(controller: controller, expiryAlert: expiryAlert)
                }
        }
        .menuBarExtraStyle(.window)
    }

    /// The `SwiftUI.` prefix is required, not decorative: `CaffeinateKit` also
    /// exports a type called `Settings` (the user's configuration), so a bare
    /// `Settings { … }` here binds to the wrong type and the compiler reports
    /// the error somewhere else entirely.
    private var settings: some Scene {
        SwiftUI.Settings {
            SettingsView(controller: controller)
        }
    }
}

/// Everything that depends only on how the process was launched.
enum LaunchEnvironment {
    static let uiTestingArgument = "-CaffeinateUITesting"
    static let uiTestWindowID = "ui-test-harness"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    /// Which surface goes into the test window. The Settings window is a
    /// `Settings` scene that XCUITest cannot open from outside, so it needs its
    /// own way in — without one, that whole window would have no tests at all,
    /// and that is exactly where an accessibility bug slipped through: all four
    /// flag switches had no label.
    enum TestSurface: String {
        case panel
        case settings
    }

    /// Read straight from the process arguments rather than through
    /// `UserDefaults`.
    ///
    /// The `NSUserDefaults` argument domain parses `-key value` pairs, and
    /// `-CaffeinateUITesting` is a bare flag with no value — so it swallows the
    /// token after it. Learned the hard way: the surface flag placed right
    /// after it could never be read, and the app quietly opened the panel
    /// instead of the Settings window.
    static var testSurface: TestSurface {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: surfaceArgument),
              index + 1 < arguments.count,
              let surface = TestSurface(rawValue: arguments[index + 1])
        else { return .panel }
        return surface
    }

    static let surfaceArgument = "-CaffeinateUITestSurface"

    /// `LSUIElement` in Info.plist already puts the app in accessory mode. Only
    /// a UI test run promotes it to `.regular`, because the test runner needs a
    /// real window to activate — an accessory app with no window makes
    /// `XCUIApplication.launch()` fail with "Failed to activate".
    @MainActor
    static func applyActivationPolicy() {
        guard isUITesting else { return }
        NSApplication.shared.setActivationPolicy(.regular)
    }
}

/// Everything that must be wired up exactly ONCE per session.
///
/// `install` is deliberately idempotent. `.task` attaches it to the
/// `MenuBarExtra` label, and SwiftUI promises nothing about how often that view
/// is rebuilt — an earlier version lacked this latch, so every rebuild added
/// another `willTerminate` observer, meaning `shutdown()` ran several times at
/// exit.
@MainActor
@Observable
final class AppLifecycle {
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var terminationObserver: NotificationObserverToken?
    @ObservationIgnored private var uiTestHarness: UITestHarnessWindow?

    func install(controller: CaffeineController, expiryAlert: TimerExpiryAlert) {
        guard !installed else { return }
        installed = true

        if LaunchEnvironment.isUITesting {
            switch LaunchEnvironment.testSurface {
            case .panel:
                uiTestHarness = UITestHarnessWindow(
                    content: ControlPanel(controller: controller, expiryAlert: expiryAlert)
                )
            case .settings:
                uiTestHarness = UITestHarnessWindow(
                    content: SettingsView(controller: controller)
                )
            }
        }

        // IOKit cleans up assertions when the process dies, but doing it
        // explicitly makes the behaviour something you can reason about — and
        // it also stops the triggers and the timer.
        terminationObserver = NotificationObserverToken(
            forName: NSApplication.willTerminateNotification
        ) {
            controller.shutdown()
        }

        controller.onTimerStarted = { expiryAlert.prepareForTimer() }
        controller.onTimerExpired = {
            // Still active after expiry means an automation rule is holding the
            // Mac awake — say that, rather than claiming it is about to sleep.
            expiryAlert.fire(stillActive: controller.state.isActive)
        }
    }
}

/// RAII-style observer registration: the token lives exactly as long as this
/// object, and is removed when the object dies.
///
/// No deinit in `AppLifecycle` has to remember to clean up — forgetting is the
/// classic `addObserver(forName:)` bug, and the surest way not to forget is to
/// make remembering unnecessary.
private final class NotificationObserverToken: @unchecked Sendable {
    // @unchecked: the token is only ever handed back to removeObserver, which
    // is thread-safe. No other state crosses an actor boundary.
    private let token: any NSObjectProtocol

    init(forName name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
