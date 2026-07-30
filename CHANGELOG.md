# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] — 2026-07-30

### Changed

- Mectrics uses noticeably less CPU while it sits in the menu bar. A status item is only
  redrawn when its reading actually changed, disk space is read through a cheap system
  call instead of one that wakes a background service every second, and the graphics and
  sensor readings copy only the values they need.
- Launching is roughly three times cheaper in CPU terms, so the menu bar fills in sooner
  after login.
- Monitoring now steps down while nobody can see it — a sleeping display, a locked
  screen, or another user's session — and returns to full speed with a fresh reading the
  moment you come back.
- Battery and disk readings follow their own pace, which slows down further on battery
  and under thermal pressure while everything on screen stays current.

## [1.2.0] — 2026-07-30

### Added

- Independent temperature menu bar components for CPU, Memory, and GPU, plus Memory
  temperature in its detail popover when the Mac exposes a recognized sensor.

## [1.1.0] — 2026-07-30

### Added

- Complete English, Turkish, Russian, Spanish, French, and Brazilian Portuguese
  localizations for the app and widgets, with an in-app language picker under General
  Settings.
- A built-in clean uninstall flow that removes Mectrics, its preferences, alert rules,
  local history, and caches without requiring administrator access.

### Changed

- Diagnostics and system-summary exports now follow the selected app language.
- Technical translations use the terminology found in each language's macOS interface,
  including Activity Monitor, System Settings, battery, memory, disk, and network labels.
- Translation contributor guidance now covers both String Catalogs and the language picker.

### Fixed

- The manual uninstall script now removes the Sparkle cache.
- Failed login-item changes are reported to the uninstall flow instead of being ignored.

## [1.0.0] — 2026-07-30

The first release. Distributed as a signed and notarized DMG.

Measured on the reference Mac, a Release build holds steady at **25 MB** of memory with
roughly one idle wake per second.

### Added

- **Menu bar modules** — CPU, Memory, Battery, Network, Disk, GPU, Temperature (SMC), and
  Fans (SMC), each drawn as a readable value, with live sparklines for CPU, Memory, and
  GPU. Unavailable hardware hides its module; a missing reading renders as a
  dash rather than a fabricated zero.
- **Fixed-width status items** — every component reserves a worst-case width and
  right-aligns monospaced digits, so values change without the menu bar shifting.
- **Detail popovers** with per-module breakdowns, top processes, and contextual actions.
- **Compact Health** — an optional single status item that summarizes the machine and
  surfaces only what needs attention.
- **Alert rules** — sustained-threshold notifications with live previews and test delivery.
- **Attention Log** — a local, exportable record of what tripped and when.
- **Energy Guard** — normal / reduced / protected sampling driven by power source, Low Power
  Mode, and thermal pressure.
- **Menu bar builder** — a visual layout editor with presets and live preview chips.
- **WidgetKit widgets** in small, medium, and large sizes, fed through an App Group snapshot.
- **Diagnostics** — a local-only system summary that can be copied or exported as plain text.
- **Three-step onboarding**, accent themes, and launch-at-login via `SMAppService`.
- **MetricsKit** — a UI-independent SwiftPM engine (providers, adaptive scheduler,
  pre-allocated ring buffer store) with a `mectrics-cli` terminal readout.
- **Internationalization** — English base strings extracted into a String Catalog; adding a
  language requires no code change.

### Security

- Release builds use Hardened Runtime, a Developer ID signature, and notarization.
- Automatic update checks are disabled; the Sparkle appcast is fetched only on an explicit
  **Check for Updates…** and verified against a pinned EdDSA public key.

[1.2.0]: https://github.com/farukkamcici/mectrics/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/farukkamcici/mectrics/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/farukkamcici/mectrics/releases/tag/v1.0.0
