# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Mectrics can now check for updates on its own, if you let it. It asks once, in onboarding
  or on a later launch where it has nothing else to say, and the answer is changeable in
  **Settings → General → Updates**. Consent changes when the appcast is fetched, never what
  the request carries: system profiling stays off, so nothing about you or the Mac is
  attached, and an update is still never downloaded or installed without you. Until it is
  answered, and whenever the answer is no, nothing reaches the network unless you press
  **Check for Updates…**.

## [1.5.0] — 2026-08-04

### Added

- `mectrics alerts watch --json --heartbeat <seconds>` now provides a tagged NDJSON stream
  with immediate readiness, periodic liveness and freshness information, alert events, and
  sampling-coverage transitions.
- `mectrics doctor` validates saved rules, hardware coverage, the executable and optional
  command link, and emits the same diagnosis as versioned JSON with `--json`.
- End-to-end CLI contract tests now execute the real binary with isolated preferences and
  lock down exit codes, stream separation, sampling failures, and version 1 JSON fixtures.
- A local performance harness now records Release CPU, `phys_footprint`, open connections,
  long-run memory growth, and embedded CLI latency with machine-local JSON/CSV reports. It
  runs declared workloads from `scripts/performance/profiles/`, can open a Settings pane so
  that window is measured too, and logs the power source alongside every sample.
- `mectrics://menu-bar` opens the Menu Bar pane of Settings, completing a route table that
  already covered the overview and alerts.
- Points-of-interest signposts and XCTest microbenchmarks cover launch-to-first-sample,
  popover presentation, menu bar formatting, Energy Guard decisions, and the ring-buffer
  hot path.
- A private release-candidate workflow now signs, notarizes, and staples a versioned DMG
  without changing the appcast or publishing a tag or GitHub release.
- Public performance guidance now explains the Release-only measurement method, the
  Activity Monitor CPU and memory scales, and the difference between a smoke gate and a
  long-run stability result.
- Explicit app test and optimized performance schemes now run the app-layer suite instead
  of relying on an implicit build-only scheme; the embedded CLI also uses a distinct Swift
  module name while preserving its lowercase executable.

### Changed

- CLI commands use typed subcommand parsing with command-specific help and conventional
  usage (`64`), software (`70`), and configuration (`78`) exit codes while preserving the
  published `check` health codes `0`, `1`, and `2`.
- Alert checks construct only the providers their enabled rules require. Thermal-pressure
  rules use the native system state directly, and watch sampling adapts to AC or battery.
- Temperatures are sampled only where one is actually on screen — a temperature item, an
  open popover or detail window, the menu bar builder, or a rule that watches the CPU
  temperature. A module simply having a menu bar item no longer keeps the SMC busy.
- Battery and disk are read every second base cycle rather than every cycle. Both move on
  the scale of minutes and each costs an IOKit round trip, and the new cadence stays well
  inside the staleness budget that decides when a reading is shown as out of date.

### Fixed

- A watch session no longer evaluates a cached metric after that provider fails. Repeated
  failures and stale readings now degrade explicit coverage instead of leaving a stream
  silently healthy or allowing an old violation to become an alert.
- Release performance launches no longer leave test or framework bookkeeping in the user's
  real preferences domain or restore a previously open Settings window. A preferences
  domain that did not exist before a run is now removed reliably after it.
- Leaving Settings open no longer costs a large and growing amount of CPU and memory. The
  Menu Bar and Alerts panes rebuilt themselves on every sample, which rebuilt every tooltip
  and hover region with them; live values now live in small fixed-width leaf views, so a new
  reading repaints a caption instead of re-laying out the window. On the reference Mac a
  31-minute run with Settings open went from a 74.9% CPU median to 4.3%, from 1422 seconds
  spent above 10% to 5, and from a 122 MB memory p95 growing at 21 MB/hour to 62 MB growing
  at 2.9 MB/hour.
- A temperature sensor that reads out of range for a moment no longer adds and removes a
  menu bar item, which rebuilt every status item each time it flickered. What a module can
  show is now settled once it has been seen.
- The menu bar previews in Settings reserve the same fixed width as the real items, so
  chips no longer resize as values change.
- The Dock icon now goes away when you close the last Mectrics window. It was decided by
  scanning every window the app owned, which always found the window behind a status item,
  so once the icon appeared it stayed for the rest of the session.
- Closing Settings now releases the window instead of holding it for the session, returning
  roughly 35 MB — more than half of what a menu bar agent is budgeted in total.
- What's New shows the release you just installed. It listed the same three features
  regardless of version, so an upgrade was announced with news from an older release.
- A partially unavailable watch reports the missing conditions in machine-readable status
  and heartbeat records rather than exposing the loss only as a standard-error warning.

## [1.4.0] — 2026-08-01

### Added

- A bundled, read-only `mectrics` CLI for headless Macs. It reuses the alert rules enabled
  in the app, streams activation and recovery events as text or newline-delimited JSON,
  lists configured rules, provides a cron-friendly `check` with meaningful exit codes,
  and captures every available module through a one-shot `snapshot`.
- A one-click CLI installer in Alert settings. It creates `/usr/local/bin/mectrics` as a
  link to the signed executable inside the app, with no second download or background
  service.
- Two alert rules for what macOS itself reports, alongside the existing number
  thresholds. **CPU and GPU slowed to cool down** fires when the system holds the chip
  back — a hot sensor and a machine that is actually being slowed are not the same
  thing, and only the second one costs you time. On Apple silicon the state covers the
  whole chip, so a throttled GPU is included. **Memory pressure** fires on the kernel's
  own verdict rather than on how full memory looks; a Mac can sit at 95% with nothing
  wrong. Both wait for the condition to persist before they say anything, both appear on
  the Compact Health item, and both are recorded in the Attention Log — so after a long
  job you can go back and see the hours your Mac spent held back.

### Changed

- Fan detection now falls back to the read-only per-fan speed keys when a Mac exposes
  fan data but does not return the usual SMC fan-count key.

- Temperatures are no longer sampled for a module that is only being watched by an alert
  rule. Reading the SMC is the most expensive thing Mectrics does, and a rule on CPU
  usage never needed it.

### Fixed

- What's New now appears after an update actually installs. It was only ever shown when
  the app was reopened from the Finder, and an update does not do that — it quits
  Mectrics and starts it again. A menu bar app has no Dock icon to click either, so in
  practice the release notes never appeared for anyone who upgraded.
- Disk read and write throughput no longer reports an impossible figure after a volume
  is ejected. Throughput is the difference between two lifetime byte counters summed
  across every disk, so unplugging an external drive made the total go *backwards* and
  the subtraction wrapped around into roughly ten quintillion bytes per second. A
  shrinking total now reads as no traffic, the same way the network module already
  handled an interface disappearing.
- The Used and Free menu bar items no longer draw outside their reserved slot. Digits are
  monospaced but unit letters are not, and `MB` is wider than the `GB` the slot had been
  sized for — so a disk with a few hundred megabytes left could nudge its neighbours.
- Fan speeds that no fan could reach are ignored instead of shown. An SMC key decoded
  under the wrong type returns a number rather than an error, and that number used to
  reach the menu bar as a fan reading.

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

[Unreleased]: https://github.com/farukkamcici/mectrics/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/farukkamcici/mectrics/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/farukkamcici/mectrics/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/farukkamcici/mectrics/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/farukkamcici/mectrics/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/farukkamcici/mectrics/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/farukkamcici/mectrics/releases/tag/v1.0.0
