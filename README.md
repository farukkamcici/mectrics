# mectrics

A lightweight, private, modern macOS menu bar system monitor.
Shows CPU, Memory, Battery and more as live **sparklines** in the menu bar, with an
optional Compact Health item that speaks up only when something needs attention.

> Status: **feature complete, preparing the first release.** Modules: CPU / Memory /
> Battery / Network / Disk / GPU / Temperatures (SMC) / Fans (SMC) (+ Bluetooth when a
> device with a battery is connected). Unavailable hardware hides itself (e.g. Fans on a
> fanless MacBook Air). Plus: detail popovers, the Compact Health item, Attention Log,
> Energy Guard, three-step onboarding, accent themes, alert rules with previews and test
> delivery, a visual menu bar builder with layout presets, launch-at-login, local-only
> diagnostics, and small/medium/large WidgetKit widgets. Remaining for v1.0: publishing
> the update feed and the first GitHub Release.

**Lightweight & private by design:** adaptive sampling (slower on battery), Energy Guard
that backs off under Low Power Mode and thermal pressure, zero telemetry, and fixed-width
menu bar items that never jitter as values change.

## Positioning
*iStat's depth + Stats' open spirit + lighter and more modern than either.* See [`docs/`](docs/).

- [00 — Research](docs/00-research.md)
- [01 — Product Plan](docs/01-product-plan.md)
- [02 — Architecture](docs/02-architecture.md)
- [03 — Roadmap](docs/03-roadmap.md)
- [04 — Release and Notarization](docs/04-releasing.md)
- [05 — Premium Experience Backlog](docs/05-premium-experience-backlog.md)
- [06 — Experience Quality Gate](docs/06-experience-quality-gate.md)
- [07 — Approved Feature Program](docs/07-approved-feature-program.md)

Conventions for contributors: [`AGENTS.md`](AGENTS.md) (source of truth) and
[`CLAUDE.md`](CLAUDE.md).

## Project layout
```
mectrics/
├── docs/                    # product & architecture docs
├── project.yml              # XcodeGen project definition (source; .xcodeproj is generated)
├── Mectrics/                # menu bar app (SwiftUI + AppKit)
│   ├── App/                 # AppDelegate, AppModel, LoginItem
│   ├── MenuBar/             # NSStatusItem controller + live sparkline drawing
│   ├── UI/                  # popover, sparkline, formatting, localization, themes
│   ├── Onboarding/          # three-step first-launch flow
│   ├── Alerts/              # alert rules and threshold monitor
│   ├── Attention/           # local Attention Log
│   ├── Energy/              # Energy Guard sampling policy
│   ├── Diagnostics/         # local-only system summary and diagnostics export
│   ├── Release/             # About, What's New, update status
│   ├── Settings/            # settings window (General / Menu Bar / Alerts)
│   └── Resources/           # Localizable.xcstrings (String Catalog)
├── MectricsWidget/          # small/medium/large WidgetKit overview
└── Packages/MetricsKit/     # UI-independent metric engine (SwiftPM)
    ├── Sources/MetricsKit/  # providers, scheduler, store, engine
    ├── Sources/MectricsCLI/ # `swift run mectrics-cli` — terminal demo
    └── Tests/
```

## Requirements
- macOS 15+ (development: Xcode 16+/26, Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Development

**Run the core engine in the terminal (no Xcode needed):**
```bash
cd Packages/MetricsKit
swift run mectrics-cli      # live readout of every provider (incl. GPU/Temp/Fans)
swift test                 # unit tests
```

**Build & run the menu bar app:**
```bash
xcodegen generate          # project.yml -> Mectrics.xcodeproj
open Mectrics.xcodeproj     # then Cmd+R in Xcode
# or from the command line:
xcodebuild -project Mectrics.xcodeproj -scheme Mectrics -configuration Debug build
```

## Internationalization
English-first, fully localizable. User-facing strings use `String(localized:)` / SwiftUI
`Text` and are extracted into a String Catalog. To add a language, open
`Mectrics/Resources/Localizable.xcstrings` in Xcode and translate.

## Privacy
Zero telemetry. No usage or hardware data ever leaves the device. All metrics come from
local system interfaces (public APIs plus the same read-only SMC/IORegistry paths every
open-source monitor uses). The only network request the app can make is an update check,
and only when you choose **Check for Updates…** — automatic checks are off.
See the full [`PRIVACY.md`](PRIVACY.md) statement.

## License
[MIT](LICENSE)
