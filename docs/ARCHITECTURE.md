# Architecture

This document explains *why* Caffeinate is built the way it is. The *what* is in
the [README](../README.md); the how-to-work-here notes are in
[CLAUDE.md](../CLAUDE.md).

## The whole picture

```
                       ┌─────────────────────────────┐
   menu bar ──────────▶│      MenuBarLabel           │
                       │ (1 Hz only while counting)  │
                       └──────────────┬──────────────┘
                                      │ reads
   panel  ────────────▶ ControlPanel ─┤
   ⌘,     ────────────▶ SettingsView ─┤
                                      ▼
                       ┌─────────────────────────────┐
                       │     CaffeineController      │  @MainActor @Observable
                       │  send(event) → reduce → apply
                       └──────┬───────────────┬──────┘
                              │               │
                   ┌──────────▼──────┐  ┌─────▼────────────┐
                   │ AssertionManager│  │  TriggerEngine   │
                   └────────┬────────┘  └─────┬────────────┘
                            │                 │
                   ┌────────▼────────┐  ┌─────▼──────────────────────────┐
                   │  IOKitBacking   │  │ AppRunning / PowerSource /     │
                   │   (IOKit pwr)   │  │ ExternalDisplay                │
                   └─────────────────┘  └────────────────────────────────┘
```

## Why the core is a separate package

`CaffeinateKit` is not decomposition for its own sake. It creates a boundary the
compiler can enforce: the package cannot import SwiftUI, so there is no way for
state logic to quietly acquire a dependency on some `@State`. The practical
result is that `swift test` runs 69 tests in under a tenth of a second without
building the app, without a GUI, and without touching the real system.

That boundary is only worth anything if it is kept. Three rules:

- The package does not import SwiftUI.
- `Core/` and `State/` do not import AppKit.
- The app target does not import IOKit.

## Why there is one path for state changes

`CaffeineController` is the only caller of `AssertionManager.set(flags:)`. Every
change goes through `send(event) → reduce() → apply()`.

This costs more than calling directly, and it earns that cost for one concrete
reason: an IOKit assertion is a resource that lives *outside* the process. With
two write paths, the app's state and the system's real state eventually
disagree, and nothing tells you which is right. With one path,
`state.effectiveFlags` *is* the definition of what the system is holding.

`reduce` is pure — no I/O, no reading `Date()`. Every instant arrives through an
event (`.startedTimer(until:)`). That makes every state transition testable
without waiting on a real clock.

## Why the core holds no words

`AssertionFlags` originally had a `displayName` returning `"System"`. It was
convenient, and it was wrong in two ways:

1. It put presentation inside the core, so the package could not be tested or
   reasoned about without dragging wording along.
2. It leaked into logic. `CaffeineState.activeReason` picked which reason to
   display by **sorting the display strings** — so changing the interface
   language changed which reason the user saw. That is not a bug anyone predicts
   in advance; it is one you discover.

Today the package returns data (`AssertionFlags.identifier`, `TriggerReason`,
`AssertionFailure`) and `Caffeinate/DisplayText.swift` is the single place that
turns those into sentences. Trigger precedence is an explicit `Comparable`,
independent of any wording.

The one exception is `AssertionManager.defaultReason`. That is not interface
text but a string the operating system reads back — it shows up in
`pmset -g assertions`. It must be pure ASCII (accented characters make the
assertion anonymous) and must never be reworded casually.

## Why the app is English-only

Earlier versions shipped a Vietnamese and English interface with an in-app
language switcher, built on a String Catalog and `EnvironmentValues.locale`.
That was removed deliberately: the app is maintained in English, and a second
language meant a catalog to hand-maintain, a `\.locale` discipline every new
view had to follow, and six UI tests whose only job was guarding the
translation machinery.

What survives the removal is the *layering*, not the localization:
`DisplayText.swift` still exists, and the core still returns types rather than
strings. That is worth keeping on its own merits — it is what stops wording from
leaking back into `reduce`, which is exactly how the sorting bug above happened.

Two consequences worth knowing:

- Plural forms are now spelled out in `Plural.minutes(_:)` rather than handled by
  the catalog. It is one function, and it keeps "1 minute" from rendering as
  "1 minutes".
- The UI tests no longer pin `-AppleLanguages`, because the interface no longer
  varies with it. That also removes a class of flakiness: the suite used to go
  red on any machine where the app's language had ever been chosen, since the
  preference persisted in UserDefaults between runs.

## Accessibility labels in the Settings window must be set by hand

In a `Form` on macOS, the label of a `Toggle`, `Picker` or `Stepper` is drawn as
its OWN run of text beside the control rather than attached to it. The
consequence: VoiceOver reads out nine identical switches — "switch, off" — with
no way to tell "Display" from "Plugged into power".

This holds even when the label is declared as a plain string
(`Toggle("Plugged into power", isOn:)`), so it is not a side effect of using a
`VStack` as the label. Every control in the Settings window needs a hand-written
`.accessibilityLabel(…)`.

The bug survived as long as it did because the Settings window is a `Settings`
scene that XCUITest cannot open from outside — meaning that part of the app had
no tests at all. The real fix was not to remember harder but to make it
testable: `UITestHarnessWindow` gained a `-CaffeinateUITestSurface settings`
flag so it can host `SettingsView` itself, and `SettingsAccessibilityTests`
walks every tab checking that no control has an empty label. That test
immediately found the same fault on the other two tabs.

## Why there is no main window

The first version had a three-tab main window alongside the menu bar panel.
Nearly all of the app's lifecycle complexity was in coordinating the two:

- an `NSApplicationDelegate` guessing whether to open a window at launch — and
  the right answer differed depending on whether the app was opened by hand, by
  a login item, or by clicking the menu bar icon;
- an `NSWindow.didBecomeKeyNotification` watcher filtering for `NSPanel` so the
  main window closed when the panel appeared;
- a counter of window-open requests, because with a `Bool` flag two consecutive
  requests swallowed the second.

`LSUIElement = YES` deleted all three. The menu bar icon is the only surface
that always exists; the Settings window is a secondary view whose being open or
closed has no bearing on whether the app is holding the Mac awake.

The price: an accessory app does not own the system menu bar, so ⌘W does not
come for free. It is reattached with a hidden button (`CloseWindowShortcut`) —
a small debt, stated plainly, in exchange for deleting the three mechanisms
above.

## Why each thing has its own tick

This app exists to manage power, so burning CPU on animation would contradict
itself. Three clocks, each running only when needed:

| Component | Rate | Runs when | Driven by |
|---|---|---|---|
| Coffee cup (steam + level) | 20 fps | active **and** the panel is open | `TimelineView` |
| Countdown number | 1 Hz | a timer exists **and** the panel is open | `TimelineView` |
| Menu bar label | 1 Hz | **only while a timer exists** | `CaffeineController.now` |
| Accessibility label | no tick | — | — |

The key point: the cup used to run at 24 fps inside a main window that was
**always open**, with the countdown in the same block. Now both exist only while
the panel is showing, and when it closes SwiftUI stops rendering them — so at
rest, the app draws nothing at all.

The menu bar label is the exception, and it does not use `TimelineView`. This is
a conclusion from **measurement, not reasoning**: a `MenuBarExtra` label built
on `TimelineView(.periodic(by: 1))` redrew **twice in eight seconds** of an
active countdown, and both redraws came from state changes. SwiftUI renders that
label into an `NSStatusItem`, and inside that frame `TimelineView` does not
tick. Left alone, the icon would sit at full for the whole timer — losing the
one thing that earns it a place on the menu bar.

The only reliable approach is to have the label read an `@Observable` property
that genuinely changes. So `CaffeineController` keeps a `now` and a 1 Hz `Task`
— but that `Task` **lives only while `timerEndsAt != nil`**, and the arithmetic
stays pure: `iconState(at: Date)` takes its instant from the caller, so it is
testable without a real clock.

The label is protected further by quantization: `MenuBarIconState` rounds
progress to 32 steps. The cup interior is 8.8pt tall, which is 18 pixels on a 2x
display — every change smaller than 1/32 lands on the same pixel. That turns the
state into a usable cache key, so an eight-hour timer builds 32 images instead
of 28,800.

## Why the accessibility label states the end time

`CoffeeGauge` used to put the whole block inside a 24 fps `TimelineView`, so the
accessibility element wrapping it was rebuilt every frame. Two consequences:

- VoiceOver lost its anchor and read the label over and over;
- an XCUITest query against that tree ran until it timed out.

The label now says **"On, timer until 15:47"** rather than **"On, 14 minutes
left"**. It is more precise read aloud, and it holds still for the whole timer.

## Why settings decoding is lenient

Settings are the user's data and outlive every version of the app. The
synthesized `Codable` throws on a missing key, and
`UserDefaultsSettingsStore` catches that by returning `Settings()` — which
**wipes the configuration** merely because an older build never wrote a newer
field.

Now each field is read independently with `decodeIfPresent`, plus a
`normalize()` that clamps values into range (including when they arrive from a
hand-edited plist). A `schemaVersion` is written so a real migration has
something to hang off later — that is, when the *meaning* of an existing field
changes, not when a field is added.

## Why "Stop" does not switch itself back on

This is the subtlest part of the app, and someone has already "fixed" it into a
bug once.

`.stopAll` clears `manual`, `timerEndsAt` and **every trigger reason in
`state`** — but does *not* touch each trigger's internal state.
`PowerSourceTrigger` keeps `isCharging == true` while the Mac is still plugged
in, and only emits `.triggerFired` on a genuine `false → true` transition.

Reset that baseline on `stopAll` and the next power notification — with the
condition entirely unchanged — re-enables the rule immediately, and the Stop
button means nothing.

One edge case is accepted and deliberately not fixed: if the user changes any
setting, `rebuildTriggers()` runs, the new trigger set calls `refresh()`, and
that rule may come straight back. That is the consistent consequence of
re-evaluating from scratch, and adding state to prevent it would cost more than
it is worth.

## Testing

| Layer | Tool | Covers |
|---|---|---|
| Core | `swift test` (69 tests) | reduce, assertions, triggers, the settings schema, timers, icon rendering |
| Real IOKit | `IOKitBackingTests` | creates a real assertion and reads it back with `pmset -g assertions` |
| Interface | `CaffeinateUITests` (3 tests) | button → controller → state through `UITestHarnessWindow`; an accessibility label on every control in the Settings window |

There are deliberately few UI tests: XCUITest cannot cope with the 1 Hz
background tick of countdown mode, and bending the app to suit the tool is not a
price worth paying. Countdown behaviour is covered deterministically at the core
layer instead.
