<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/banner-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/assets/banner-light.svg">
  <img alt="mectrics — a lightweight, private system monitor that lives in your macOS menu bar" src="docs/assets/banner-light.svg" width="100%">
</picture>

<p>
  <img alt="Platform: macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2ea44f?style=flat-square"></a>
  <a href="https://github.com/farukkamcici/mectrics/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/farukkamcici/mectrics/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Telemetry: none" src="https://img.shields.io/badge/telemetry-none-8957e5?style=flat-square">
</p>

<p><b>CPU · Memory · Battery · Network · Disk · GPU · Temperature · Fans · Bluetooth</b><br>
live in your menu bar — readable at a glance, and the bar never jumps around.</p>

</div>

---

## What it is

**mectrics** is a native macOS menu bar system monitor. Each module you enable draws a
readable value — with a live sparkline where a trend actually tells you something — and
stays out of the way otherwise. A click opens a detail popover with the numbers behind it.
An optional **Compact Health** item collapses the whole machine into a single indicator
that speaks up only when something needs attention.

It is built around three commitments:

| | |
|---|---|
| 🔒 **Private by construction** | Zero telemetry. No analytics, no identifiers, no crash reports. The only network request the app can make is an update check you trigger yourself — automatic checks are off by default. |
| 🪶 **Light on the machine** | Sampling slows down on battery and backs off under Low Power Mode and thermal pressure. Target: under 60 MB of memory and "Energy Impact: Low". |
| 📐 **Stable in the menu bar** | Items reserve a fixed width, so values change without anything shifting sideways. |

> [!NOTE]
> **Status: pre-release.** The app is feature complete and in daily use. What is left before
> v1.0 is release plumbing — publishing the signed update feed and the first GitHub Release.
> Until then, [build it from source](#install).

## Modules

<div align="center">
  <img src="docs/assets/menubar.png" alt="Mectrics in the macOS menu bar: free disk space, memory, CPU with a sparkline, and network activity" width="872">
</div>

Unavailable hardware hides itself — no Fans module on a fanless MacBook Air, no Battery on
a Mac mini, no Bluetooth module until a device that reports a battery is connected. **A
missing reading shows a dash, never a fabricated `0`.**

| Module | What you can put in the menu bar | Sparkline |
|---|---|---|
| **CPU** | Usage %, per-core bars | ✅ |
| **Memory** | Usage %, used memory | ✅ |
| **GPU** | Utilization % | ✅ |
| **Battery** | Level with charge indicator, icon, health, cycles | — |
| **Network** | Stacked ↓/↑ activity, download only, upload only | — |
| **Disk** | Usage %, ring, used, free | — |
| **Temperature** | Hottest CPU reading in °C | — |
| **Fans** | Fastest fan RPM | — |
| **Bluetooth** | Connected device battery % | — |

Sparklines are drawn for the three metrics where a trend is genuinely informative. The rest
show a value, because a chart of your disk's fill level is decoration.

A module can contribute **several independent items** — Battery can show its icon *and* its
health side by side. You pick components by clicking a live preview chip in the menu bar
builder, so you choose from what you can actually see. Each popover adds the detail behind
the value: per-core load and top processes for CPU, swap and pressure for Memory,
read/write throughput for Disk, and so on.

<div align="center">
  <img src="docs/assets/popover-disk.png" alt="The Disk popover: a usage ring, a used/purgeable/free bar, capacity figures, and live read and write throughput" width="620">
</div>

## Beyond the numbers

- **Compact Health** — one status item that summarizes the whole machine and surfaces only
  what is off.
- **Alert rules** — sustained-threshold notifications with a live preview and test delivery,
  so you know what a rule will look like before it fires at 3am.
- **Attention Log** — a local, exportable record of what tripped and when.
- **Energy Guard** — sampling that steps down under Low Power Mode and thermal pressure.
- **Menu bar builder** — a visual layout editor with presets, where you toggle components
  by clicking their live preview instead of guessing from a list.
- **Widgets** — small / medium / large WidgetKit overviews for Notification Center.
- **Diagnostics** — a local-only system summary you can copy or export as plain text.
- **Three-step onboarding**, accent themes, and launch at login.

<table>
<tr>
<td width="50%" valign="top">
  <img src="docs/assets/settings-menubar.png" alt="The Menu Bar settings pane: a live preview of the menu bar, and every module's components as clickable chips" width="100%">
  <p align="center"><sub><b>Menu bar builder</b> — click a live chip to add or remove it</sub></p>
</td>
<td width="50%" valign="top">
  <img src="docs/assets/settings-alerts.png" alt="The Alerts settings pane: threshold rules for CPU, memory, battery, disk, GPU, and temperature, each with a sustained duration" width="100%">
  <p align="center"><sub><b>Alert rules</b> — with the current reading next to each threshold</sub></p>
</td>
</tr>
</table>

## Install

Requires **macOS 15 (Sequoia)** or newer.

The first signed and notarized DMG ships with v1.0. Until then, build it yourself:

```bash
git clone https://github.com/farukkamcici/mectrics.git
cd mectrics
brew install xcodegen
xcodegen generate
open Mectrics.xcodeproj      # then ⌘R
```

Full setup notes, including code signing, are in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Privacy

Zero telemetry — not "anonymized", not "opt-out". No usage data, hardware information,
metric history, or alert configuration ever leaves the device. Every number comes from a
local, read-only system interface.

The single network request the app can make is an update check, and only when you choose
**Check for Updates…**. Read the full statement in [`PRIVACY.md`](PRIVACY.md).

## Contributing

Contributions are welcome — new hardware coverage and translations especially.

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — setup, the development loop, how to add a metric
  provider or a translation
- [`AGENTS.md`](AGENTS.md) — the conventions this repository enforces, and the source of
  truth for them
- [`docs/architecture.md`](docs/architecture.md) — how the app and the metric engine fit
  together, and where each number comes from

**Adding a language needs no code change:** open
[`Localizable.xcstrings`](Mectrics/Resources/Localizable.xcstrings) in Xcode, add your
language, translate, and open a pull request.

## Security

Found a vulnerability? Please report it privately — see [`SECURITY.md`](SECURITY.md).

## Acknowledgements

Prior art that set the bar: [Stats](https://github.com/exelban/stats) for proving an open
source monitor can be excellent, and iStat Menus for the depth people expect. Built with
[Sparkle](https://github.com/sparkle-project/Sparkle) for updates and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) for a reviewable project file.

## License

[MIT](LICENSE) © Faruk Kamçıcı
