# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioned according to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A standard macOS Settings window (⌘,) split into four tabs: General,
  Automatic, Startup, About. Closes with ⌘W.
- `Scripts/GenerateAppIcon.swift` — generates the whole app icon set from code.
- `Scripts/build.sh` — builds from the command line, puts the product somewhere
  predictable (`build/Caffeinate.app`) and **rejects a non-universal Release
  build**, rather than leaving that as an item someone has to remember.
- `Scripts/install.sh` — build and install into `/Applications` in one command,
  for someone who has just cloned the repo. It handles three things a bare
  `cp -R` misses: asking the running copy to quit so it can write its settings
  and release its assertion, replacing the old bundle outright instead of
  merging into it, and opening the app — with a pure menu bar app, copying it
  leaves nothing on screen to confirm it worked.
- `.gitignore` moved to a whitelist: block everything at the root and re-open
  exactly the directories that belong to the project, so tool droppings cannot
  reach a commit merely because nobody has hit them yet.
- Build settings extracted into `Configs/*.xcconfig`, with a comment on every
  choice.
- 23 new unit tests covering the settings schema, trigger precedence, timers and
  icon state (46 → 69).
- 2 UI tests for the Settings window, which previously had none: every control
  must carry an accessibility label, and the four flags must be individually
  identifiable. `UITestHarnessWindow` gained a `-CaffeinateUITestSurface
  settings` flag so the window can be opened from a test at all.

### Changed

- **Caffeinate is now a pure menu bar app** (`LSUIElement`): no Dock icon and no
  main window. Every control lives in the menu bar panel; configuration lives in
  the Settings window.
- The interface is English only. An earlier iteration shipped a Vietnamese and
  English interface with an in-app language switcher, built on a String Catalog;
  it was removed along with the catalog, the `\.locale` plumbing and the six UI
  tests that existed to guard it. The layering it motivated survives:
  `DisplayText.swift` is still the only place core types become sentences.
- Redrawn app icon: warm brown gradient background, a thick-stroked ceramic cup,
  on the correct macOS icon grid (an 824 body inside a 1024 canvas) with
  superellipse corners.
- `CaffeinateKit` contains no display strings at all. Errors became a typed
  `AssertionFailure` that distinguishes "could not hold" from "could not
  release".
- Precedence among simultaneously-true automation rules is now an explicit
  `Comparable` rather than a sort over display strings — so wording can no
  longer silently change which reason is shown.
- The bundle identifier changed to `io.github.quochung-bic.Caffeinate`. A new
  build cannot read settings written by the old one (`com.caffeinate.app`).
- Release builds no longer inject the `get-task-allow` entitlement.

### Fixed

- **No control in the Settings window had an accessibility label.** Nine
  switches, a pop-up button and a stepper all read out under VoiceOver as
  "switch, off", with nothing to tell them apart. Cause: in a `Form` on macOS
  the label is drawn beside the control rather than attached to it, even when
  declared as a plain string.
- The lifecycle hook (`willTerminate`) was registered non-idempotently: every
  time SwiftUI rebuilt the menu bar label it added another observer, so
  `shutdown()` ran repeatedly at exit. The observation is now RAII and removes
  itself with its owner.
- Settings were wiped whenever a key was missing: the synthesized `Codable`
  threw and the store fell back to defaults. Decoding is now lenient per key,
  with value normalization (clamping the duration, dropping duplicate and empty
  bundle IDs).
- The coffee cup's accessibility element was rebuilt 24 times a second, costing
  VoiceOver its anchor. The label now holds still for the whole timer, stating
  the end time rather than the time remaining.

### Performance

- The coffee cup and the countdown number now exist only while the panel is
  open, instead of running continuously inside an always-open main window. At
  rest, the app draws nothing.
- Icon state became a pure computation (`iconState(at: Date)`), testable without
  waiting on a real clock. The controller still emits the 1 Hz tick, but it
  lives only while `timerEndsAt != nil` — and it has to work that way, because
  `TimelineView` was measured not to tick inside a `MenuBarExtra` label.
- `MenuBarIconState` quantizes progress to 32 steps (below one pixel at 18pt)
  and `MenuBarIcon` caches: an eight-hour timer builds 32 images instead of
  28,800.
- The coffee cup dropped from 24 to 20 fps and was separated from the 1 Hz
  countdown, so each component draws only at the rate it needs.
