import AppKit
import SwiftUI

/// A window that exists only when the process is launched with
/// `LaunchEnvironment.uiTestingArgument`.
///
/// Why it is needed: Caffeinate is a menu bar app, and a `MenuBarExtra` panel
/// is a system-managed `NSPanel` — `XCUIApplication` cannot open it in any way
/// stable enough to build a test suite on. With no window at all, `launch()`
/// fails outright with "Failed to activate".
///
/// The important part: this window does NOT build a separate interface for
/// tests. It hosts the very `ControlPanel` a real user sees, so the tests
/// exercise the real path (button → CaffeineController → state) rather than
/// verifying a copy that only exists under test.
@MainActor
final class UITestHarnessWindow {
    private let window: NSWindow

    init(content: some View) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Caffeinate"
        let hosting = NSHostingView(rootView: content)
        window.contentView = hosting

        // Size to the content: the panel is 288pt wide while the Settings
        // window is 500pt, and a window narrower than its content would clip
        // exactly the controls under test.
        //
        // Clamp the floor: immediately after assignment `fittingSize` can still
        // be zero, because SwiftUI has not run a layout pass yet. Learned the
        // hard way — the window came out 0×0, no control could be reached, and
        // the whole suite went red reporting "the window never appeared" when
        // it had appeared, just empty.
        let fitting = hosting.fittingSize
        window.setContentSize(NSSize(
            width: max(fitting.width, 520),
            height: max(fitting.height, 560)
        ))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
