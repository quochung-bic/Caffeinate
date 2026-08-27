# CLAUDE.md

Notes for Claude Code working in this repository.

## Language

Source, comments and documentation are **written in English**. Keep it that way.

**Commit messages are English too** — natural imperative mood, first line under
60 characters, no `feat:`/`fix:` prefixes. The body explains *why*, not *what*.

## Common commands

```bash
# command-line build — Release, verifies the universal binary, outputs ./build/Caffeinate.app
./Scripts/build.sh            # --debug is faster, --test runs tests first, --help for all options

# build and install into /Applications (quits the running copy, replaces the bundle, reopens)
./Scripts/install.sh          # --test, --destination DIR, --no-build, --help

# core unit tests — 69 tests, under 0.2 s, no GUI needed. Run this first.
./Scripts/build.sh --unit-only

# the UI tests on their own — slow, takes over the screen
./Scripts/build.sh --ui-only

# both layers
./Scripts/build.sh --test-only

# one suite or a single test (matched against the English display names)
./Scripts/build.sh -u -f 'CaffeineController'
./Scripts/build.sh -U -f 'SettingsAccessibilityTests'

# the same thing without the wrapper, when you need the raw tool
swift test --package-path CaffeinateKit --filter 'timers'

# build the app
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' build

# build plus every UI test (slow, ~45 s, takes over the screen)
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' test

# run one UI test class or a single UI test
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' \
           -only-testing:CaffeinateUITests/SettingsAccessibilityTests test

# redraw the whole app icon set
swift Scripts/GenerateAppIcon.swift

# verify a Release build really is a universal binary
lipo -info <path>/Caffeinate.app/Contents/MacOS/Caffeinate
```

The finish line is always green: **69 unit tests + 3 UI tests, and no warnings**.

Local `./Scripts/build.sh --test-only` is authoritative. The UI job in CI is
advisory — a hosted runner has no physical display and nobody to dismiss a
system prompt.

Warnings are promoted to errors **in CI only**, where the toolchain is pinned.
`Configs/*.xcconfig` deliberately does not set `-Werror`: a newer Xcode must not
break someone's build over code they never touched.

The two repositories share one `build.sh` body. Anything outside the marked
config block at the top must stay byte-identical with `mymac`:

```bash
diff <(sed -n '/^# ---- END CONFIG/,$p' Scripts/build.sh) \
     <(sed -n '/^# ---- END CONFIG/,$p' ../../quochung/mymac/Scripts/build.sh)
```

The three UI tests fall into two groups, and each says something different when
it goes red:

| Class | Tests | What it catches |
|---|---|---|
| `SmokeTests` | 1 | button → controller → state, through the real `ControlPanel` |
| `SettingsAccessibilityTests` | 2 | every control in the Settings window has an accessibility label, and the four flags are individually identifiable |

Both start the app with `-CaffeinateUITesting`, which promotes it from
`LSUIElement` to `.regular` and opens `UITestHarnessWindow`. Adding
`-CaffeinateUITestSurface settings` makes that host window build `SettingsView`
directly — the only way to reach the `Settings` scene from XCUITest.

## Layout

| Path | Contents |
|---|---|
| `CaffeinateKit/` | SwiftPM package — all the logic. No GUI, no display strings. |
| `Caffeinate/` | App target (SwiftUI). A filesystem-synchronized group: adding a file is picked up by Xcode automatically, with **no need to edit `project.pbxproj`**. |
| `Configs/` | Build settings (`.xcconfig`) and entitlements. Change build settings here, never in the pbxproj. |
| `Scripts/` | `build.sh`, `install.sh` and `GenerateAppIcon.swift` — the app icon is source code, not a hand-copied binary. |
| `CaffeinateUITests/` | UI tests — smoke and accessibility labels. |
| `docs/ARCHITECTURE.md` | Detailed architecture, the invariants, and the places that are easy to get wrong. |

Data flows one way, and everything hangs off `CaffeineController`:

```
MenuBarLabel / ControlPanel / SettingsView   ← read @Observable
TriggerEngine (app running · plugged in · external display)
              ↓ send(event)
        CaffeineController  →  reduce()  →  apply()  →  AssertionManager  →  IOKit
```

`project.pbxproj` is hand-written and deliberately minimal. Avoid opening the
project in Xcode and saving — Xcode will rewrite it and bloat the file.

## Invariants — do not break these

1. **One path for state changes.** `CaffeineController` is the *only* caller of
   `AssertionManager.set(flags:)`. Every change goes through
   `send(event) → reduce() → apply()`.

2. **`reduce` is pure.** No I/O, no reading the system clock. Every instant
   arrives through an event.

3. **`CaffeinateKit` holds no display strings.** It returns types;
   `Caffeinate/DisplayText.swift` is the single place that turns them into
   sentences. Putting wording into the package is how the reason-ordering bug
   happened once already (see ARCHITECTURE.md).

4. **`AssertionManager.defaultReason` must be pure ASCII.** That is the string
   `pmset -g assertions` prints; non-ASCII characters make the assertion
   anonymous, exactly when someone needs pmset to confirm the app is working.

5. **Import layering.** The package does not import SwiftUI. `Core/` and
   `State/` do not import AppKit. The app target does not import IOKit.

6. **Stop is decisive.** `stopAll` clears even a trigger reason that is still
   true, but does *not* reset the trigger's internal baseline. Read the long
   comments in `CaffeineController.toggle()` and `PowerSourceTrigger.refresh()`
   before touching this — someone has already "fixed" it into a bug.

7. **Nothing fails silently.** A failed create forces the state off and reports
   it. A failed release keeps the state and reports it. No error is swallowed.

## Things that are easy to get wrong

- **`Settings` means two things.** `CaffeinateKit.Settings` (user configuration)
  and `SwiftUI.Settings` (the scene). In `CaffeinateApp.swift` it has to be
  written `SwiftUI.Settings { … }`, or the compiler reports an error somewhere
  completely unrelated, as "failed to produce diagnostic".

- **XCUITest cannot cope with a background tick.** During a countdown the menu
  bar label runs at 1 Hz and XCUITest never sees the app go idle → every query
  times out. Do not add a UI test for countdown mode; cover it in
  `CaffeineControllerTimerTests`.

- **The app is `LSUIElement`.** No Dock icon, no main window, and it does not own
  the system menu bar — so ⌘W has to be reattached with a hidden button
  (`CloseWindowShortcut`). UI tests work because `-CaffeinateUITesting` promotes
  the app to `.regular` and opens `UITestHarnessWindow`.

- **The accessibility label must not change every second.** `CoffeeGauge`'s label
  states the end time ("On, timer until 15:47") rather than the time remaining,
  so it holds still. Turning it back into a countdown makes VoiceOver repeat
  itself and breaks the UI test.

- **`TimelineView` does not tick inside a `MenuBarExtra` label.** Measured: two
  redraws in eight seconds. The label has to read `controller.now` (an
  `@Observable` property that genuinely changes) for the icon to drain. Do not
  "tidy this up" by putting `TimelineView` back.

- **`Toggle`/`Picker`/`Stepper` inside a `Form` on macOS have NO accessibility
  label.** The label is drawn as a separate run of text beside the control
  rather than attached to it, so VoiceOver reads everything as "switch, off".
  Every control in the Settings window needs a hand-written
  `.accessibilityLabel(…)`, even where the label is already a plain string.
  `SettingsAccessibilityTests` catches this.

- **`MenuBarIconState` quantizes progress to 32 steps** so it works as a cache
  key. Removing the quantization disables the cache.

- **`.gitignore` works as a whitelist.** The `/*` line blocks the whole root and
  each entry below re-opens one path. Consequence: add a new top-level directory
  without declaring `!/name/` and `git status` shows NOTHING — the new files sit
  silently outside the repo. The upside is that no tool droppings ever wander
  into a commit. Inside the re-opened directories the whitelist stops applying,
  so `.build/`, `DerivedData/` and `xcuserdata/` still have to be named
  explicitly.

## Code conventions

- Comments explain **why**, not **what**. Wherever there is a trade-off or a trap
  that has already been hit, write it down, at length if needed.
- Test names describe behaviour, not the function being called.
- No third-party dependencies. The project deliberately uses system frameworks
  only.
