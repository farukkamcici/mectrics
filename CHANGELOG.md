# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Everything below ships in the first tagged release. Until then, the entries describe the
state of `main`.

### Added

- **Menu bar modules** — CPU, Memory, Battery, Network, Disk, GPU, Temperature (SMC), Fans
  (SMC), and Bluetooth, each drawn as a readable value, with live sparklines for CPU,
  Memory, and GPU. Unavailable hardware hides its module; a missing reading renders as a
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

[Unreleased]: https://github.com/farukkamcici/mectrics/commits/main
