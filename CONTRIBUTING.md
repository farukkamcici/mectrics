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
swift run metricskit-demo               # internal live readout of every provider
swift run mectrics --help               # read-only user automation interface
swift run mectrics check --json         # alert-rule check with a script-friendly exit code
swift run mectrics snapshot --json      # one current reading from every available module
swift run mectrics alerts watch --json  # saved app rules as an NDJSON event stream
swift run mectrics alerts watch --json --heartbeat 60
swift run mectrics doctor --json        # configuration and sampling-coverage diagnosis
```

CLI contract tests live in `Tests/MectricsCLITests`. They exercise typed parsing, exact exit
codes, stdout/stderr separation, versioned JSON fixtures, injected provider failures, and the
real built executable. Add or update a fixture deliberately when changing a public JSON
schema. Valid version 1 `check`, `snapshot`, rule-list, and untagged alert-event output is a
compatibility contract.

For app-layer changes:

```bash
xcodegen generate
xcodebuild -project Mectrics.xcodeproj -scheme Mectrics -configuration Debug build
```

mectrics is an `LSUIElement` agent — no Dock icon, no main window. Verify visual changes in
the menu bar and popover directly.

## Performance validation

Performance numbers come from an optimized Release app without Xcode, a debugger, code
coverage, or sanitizers attached. Build an unsigned local candidate for development, then
measure it directly:

```bash
xcodegen generate
xcodebuild build \
  -project Mectrics.xcodeproj \
  -scheme Mectrics \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/performance/DerivedData \
  ENABLE_CODE_COVERAGE=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM=""

./scripts/performance/measure.sh \
  --app build/performance/DerivedData/Build/Products/Release/Mectrics.app \
  --scenario idle-ac

./scripts/performance/measure-cli.sh \
  --app build/performance/DerivedData/Build/Products/Release/Mectrics.app

xcodebuild test \
  -project Mectrics.xcodeproj \
  -scheme MectricsPerformance \
  -destination 'platform=macOS'
```

### The two workloads a release is gated on

The menu bar and an open Settings window fail for different reasons, so both are measured.
Run them back to back on a quiet Mac, on AC power, with nothing else launched:

```bash
./scripts/performance/measure.sh \
  --app build/performance/DerivedData/Build/Products/Release/Mectrics.app \
  --profile scripts/performance/profiles/alerts-ac.json \
  --scenario alerts-ac-menu-only
```

```bash
./scripts/performance/measure.sh \
  --app build/performance/DerivedData/Build/Products/Release/Mectrics.app \
  --profile scripts/performance/profiles/alerts-ac.json \
  --settings menu-bar \
  --scenario alerts-ac-settings-open
```

A profile is a small JSON file under `scripts/performance/profiles/` declaring the alert
rules and the menu bar layout to measure. The launcher encodes it as old-style plist data
on the app's own command line, so a declared workload still never touches the contributor's
preferences. `--settings <general|menu-bar|alerts>` opens a pane by sending the running app
a `mectrics://` route, which is why the run refuses to start next to another Mectrics: a
second copy would answer the route instead.

Every run records `power-source.csv` beside its samples. Adaptive sampling makes a run that
slipped onto battery a different measurement, so check that file before quoting a number.

`measure.sh` launches the app with isolated preferences, excludes a five-minute warm-up,
then records CPU, `phys_footprint`, and open connections every five seconds. It enforces the
60 MB memory budget, idle CPU and network gates, and memory growth on runs long enough to
make a slope meaningful. Pass `--pid` to observe an already-running CLI watch. Optional
`--powermetrics` output is diagnostic and requires existing administrator authorization;
it is not part of the clean baseline.

The launcher uses process-only argument defaults, disables window restoration, and restores
an exact snapshot of the preferences domain after the app exits. Framework bookkeeping is
therefore removed along with the test setup, including a domain that did not exist before
the run — cfprefsd can flush a departing process's writes after it is gone, so the removal
is retried until it stays gone. A restored Settings window would measure a different
workload and can also expose operating-system UI regressions.

Running the app-layer XCTest suite is not covered by any of this: the test host *is* the
app, so it launches with your real preferences and leaves its own bookkeeping behind. Run
the gates before the tests, or clear the domain in between.

The default idle CPU gates are a 3% median, 5% p95, and no interval above 10% sustained for
more than 30 seconds. CPU percentage comes from process CPU-time deltas, not `ps`'s smoothed
display value. Override a budget through the documented `MECTRICS_MAX_*` environment
variables only when defining a deliberate hardware-specific baseline.

Results are local JSON and CSV under ignored `build/performance/`. Compare p50 and p95 on
the same Mac, OS, power source, settings, and sampling scenario. A single Activity Monitor
refresh is not a baseline, and RSS is never the product memory number.

When reporting a result, include the app version and configuration, warm-up and measured
duration, power source, scenario, and enabled modules. Quote CPU median and p95 together;
quote post-warm-up `phys_footprint` p95 for memory. State whether the 30-minute memory-slope
gate ran. A short smoke run may validate the sampler and the immediate budgets, but it must
not be presented as evidence of long-run stability or as a universal result for every Mac.
Activity Monitor's process CPU scale assigns 100% to one logical core, so preserve the
measurement window when comparing its display with a gate report.

The `MectricsPerformance` scheme uses an optimized `Performance` configuration with
testability enabled. The shipping `Release` configuration stays non-testable. Ordinary app
logic tests use the Debug `Mectrics` scheme; CI runs those tests in addition to building the
app.

For a private distribution-equivalent candidate, use `scripts/release-candidate.sh` with
the same signing and notary environment variables as `scripts/release.sh`. It writes under
`build/candidate/<version>/`, signs, notarizes, and staples the DMG without changing the
appcast or publishing anything.

## Before you open a pull request

- [ ] `swift test` passes in `Packages/MetricsKit`.
- [ ] `xcodebuild ... build` succeeds and produces no new warnings. MetricsKit builds in the
      Swift 6 language mode and must stay warning-free.
- [ ] Performance-sensitive changes pass the Release process and CLI gates on the same
      baseline machine.
- [ ] New or changed user-facing strings go through `String(localized:)` / SwiftUI `Text`.
- [ ] If you added or removed files, `xcodegen generate` was run and `project.yml` reflects it.
- [ ] If you added a menu bar component or changed a format, its width template is updated.
- [ ] If you bumped `MARKETING_VERSION`, `ReleaseHighlights` has notes for the new version
      and they are translated in both string catalogs.
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

Read the [Non-goals](README.md#non-goals) section before starting anything large. It is
the fastest way to find out that an idea will not be merged, and it is kept short so that
there is no excuse for not reading it.

Some things were tried and deliberately reversed: the always-on-top floating panel and its
global hotkey, and the 30-day archive with CSV export. Please open an issue for discussion
before reviving either of them.

Kernel memory-pressure and thermal-state alert rules were also once reversed, then brought
back after a user pointed out that a hot sensor and a throttled machine are not the same
thing. A reversal is a decision about a moment, not a permanent verdict; argue with one if
you have the case for it.

Issues and pull requests may take time to review. A polite nudge after a week or two is
welcome.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating you
are expected to uphold it.
