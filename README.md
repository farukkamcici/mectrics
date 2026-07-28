# mectrics

A lightweight, private, modern macOS menu bar system monitor.
Shows CPU, Memory, Battery and more as live **sparklines** in the menu bar, with an
optional live floating panel and a WidgetKit widget.

> Status: **v0.1 MVP + Phase 2 in progress** — the core engine (MetricsKit) and the menu
> bar app work: CPU / Memory / Battery / Network / Disk (+ Bluetooth when a device with a
> battery is connected), sparklines, a detail popover, settings, and launch-at-login.

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
│   ├── UI/                  # popover, sparkline, formatting, localization
│   ├── Settings/            # settings window
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
swift run mectrics-cli      # live CPU/Memory/Battery/Network/Disk
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
Zero telemetry. No usage or hardware data ever leaves the device.

## License
Open source (license to be finalized at the distribution phase — proposal: MIT).
