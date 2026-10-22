# Changelog

All notable changes to One Percent. Versions follow [Semantic Versioning](https://semver.org); the
format follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

## [0.1.3] - 2026-10-22

First public, open-source release.

### Changed
- The Apple Team ID, bundle ID, App Group and Supabase project now come from
  `Config/Local.xcconfig` (see `Config/Local.example.xcconfig`) instead of the source code, so anyone
  can build and sign the apps with their own account.
- Cloud sync is turned on only in builds that have a Supabase project; without one the apps work
  fully on each device and the cloud section is hidden.
- The demo mode and the widget preview use generic sample goals, in English or Italian.

### Added
- README in English and Italian, MIT license, contributing guide, security policy and this changelog.
- GitHub Actions: unit tests, an iPhone Simulator build and the database schema tests.

## [0.1.2] - 2026-10-10

### Added
- Timers keep running across relaunches and show in the Dynamic Island and on the Lock Screen.

## [0.1.1] - 2026-10-10

### Added
- The iPhone app's free 7-day signature is renewed automatically from the Mac, and the app warns the
  evening before it runs out.

## [0.1.0] - 2026-10-09

### Added
- The iPhone app: Today, goal editing, stats, settings, reminders and cloud sign-in.
- iPhone timer, Pomodoro, reordering, Home and Lock Screen widgets, score curve and focus stats.
- Goal titles are hidden in the widgets while the phone is locked.

### Fixed
- Tags and steps stay clickable while the pointer is over a goal.

## [0.0.8] - 2026-10-09

### Added
- Cloud sync between devices through Supabase, and the shared `OnePercentCore` package.

## [0.0.7] - 2026-10-09

### Added
- The goal page suggests every known tag.

## [0.0.6] - 2026-10-09

### Fixed
- The stats tabs no longer change size; click haptics removed.

## [0.0.5] - 2026-10-09

### Fixed
- The goal list is always scrolled to the top when the panel opens.

## [0.0.4] - 2026-10-09

### Added
- Focus timer, virtual notch, Italian and English language packs, compact time pill.

## [0.0.3] - 2026-10-09

### Added
- Habits, The One, tags, notes, steps, evening wrap-up, reminders and smart quick add.

## [0.0.2] - 2026-10-09

### Added
- Streaks, week strip, stats page, 1% score and the "moved" badge.

### Changed
- Redesigned panel: progress hero, animated status marks, scroll cues.

## [0.0.1] - 2026-10-09

### Added
- The notch panel on the Mac: daily goals with statuses, reordering, deferral to tomorrow, day
  navigation within a week, and the menu bar item.

[Unreleased]: https://github.com/emanueleR3/One-Percent/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/emanueleR3/One-Percent/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/emanueleR3/One-Percent/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/emanueleR3/One-Percent/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/emanueleR3/One-Percent/compare/v0.0.8...v0.1.0
[0.0.8]: https://github.com/emanueleR3/One-Percent/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/emanueleR3/One-Percent/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/emanueleR3/One-Percent/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/emanueleR3/One-Percent/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/emanueleR3/One-Percent/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/emanueleR3/One-Percent/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/emanueleR3/One-Percent/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/emanueleR3/One-Percent/releases/tag/v0.0.1
