import XCTest

/// End-to-end smoke test at the UI layer: click a real button in the app and
/// verify that "holding the Mac awake" is reflected in the interface.
///
/// Why the launch flag is needed: Caffeinate is a menu bar app (`LSUIElement`)
/// with no Dock icon and no window. `XCUIApplication.launch()` would fail
/// immediately with "Failed to activate" because there is nothing to bring
/// forward, and the `MenuBarExtra` panel is a system `NSPanel` that XCUITest
/// cannot open reliably. `-CaffeinateUITesting` promotes the app to `.regular`
/// and opens a host window around the very `ControlPanel` a real user sees — not
/// a test-only interface — so the path under test is the real one.
///
/// Why `pmset` is NOT called here: the UI test process is sandboxed and cannot
/// spawn `/usr/bin/pmset`, so every call returns empty, which is not a signal
/// worth trusting. "The assertion is really visible to the OS through pmset" is
/// covered a layer down, in `CaffeinateKitTests/IOKitBackingTests`, which
/// creates a real assertion through `IOKitBacking` and reads
/// `pmset -g assertions`.
///
/// `@MainActor`: the whole XCUITest API is main-actor isolated, so under Swift 6
/// every touch from a plain method is a concurrency warning. Marking the class
/// states the truth instead of silencing it.
@MainActor
final class SmokeTests: XCTestCase {

    /// Must match `LaunchEnvironment.uiTestingArgument` in the app target. The
    /// test target cannot import the app target, so this constant has to be
    /// duplicated.
    private static let uiTestingArgument = "-CaffeinateUITesting"

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [Self.uiTestingArgument]
        app.launch()
        return app
    }

    func testActivatingReflectsHoldingStateInUI() throws {
        let app = launchApp()

        let indefinite = app.buttons["Turn on indefinitely"].firstMatch
        XCTAssertTrue(indefinite.waitForExistence(timeout: 10),
                      "The indefinite button should be present once the app opens")

        // The Stop button carries `.disabled(!isActive)`, so its `isEnabled` is
        // the most direct and reliable signal of the active state.
        let stop = app.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertFalse(stop.isEnabled, "While off, Stop should be disabled")
        XCTAssertTrue(gaugeLabelExists(app, "Off"),
                      "While off, the cup should report being off")

        indefinite.click()

        XCTAssertTrue(waitForEnabled(stop, timeout: 5),
                      "Once on, Stop should be usable (the app is active)")
        // The cup is a combined accessibility element; its label reflects the
        // active state derived from the state machine directly.
        XCTAssertTrue(gaugeLabelExists(app, "On, indefinitely"),
                      "The cup should report being on indefinitely")

        stop.click()

        XCTAssertTrue(waitForDisabled(stop, timeout: 5),
                      "Once stopped, Stop should be disabled again")
        XCTAssertTrue(gaugeLabelExists(app, "Off"),
                      "Once stopped, the cup should report being off")

        app.terminate()
    }

    // Why there is NO smoke test for countdown mode here:
    //
    // While a timer runs, the menu bar label ticks at 1 Hz for its whole
    // duration — by design, because the icon has to drain in real time.
    // XCUITest waits for the application to be "idle" before each interaction,
    // and a tick that never stops means that condition is never met: every
    // query after clicking a duration button times out.
    //
    // That is a limitation of the tool, not a bug in the app, and the answer is
    // not to break the app to suit the tool. All countdown behaviour (setting
    // the end date, the coffee level over time, clamping the duration,
    // cancelling the timer when switching to indefinite) is verified
    // deterministically in `CaffeinateKitTests/CaffeineControllerTests`, with no
    // real clock to wait on.

    // MARK: - Helpers

    /// Must match `CoffeeGauge.accessibilityIdentifier` in the app target,
    /// which the test target cannot import.
    private static let gaugeIdentifier = "caffeine-gauge"

    /// The cup is a combined accessibility element whose label reflects the
    /// active state. Find it by identifier rather than scanning the tree by
    /// label — the tree is always animating, so a broad query has to wait for a
    /// settled state that never arrives.
    private func gauge(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[Self.gaugeIdentifier].firstMatch
    }

    private func gaugeLabelExists(
        _ app: XCUIApplication,
        _ label: String,
        timeout: TimeInterval = 10
    ) -> Bool {
        let e = expectation(
            for: NSPredicate(format: "label == %@", label),
            evaluatedWith: gauge(app)
        )
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let e = expectation(for: NSPredicate(format: "isEnabled == true"),
                            evaluatedWith: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private func waitForDisabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let e = expectation(for: NSPredicate(format: "isEnabled == false"),
                            evaluatedWith: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }
}
