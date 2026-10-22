# Contributing to One Percent

Thanks for taking the time. Bug reports, ideas, translations and pull requests are all welcome.

## Before you start

- **Bugs:** open an issue with the bug template. Say which app (Mac or iPhone), the OS version, what
  you did, what you expected and what happened.
- **Features:** open an issue first, so we can agree on the idea before you spend time on code. One
  Percent is meant to stay small and calm; not every good feature belongs in it.
- **Security problems:** do not open a public issue. See [SECURITY.md](SECURITY.md).

## Set up

Follow [Build from source](README.md#build-from-source). In short:

```bash
cp Config/Local.example.xcconfig Config/Local.xcconfig   # optional: your Team ID, bundle ID, Supabase
swift build && swift test                                # the core and the Mac app
open iOS/OnePercentiOS.xcodeproj                         # the iPhone app
```

Never commit `Config/Local.xcconfig`, a Supabase `secret` / `service_role` key, or a password.

## Where things go

- Logic that both apps need (models, rules, stats, timers, sync) goes in `Sources/OnePercentCore`,
  with tests in `Tests/OnePercentCoreTests`. It must not import AppKit or UIKit.
- Mac-only code goes in `Sources/OnePercent`, iPhone-only code in `iOS/OnePercentiOS`, widget code in
  `iOS/OnePercentWidget`, and code the iPhone app and widget share in `iOS/Shared`.
- The Xcode project is generated. Adding a Swift file to an existing folder needs nothing else. For
  new targets, settings or capabilities, edit `Scripts/generate-ios-project.py` and run it; do not
  edit `project.pbxproj` by hand.
- Database changes go in a new file in `supabase/migrations/`, with a check in
  `supabase/tests/schema_test.sql`.

## Code style

- Follow the style around you: Swift with SwiftUI, small types, no third-party dependencies.
- Comments explain *why*, in plain English.
- Every user-facing string goes through `L("…")` (or `Lp` for plurals). English text is the key. After
  adding strings, add the Italian translation to `Scripts/translations-it.py` and run
  `python3 Scripts/generate-strings.py`. `LocalizationCoverageTests` fails if a translation is missing.

## Pull requests

1. Branch from `main` and keep each pull request to one change.
2. Add or update tests for behavior changes.
3. Make sure `swift test` passes and the iPhone app builds.
4. Describe what changed and why; for UI changes, add a screenshot.
5. Add a line under *Unreleased* in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.

By contributing, you agree that your work is released under the [MIT License](LICENSE).
