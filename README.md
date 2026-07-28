# mectrics

A lightweight, private, modern macOS menu bar system monitor.
Shows CPU, Memory, Battery and more as live **sparklines** in the menu bar, with an
optional always-on-top floating panel.

> Status: **v0.5 — Phases 1–2 complete, Phase 3 providers done.** Modules: CPU / Memory /
> Battery / Network / Disk / GPU / Temperatures (SMC) / Fans (SMC) (+ Bluetooth when a
> device with a battery is connected). Unavailable hardware hides itself (e.g. Fans on a
> fanless MacBook Air). Plus: detail popovers, floating panel (global hotkey **⌃⌥M**),
> three-step onboarding, accent themes + compact menu bar style, notification thresholds,
> settings, launch-at-login. Remaining for v1.0: WidgetKit, notarized DMG distribution.

**Lightweight & private by design:** ~25 MB memory, ~3% CPU with adaptive sampling
(slower on battery), zero telemetry, and fixed-width menu bar items that never jitter
as values change.

## Positioning
*iStat's depth + Stats' open spirit + lighter and more modern than either.* See [`docs/`](docs/).

- [00 — Research](docs/00-research.md)
- [01 — Product Plan](docs/01-product-plan.md)
- [02 — Architecture](docs/02-architecture.md)
- [03 — Roadmap](docs/03-roadmap.md)

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
│   ├── Panel/               # floating always-on-top live panel (NSPanel)
│   ├── Onboarding/          # three-step first-launch flow
│   ├── Alerts/              # notification threshold monitor
│   ├── Hotkey/              # global hotkey (Carbon)
│   ├── Settings/            # settings window (General / Modules / Alerts)
│   └── Resources/           # Localizable.xcstrings (String Catalog)
└── Packages/MetricsKit/     # UI-independent metric engine (SwiftPM)
    ├── Sources/MetricsKit/  # providers, scheduler, store, engine
    ├── Sources/MectricsCLI/ # `swift run mectrics-cli` — terminal demo
    └── Tests/
```

## Requirements
- macOS 15+ (development: Xcode 16+/26, Swift 5.10+)
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
Zero telemetry. The app makes no network requests; no usage or hardware data ever
leaves the device. All metrics come from local system interfaces (public APIs plus the
same read-only SMC/IORegistry paths every open-source monitor uses).

## License
[MIT](LICENSE)
