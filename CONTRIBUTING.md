# Contributing to mectrics

Thanks for considering a contribution. This document covers the practical steps; the
conventions themselves live in [`AGENTS.md`](AGENTS.md), which is the source of truth for
this repository. Please read it before your first pull request — it is short.

## Ground rules you should know up front

1. **The repository is English-only.** Source, comments, documentation, commit messages,
   branch names, PR titles and descriptions, and the base UI strings. Other languages are
   added through the String Catalog, never in source.
2. **Menu bar item width must never depend on the current value.** Every item reserves a
   fixed width from a worst-case template and right-aligns monospaced digits inside it. A
   value that grows a digit must not push its neighbours.
3. **Absence is not zero.** When a reading is unavailable, render a dash. Never fabricate
   `0%` and never offer a component this Mac cannot report.
4. **Zero telemetry.** The only network call the app may make is an explicit update check.
5. **`project.yml` is the source.** `Mectrics.xcodeproj` is generated output and is not
   committed. Run `xcodegen generate` after adding or removing files.

## Setting up

```bash
git clone https://github.com/farukkamcici/mectrics.git
cd mectrics
brew install xcodegen
xcodegen generate
open Mectrics.xcodeproj
```

Requirements: macOS 15+, Xcode 16 or newer, Swift 6.

### Code signing

No Apple Developer Team ID is committed. `project.yml` fills `DEVELOPMENT_TEAM` from the
`MECTRICS_TEAM_ID` environment variable at generation time, so if you want Xcode to sign
your local builds automatically, export your own before generating:

```bash
export MECTRICS_TEAM_ID=YOURTEAMID   # add it to your shell profile
xcodegen generate
```

Leave it unset and the setting resolves to empty — fine for building unsigned, which is
what CI does. **Never commit a Team ID, a signing identity, or notary credentials.**

## The development loop

The metric engine is a standalone SwiftPM package, so most core work needs no Xcode:

```bash
cd Packages/MetricsKit
swift test
swift run mectrics-cli   # live readout of every provider
```

For app-layer changes:

```bash
xcodegen generate
xcodebuild -project Mectrics.xcodeproj -scheme Mectrics -configuration Debug build
```

mectrics is an `LSUIElement` agent — no Dock icon, no main window. Verify visual changes in
the menu bar and popover directly.

## Before you open a pull request

- [ ] `swift test` passes in `Packages/MetricsKit`.
- [ ] `xcodebuild ... build` succeeds and produces no new warnings. MetricsKit builds in the
      Swift 6 language mode and must stay warning-free.
- [ ] New or changed user-facing strings go through `String(localized:)` / SwiftUI `Text`.
- [ ] If you added or removed files, `xcodegen generate` was run and `project.yml` reflects it.
- [ ] If you added a menu bar component or changed a format, its width template is updated.
- [ ] Commit messages are English with an imperative subject and a body explaining the *why*.

## Adding a metric provider

The full recipe is in [`AGENTS.md` §6](AGENTS.md#6-adding-a-metric-provider). In short:

1. Add a `MetricProvider` under `Packages/MetricsKit/Sources/MetricsKit/Providers/`.
2. Return `isAvailable = false` when the hardware or permission is absent — the module then
   hides itself automatically.
3. Register it in `MetricsKit.coreProviders()`.
4. Add menu bar text in `MenuBarText` plus a stable width template in `MetricStatusItem`.
5. Add popover rows and a primary value in `DetailPopoverView`, with localized labels.
6. Add a sanity test in `MetricsKitTests`.

Providers are sampled on one serial queue and declare a `cost` (`light` / `medium` /
`heavy`). SMC, GPU, and sensor work is `heavy` and is sampled less often — respect that
budget; a provider that blocks the queue degrades every other module.

## Adding a translation

1. Add the language and its identifier to `Mectrics/App/AppLanguage.swift`.
2. Add it to both `Mectrics/Resources/Localizable.xcstrings` and
   `MectricsWidget/Localizable.xcstrings`.
3. Translate every entry in both catalogs; partial catalogs are not accepted.
4. Verify the language picker and relaunch flow, then check the widget under that system
   language.

Note that numeric and symbolic menu bar strings (percentages, rates, arrows) are
intentionally not localized.

## Reporting bugs and requesting features

Use the [issue templates](https://github.com/farukkamcici/mectrics/issues/new/choose). For
bugs, the Mac model, macOS version, and affected module matter more than anything else — a
lot of behaviour here is hardware-specific. The app's **Diagnostics** export is local-only
plain text and is the fastest way to give a complete picture; review it before attaching.

## Scope

Some things were tried and deliberately reversed: the always-on-top floating panel and its
global hotkey, the 30-day archive and CSV export, and kernel memory-pressure / thermal-state
alert rules. Please open an issue for discussion before reviving any of them.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating you
are expected to uphold it.
