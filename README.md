<div align="center">

<img src="Resources/AppIcon.png" width="120" alt="One Percent app icon">

# One Percent

**Get 1% better every day.**

A small daily-goal tracker that lives in your MacBook's notch, with a companion iPhone app.

[![CI](https://github.com/emanueleR3/One-Percent/actions/workflows/ci.yml/badge.svg)](https://github.com/emanueleR3/One-Percent/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple)
![iOS 17+](https://img.shields.io/badge/iOS-17%2B-111?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[**Download for Mac**](https://github.com/emanueleR3/One-Percent/releases/latest) · [Build from source](#build-from-source) · [Leggi in italiano](README.it.md)

<img src="docs/images/mac-panel.png" width="680" alt="The One Percent panel open below the MacBook notch, showing today's goals and progress">

</div>

---

Move the pointer to the notch and your day drops down: today's goals, how far along you are, and
the one thing that matters most. Mark something done, start a timer, push the rest to tomorrow,
move away, and it is gone. No Dock icon, no window to manage.

The iPhone app shows the same day, with widgets and a Live Activity. The two stay in sync through a
free Supabase project of your own, or not at all: each app works fully on its own.

Native Swift and SwiftUI, no third-party dependencies, no analytics.

## Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Install](#install)
- [Build from source](#build-from-source)
- [Cloud sync (optional)](#cloud-sync-optional)
- [Tests](#tests)
- [Project structure](#project-structure)
- [How it works](#how-it-works)
- [Privacy](#privacy)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

## Features

### On the Mac

- **Lives in the notch.** Hover the notch and the panel opens; move away and it closes. It works over
  full-screen apps and on every Space. On a Mac without a notch, a strip at the top of the screen
  (left, center or right) does the same job.
- **Virtual notch.** An optional black notch, a little wider than the real one, that shows today's
  progress ring and `done/total` on its sides, or the running timer.
- **Goals with four states:** to do, in progress, done, tomorrow. Click to complete, double-click to
  rename, drag to reorder, right-click for everything else. Done goals sink to the bottom.
- **The One.** Star the goal that matters most today and it stays on top.
- **Habits.** Repeat a goal every day, on weekdays or on the days you pick, each with its own streak.
- **Tags, steps and notes.** Type `#tags` right in the title; add a checklist and a note on the
  goal's page.
- **Smart quick add** (macOS 26 with Apple Intelligence). Type *"call mom tomorrow #family"* and the
  on-device model picks the day, the repeat and matching tags you already use. Nothing leaves the Mac.
- **Focus timer and Pomodoro.** A stopwatch per goal, or focus blocks with short and long breaks.
  It pauses when the Mac sleeps.
- **Evening wrap-up.** After 21:00 (you choose the time) it offers to move what is left to tomorrow,
  with undo.
- **Gentle reminders.** Optional morning plan, afternoon check-in and evening wrap-up. They are sent
  only when there is something useful to say.
- **Stats.** Streak, 7- and 30-day completion, a 12-week heatmap, your best weekday, focus time per
  goal, and the **1% score**: 1.01 raised to the number of perfect days.
- **English and Italian**, switchable without a relaunch. Launch at login.

### On the iPhone

- **Today screen** with the same goals: swipe for Tomorrow, Delete or The One, long-press for the
  rest, reordering included.
- **Widgets** for the Home Screen (small, medium) and the Lock Screen (circular, rectangular). Goal
  titles are hidden while the phone is locked.
- **Live Activity and Dynamic Island** for the running timer or Pomodoro block, including one started
  on the Mac.
- Goal pages, habits, stats, focus stats, Pomodoro and reminders, as on the Mac.
- **Signature watch.** Installed with a free Apple ID, the app knows when its 7-day signature runs out
  and warns you the evening before.

### Between the two

Goals and habits sync through a Supabase project you own. Changes arrive within a second or two,
every device keeps a full local copy, and both apps keep working offline. Settings stay on each
device. See [Cloud sync](#cloud-sync-optional).

## Screenshots

All screenshots use the sample goals of the [demo mode](#3-iphone-app).

<table>
  <tr>
    <td width="50%"><img src="docs/images/mac-stats.png" alt="Stats page on the Mac: streak, completion, 12-week heatmap and the 1% score curve"></td>
    <td width="50%"><img src="docs/images/mac-focus.png" alt="The Mac panel with a focus timer running on a goal"></td>
  </tr>
  <tr>
    <td align="center"><sub>Stats and the 1% score</sub></td>
    <td align="center"><sub>Focus timer</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td width="25%"><img src="docs/images/ios-today.png" alt="iPhone Today screen with goals, tags and the week strip"></td>
    <td width="25%"><img src="docs/images/ios-detail.png" alt="iPhone goal page with status, time, note, steps and tags"></td>
    <td width="25%"><img src="docs/images/ios-stats.png" alt="iPhone stats with heatmap and 1% score"></td>
    <td width="25%"><img src="docs/images/ios-lockscreen.jpg" alt="iPhone Lock Screen with the focus timer as a Live Activity"></td>
  </tr>
  <tr>
    <td align="center"><sub>Today</sub></td>
    <td align="center"><sub>Goal page</sub></td>
    <td align="center"><sub>Stats</sub></td>
    <td align="center"><sub>Live Activity</sub></td>
  </tr>
</table>

## Install

### Mac

The download runs on Macs with Apple silicon and macOS 14 or later. On an Intel Mac,
[build from source](#build-from-source).

1. Download `One-Percent-v<version>.dmg` from the
   [latest release](https://github.com/emanueleR3/One-Percent/releases/latest), open it and drag
   **One Percent** to **Applications**.
2. The app is signed ad hoc and not notarized by Apple, so macOS blocks it the first time. Open
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or, in Terminal:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/One Percent.app"
   ```
3. Look for the **%** icon in the menu bar, then move the pointer to the notch.

The downloadable build has cloud sync turned off, because sync needs your own Supabase project.
[Build from source](#build-from-source) to turn it on.

### iPhone

The iPhone app is not on the App Store. Build it from source and install it with a free Apple ID, as
described below.

## Build from source

### Requirements

- macOS 14 or later and **Xcode 26.6 or later** (developed with Xcode 27; CI builds with 26.6).
  Smart quick add uses the macOS 26 SDK's on-device model; with an older SDK the app still builds,
  without that feature.
- For the iPhone: iOS 17 or later, an Apple ID signed in to Xcode (a free one works), and Developer
  Mode turned on.
- Python 3, which comes with the Xcode command line tools, for the helper scripts.

### 1. Clone and configure

```bash
git clone https://github.com/emanueleR3/One-Percent.git
cd One-Percent
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Fill in `Config/Local.xcconfig` (git ignores it). Every value is optional: with none, the Mac app and
the iPhone Simulator build work as they are, with cloud sync off.

| Setting | What it is | Needed for |
| --- | --- | --- |
| `ONEPERCENT_TEAM_ID` | Your Apple Team ID. A free Personal Team works. | Installing on an iPhone |
| `ONEPERCENT_BUNDLE_ID` | The iPhone app's bundle ID, unique to you, e.g. `com.yourname.onepercent` | Installing on an iPhone |
| `ONEPERCENT_SUPABASE_HOST` | Your Supabase project's host, **without** `https://` | Cloud sync |
| `ONEPERCENT_SUPABASE_KEY` | The project's publishable key | Cloud sync |

To find your Team ID once Xcode is signed in to your Apple ID:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

It is the 10-character `OU=` value.

> [!TIP]
> Set the team in `Local.xcconfig`, not in Xcode's *Signing & Capabilities* tab: Xcode would write
> it into the shared project file.

### 2. Mac app

```bash
swift run OnePercent           # quick run from the terminal
zsh Scripts/build-app.sh       # builds build/One Percent.app
zsh Scripts/make-dmg.sh        # builds build/One-Percent-v<version>.dmg
```

`swift run` starts a bare binary: the panel works, but reminders, launch at login and cloud sync need
the `.app` bundle. Copy `build/One Percent.app` to `/Applications` to use it every day. You can also
open `Package.swift` in Xcode.

### 3. iPhone app

**Simulator:** open `iOS/OnePercentiOS.xcodeproj`, pick the `OnePercentiOS` scheme and a simulator,
and press Run. No Apple account is needed. On a freshly booted simulator the first launch can stay
black for 10–20 seconds.

**Your iPhone:** plug it in, unlock it, and run:

```bash
zsh Scripts/install-iphone.sh
```

It builds the app, signs it with your team, installs it and opens it. The first time, iOS asks you to
trust the developer: **Settings → General → VPN & Device Management**.

A free Apple ID signs apps for 7 days. To have the Mac renew the signature by itself:

```bash
zsh Scripts/iphone-autorefresh.sh install   # also: status, run, remove
```

A small background job checks every hour and reinstalls the app once 6 days have passed, over Wi-Fi
if the phone is not plugged in. For that, turn on **Connect via network** once, in Xcode under
**Window → Devices and Simulators**.

**Demo mode.** Debug builds launched with `-demo` (Xcode: *Product → Scheme → Edit Scheme → Run →
Arguments*) show sample goals that are never saved or synced. Add `-demoItalian` for Italian data,
`-demoSheet add|settings|stats|detail` to open a screen, or `-demoFocus` to start a timer.

The Xcode project is generated by `Scripts/generate-ios-project.py`. Source folders are synchronized,
so adding a Swift file needs no project change; change the script only for structural edits.

## Cloud sync (optional)

1. Create a free project at [supabase.com](https://supabase.com) and put its host and publishable
   key in `Config/Local.xcconfig`.
2. Run [`supabase/migrations/20261009000000_sync_records.sql`](supabase/migrations/20261009000000_sync_records.sql)
   in the project's SQL editor.
3. Create your user (*Authentication → Users → Add user*), then turn off new sign-ups.
4. Rebuild both apps and sign in from Settings on each device.

The apps only sign in and have no sign-up screen, so with sign-ups off nobody else can use your
project. The full guide, the data format and the checks are in [`supabase/README.md`](supabase/README.md).

## Tests

```bash
swift test                         # 360+ unit tests: core logic, sync engine, Mac panel logic
zsh supabase/tests/run-local.sh    # database schema tests on a throwaway Postgres (needs Docker)
zsh Scripts/test-live.sh           # end-to-end sync against your own Supabase project
```

GitHub Actions runs the unit tests, a Simulator build of the iPhone app and the schema tests on
every push and pull request.

## Project structure

```text
.
├── Package.swift            Swift package: the Mac app, the shared core and the tests
├── Sources/
│   ├── OnePercentCore/      Shared by both apps: models, store, stats, timers, sync, languages
│   └── OnePercent/          The Mac app: notch window, panel, menu bar, reminders, settings
├── iOS/
│   ├── OnePercentiOS/       The iPhone app (SwiftUI)
│   ├── OnePercentWidget/    Widgets and the Live Activity
│   ├── Shared/              Code shared by the app and the widget
│   ├── Config/              Info.plists and entitlements
│   └── OnePercentiOS.xcodeproj   Generated by Scripts/generate-ios-project.py
├── Config/                  Team ID, bundle ID, Supabase project (your values: Local.xcconfig)
├── Resources/               Mac Info.plist, app icon, language packs, DMG background
├── Scripts/                 Build, package, install, localization and config helpers
├── supabase/                Sync backend: migration, schema tests, setup guide
├── Tests/                   Unit tests (XCTest)
└── docs/images/             Screenshots
```

## How it works

- **One core, two apps.** `OnePercentCore` holds everything that has no UI: goal and habit models, the
  store and its operations, the deferral rules, stats, the focus timer and Pomodoro engine, reminder
  planning, languages and the sync engine. The Mac app (AppKit and SwiftUI) and the iPhone app
  (SwiftUI) are thin layers on top.
- **Local first.** Each device keeps its data as JSON in Application Support
  (`~/Library/Application Support/OnePercent/` on the Mac): `tasks.json`, a backup of the previous
  save, and `habits.json`. A file that cannot be read is set aside, never overwritten.
- **Sync.** One Postgres table stores each goal and habit as a JSON document, and row-level security
  keeps every account to its own rows. The apps push and pull over plain REST and listen on a
  Realtime WebSocket, all with `URLSession`. The latest change to an item wins, and deletions travel
  as tombstones.
- **Habits** create their daily goals with deterministic IDs, so the Mac and the iPhone create the
  same goal for the same day instead of two.
- **Timers** are stored as start times, not counters, so they keep counting while an app is closed and
  survive relaunches.

## Privacy

Without a Supabase project the apps make no network requests at all. With one, your goals go only
to that project. There are no accounts besides your own, no analytics and no tracking. Smart quick
add runs on the device.

## Known limitations

- The Mac app is not notarized, so macOS warns before the first launch.
- The iPhone app is not on the App Store; with a free Apple ID its signature lasts 7 days (the
  auto-renew job above handles it).
- Settings, tag colors and reminder times stay on each device; only goals and habits sync.
- Smart quick add is Mac only.
- The interface is in English and Italian.

## Contributing

Bug reports, ideas and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first, and
report security problems privately as described in [SECURITY.md](SECURITY.md). Changes are listed
in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © 2026 Emanuele Romano
