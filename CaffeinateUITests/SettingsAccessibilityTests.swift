import XCTest

/// The Settings window is a `Settings` scene that XCUITest cannot open from
/// outside, so it used to have no tests at all — and that is exactly where a
/// bug slipped through: the four flag switches and the duration stepper all had
/// EMPTY accessibility labels. In a `Form` on macOS, the label of such a control
/// is drawn as its own run of text beside it rather than attached to it, so
/// VoiceOver announced four identical switches: "switch, on".
///
/// These tests drive that window through `-CaffeinateUITestSurface settings`.
///
/// They query by CONTROL TYPE only (`switches`, `popUpButtons`, `steppers`),
/// never `staticTexts`: querying the text of this window times out reliably.
/// Nothing is lost by that — what matters here is whether a control has a
/// label, and the label lives on the control.
@MainActor
final class SettingsAccessibilityTests: XCTestCase {

    private func launchSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CaffeinateUITesting",
            "-CaffeinateUITestSurface", "settings",
        ]
        app.launch()

        // Wait for the window before querying anything inside it: the first
        // accessibility snapshot can land before any window exists, and it does
        // not retry on its own.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "The Settings window should appear")
        return app
    }

    /// A control with no label is a control a VoiceOver user cannot use. Check
    /// by class rather than listing them one by one: add a new `Toggle` without
    /// a label and this test goes red without anyone having to remember.
    func testEveryControlHasAnAccessibilityLabel() {
        let app = launchSettings()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10),
                      "The General tab should have the flag switches")

        // Visit each tab: every tab has its own controls, and a tab that is not
        // open has no content in the accessibility tree to check.
        for tab in ["General", "Automatic", "Startup"] {
            let button = app.radioButtons[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing the \"\(tab)\" tab")
            button.click()

            assertAllLabelled(app.switches, kind: "switch on the \(tab) tab")
            assertAllLabelled(app.checkBoxes, kind: "checkbox on the \(tab) tab")
            assertAllLabelled(app.popUpButtons, kind: "pop-up button on the \(tab) tab")
            assertAllLabelled(app.steppers, kind: "stepper on the \(tab) tab")
        }

        app.terminate()
    }

    /// The four keep-awake flags have to be tellable APART by their labels — not
    /// merely "has a label", but the right label for each one.
    func testHoldFlagsAreIndividuallyIdentifiable() {
        let app = launchSettings()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10))

        for name in ["System", "Display", "Disk", "Idle"] {
            XCTAssertTrue(toggleExists(app, labelled: name),
                          "No switch found labelled \"\(name)\"")
        }
        XCTAssertTrue(app.steppers["Custom duration"].firstMatch.exists,
                      "The duration stepper should carry its own label")

        app.terminate()
    }

    /// macOS renders a `Toggle` in a Form as either a `Switch` or a `CheckBox`
    /// depending on the version and the Form style; accept both rather than
    /// pinning to one.
    private func toggleExists(_ app: XCUIApplication, labelled label: String) -> Bool {
        app.switches[label].firstMatch.exists || app.checkBoxes[label].firstMatch.exists
    }

    private func assertAllLabelled(_ query: XCUIElementQuery, kind: String) {
        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            XCTAssertFalse(
                element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(kind) at index \(index) has no accessibility label (value=\(element.value ?? "nil"))"
            )
        }
    }
}
