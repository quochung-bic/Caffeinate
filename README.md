<img src="Caffeinate/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" align="right" alt="Caffeinate icon">

# Caffeinate

A macOS menu bar app that keeps your Mac awake when you need it to be — and
stops when you don't.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![Universal](https://img.shields.io/badge/binary-Intel%20%2B%20Apple%20Silicon-black)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![MIT license](https://img.shields.io/badge/license-MIT-blue)

Unlike dragging a slider in System Settings and forgetting to drag it back,
Caffeinate lets you say exactly **what to keep awake**, **for how long**, and
**when to turn itself on**. When the time is up, it's up — your Mac goes back to
its normal sleep behaviour.

---

## Contents

- [Features](#features)
- [Interface](#interface)
- [Requirements](#requirements)
- [Installing](#installing)
- [Development](#development)
- [Architecture](#architecture)
- [Not yet](#not-yet)
- [License](#license)

---

## Features

### Hold exactly what you mean to hold

Four aspects you can switch independently, each one its own IOKit power
assertion:

| Flag | What it holds |
|---|---|
| System | The Mac won't go to sleep |
| Display | The screen won't turn off |
| Disk | Disks won't spin down |
| Idle | The system won't count you as idle |

Only **System** is on by default. Keeping the screen lit costs battery and is
rarely what you actually need, so it should be something you choose rather than
something the app decides for you.

### Timers that end

One click for 15 minutes, 30 minutes, an hour, your own custom duration
(1–480 minutes), or on indefinitely.

When the timer runs out, Caffeinate tells you **three independent ways** — a
notification banner, one chime, and a blinking menu bar icon — because any one
of them can go silent: banners get blocked by Do Not Disturb, sound is useless
when your headphones are in another room, and the icon only helps if you happen
to be looking at the menu bar.

### Turn on by itself

Three rules, each optional:

- an app from a list you choose is running (a VM, a renderer, a compiler);
- the Mac is plugged into power;
- an external display is connected.

The rules never fight you: **Stop** is decisive and clears even the rules that
are currently true. A rule only comes back when its condition genuinely happens
again — unplug and plug back in, not a few seconds later when the system sends
another "still charging" notice.

### Readable at a glance

The central image is a cup of coffee where **the level is the progress bar**:
full when you turn it on, draining with the countdown, steaming only while the
Mac is genuinely being held awake. The same shape appears twice — large in the
panel, and shrunk to 18×18 as the menu bar icon.

### Launch at login

Registered through `SMAppService`, off by default. There is also an option to
turn on the moment the app starts, which only applies while launch-at-login is
enabled — if the app doesn't start when you log in, that option has nothing to
act on.

---

## Interface

Caffeinate is a pure menu bar app: **no Dock icon, no main window**. That is an
architectural decision rather than an aesthetic one — the menu bar icon is the
only surface that always exists, so everything that has to survive the session
hangs off it.

- **Menu bar panel** — click the icon for the draining cup, the duration
  buttons, the state of all four flags, and why it is currently on.
- **Settings window** (⌘,) — four tabs: *General*, *Automatic*, *Startup*,
  *About*. ⌘W closes it, ⌘Q quits the app.

---

## Requirements

- macOS 14 (Sonoma) or newer — runs on both Intel and Apple Silicon
- Xcode 16 or newer (Swift 6) to build

---

## Installing

There is no prebuilt release yet, so for now you build from source, which means
you need **Xcode 16 or newer** installed first — the Command Line Tools on their
own are not enough. It is free on the App Store; open it once after installing
so it can finish setting itself up.

```bash
git clone https://github.com/quochung-bic/Caffeinate.git
cd Caffeinate
./Scripts/install.sh
```

`install.sh` builds a Release binary, asks any running copy to quit, replaces
`/Applications/Caffeinate.app` and opens it. Run the same command again whenever
you want to update. Use `--test` to run the whole suite first, `--destination`
to install elsewhere (see the warning at the end of this section), and `--help`
for every option.

Because you compiled it yourself, the bundle carries no quarantine flag:
Gatekeeper neither blocks it nor asks about it — quite unlike a `.app`
downloaded from the internet. The signature is ad-hoc, which is enough to run on
your own Mac; handing it to other people needs a Developer ID and notarization.

To uninstall: quit the app from the menu bar and drag `Caffeinate.app` to the
Trash. The only thing left behind is
`~/Library/Preferences/io.github.quochung-bic.Caffeinate.plist`.

### Build without installing

```bash
./Scripts/build.sh
```

The product lands in `build/Caffeinate.app`, and the script verifies that a
Release build really is a universal binary. Add `--debug` for a fast
host-architecture build, `--test` to run the tests first, `--help` for every
option.

Or call `xcodebuild` directly:

```bash
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' -configuration Release build
```

Release always produces a universal binary (arm64 + x86_64). To check:

```bash
lipo -info /path/to/Caffeinate.app/Contents/MacOS/Caffeinate
# Architectures in the fat file: ... are: x86_64 arm64
```

If you build by hand, remember to copy `Caffeinate.app` into `/Applications` —
that is what `install.sh` does for you. This step is not just tidiness:
**launch at login only works while the app lives in `/Applications`**, because
`SMAppService` refuses to register a bundle anywhere else. Running from
`build/` or `~/Applications` leaves everything else working; only that one
switch will report an error, and it explains why.

Or open `Caffeinate.xcodeproj` in Xcode and press Run.

---

## Development

```bash
# build from the command line (see `--help` for every option)
./Scripts/build.sh

# 69 core unit tests — fast, no GUI needed
./Scripts/build.sh --unit-only

# the 3 UI tests: smoke and accessibility labels (~1 minute, takes the screen)
./Scripts/build.sh --ui-only

# both layers
./Scripts/build.sh --test-only

# run one suite, or a single test
./Scripts/build.sh -u -f 'CaffeineController'

# build the app
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' build

# build plus the 3 UI tests: smoke and accessibility labels (~1 minute)
xcodebuild -project Caffeinate.xcodeproj -scheme Caffeinate \
           -destination 'platform=macOS' test

# redraw the whole app icon set
swift Scripts/GenerateAppIcon.swift
```

Build settings live in [`Configs/`](Configs/) rather than in `project.pbxproj` —
every choice carries a comment explaining why.

Architecture, invariants and the places that are easy to get wrong:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Architecture

The core is a separate SwiftPM package; the app target is only interface and
wiring:

```
CaffeinateKit/          pure Swift package — all the logic, no GUI, no display strings
  Core/                 AssertionFlags, AssertionManager, IOKitBacking
  State/                CaffeineEvent, CaffeineState, reduce
  Triggers/             app running, plugged in, external display
  Storage/              settings persisted to UserDefaults
  Rendering/            menu bar icon drawing (AppKit)
  CaffeineController    the source of truth for the UI
Caffeinate/             app target — SwiftUI plus the app lifecycle
  MenuBar/              the menu bar label and the control panel
  Settings/             the Settings window, four tabs
  Components/           the coffee cup, duration buttons, flag grid
  Services/             launch at login, timer expiry alert
  DisplayText.swift     the bridge from core types to words on screen
Configs/                build settings (.xcconfig) and entitlements
Scripts/                build script and app icon generator
CaffeinateUITests/      UI tests — smoke and accessibility labels
```

Four principles are held strictly throughout:

**One path for state changes.** `CaffeineController` is the *only* caller of
`AssertionManager.set(flags:)`. Every change goes `send(event) → reduce() →
apply()`. There is no shortcut, so the system's real state is always derivable
from the app's state.

**Clear layering.** The package never imports SwiftUI; `Core/` and `State/`
never import AppKit; the app target never imports IOKit. All IOKit use is
confined to two files: `IOKitBacking.swift` and `PowerSourceTrigger.swift`.

**The core holds no words.** `CaffeinateKit` contains no display strings at all.
It returns types, and `DisplayText.swift` is the single place that turns them
into sentences. That keeps the core testable with no notion of presentation, and
means rewording the interface never reaches into the state machine.

**Nothing fails silently.** A failed assertion create throws and forces the state
off — it never pretends to be on. A failed release is recorded and shown to the
user rather than swallowed.

---

## Not yet

- **Developer ID signing and notarization.** On another Mac the first launch is
  blocked by Gatekeeper (right-click → Open to get past it).
- **A prebuilt release** to download.
- **Icon Composer's `.icon` format** for macOS 26. The current `.appiconset`
  renders correctly on macOS 14, 15 and 26, but does not pick up Tahoe's Liquid
  Glass treatment. That needs the Icon Composer GUI app.

---

## License

[MIT](LICENSE) © 2026 Quốc Hưng
