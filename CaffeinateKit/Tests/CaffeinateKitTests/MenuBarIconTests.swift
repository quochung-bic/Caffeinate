import AppKit
import Testing
@testable import CaffeinateKit

@Suite("MenuBarIcon")
@MainActor
struct MenuBarIconTests {

    @Test("the icon is always a template image so it adapts to light and dark")
    func isTemplateImage() {
        let image = MenuBarIcon.image(for: MenuBarIconState(
            isActive: true, progress: 0.5, hasError: false
        ))
        #expect(image.isTemplate)
    }

    @Test("the icon is the right size for the menu bar")
    func hasMenuBarSize() {
        let image = MenuBarIcon.image(for: MenuBarIconState(
            isActive: false, progress: nil, hasError: false
        ))
        #expect(image.size == NSSize(width: 18, height: 18))
    }

    @Test("the accessibility description comes from the caller, not from the package")
    func accessibilityDescriptionComesFromCaller() {
        // The package must contain no display strings: wording belongs to the
        // app layer, which passes it down.
        let image = MenuBarIcon.image(
            for: .init(isActive: true, progress: nil, hasError: false),
            accessibilityDescription: "any caller string"
        )
        #expect(image.accessibilityDescription == "any caller string")
    }

    @Test("the error state still carries the caller's accessibility description")
    func errorStateKeepsCallerDescription() {
        let image = MenuBarIcon.image(
            for: .init(isActive: true, progress: 0.5, hasError: true),
            accessibilityDescription: "error text"
        )
        #expect(image.accessibilityDescription == "error text")
        #expect(image.isTemplate)
    }

    @Test("different states render to different images")
    func distinctStatesRenderDifferently() throws {
        let off = try #require(MenuBarIcon.image(for:
            .init(isActive: false, progress: nil, hasError: false)).tiffRepresentation)
        let on = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: nil, hasError: false)).tiffRepresentation)
        let quarter = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 0.25, hasError: false)).tiffRepresentation)
        let threeQuarter = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 0.75, hasError: false)).tiffRepresentation)

        #expect(off != on)
        #expect(quarter != threeQuarter)
        #expect(on != quarter)
    }

    @Test("progress outside 0...1 is clamped rather than drawn wrong")
    func clampsOutOfRangeProgress() throws {
        #expect(MenuBarIconState(isActive: true, progress: 1.8, hasError: false).progress == 1.0)
        #expect(MenuBarIconState(isActive: true, progress: -0.5, hasError: false).progress == 0.0)

        let over = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 1.8, hasError: false)).tiffRepresentation)
        let full = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 1.0, hasError: false)).tiffRepresentation)
        #expect(over == full)
    }

    // MARK: - Quantization and cache

    @Test("progress is rounded to a step, so two nearby values are ONE state")
    func quantizesProgressIntoSteps() {
        // 1/32 = 0.03125. Two values less than half a step apart have to
        // collapse together, otherwise the cache would miss every second and
        // lose all its value.
        let a = MenuBarIconState(isActive: true, progress: 0.500, hasError: false)
        let b = MenuBarIconState(isActive: true, progress: 0.505, hasError: false)
        #expect(a == b)
        #expect(a.progress == 0.5)

        // A full step apart must still be distinguishable.
        let c = MenuBarIconState(isActive: true, progress: 0.5 + 1 / 32.0, hasError: false)
        #expect(a != c)
    }

    @Test("the same state returns one identical image object, never rebuilt")
    func cacheReturnsIdenticalInstance() {
        let state = MenuBarIconState(isActive: true, progress: 0.25, hasError: false)
        let first = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "a")
        let second = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "a")
        #expect(first === second)
    }

    @Test("the cache reuses the image but still refreshes the accessibility description")
    func cacheStillRefreshesAccessibilityDescription() {
        // The image is identical at 12 minutes left and at 11, but what
        // VoiceOver reads is not — so the description must stay out of the key.
        let state = MenuBarIconState(isActive: true, progress: 0.75, hasError: false)
        _ = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "12 minutes left")
        let again = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "11 minutes left")
        #expect(again.accessibilityDescription == "11 minutes left")
    }

    @Test("the blank image keeps its size so neighbouring icons do not jump while flashing")
    func blankImageKeepsSize() {
        let blank = MenuBarIcon.blankImage()
        #expect(blank.size == MenuBarIcon.size)
        #expect(blank.isTemplate)
    }
}
