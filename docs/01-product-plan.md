# 01 — Product Plan: mectrics

## Vision
> Show your Mac's pulse — without distraction — in the menu bar and in optional live
> widgets; lightweight, private, and beautiful.

**One line:** *As deep as iStat, as open-spirited as Stats, lighter and more modern than both.*

## Target users
1. **Developers / power users** — CPU/RAM/thermals during builds, per-process.
2. **Creators (video/3D)** — GPU, thermals, fans, memory pressure.
3. **General MacBook users** — battery health, a quick "why is it slow?", a clean look.

## Positioning & differentiation
See `00-research.md §4`. Three pillars: **sparkline-first menu bar**, **one calm overview
surface (the Compact Health item)**, **radical lightness + privacy**.

> The originally planned always-on-top floating panel was built and then removed: it
> repeated the menu bar without answering a new question. See `02-architecture.md §5`.

---

## Feature list (modules)

Each module: menu bar indicator (number + optional sparkline) → detail popover on click →
optional widget. A module owns at most one menu bar item.

> **Decision:** the product is **fully free & open source** (see `03-roadmap.md`). There is
> **no** Free/Pro split — all modules are available to everyone. The "Order" column only
> reflects implementation order: *Core* = MVP core, *Later* = hardware-dependent/more complex.

### Metric modules
| Module | Menu bar | Detail / popover | Order |
|--------|----------|------------------|-------|
| **CPU** | Total %, sparkline | Per-core bars, user/system/idle, top 5 processes | Core |
| **Memory (RAM)** | Usage %, sparkline | Used/wired/compressed/cached, **memory pressure**, swap, top 5 processes | Core |
| **Battery** | %, icon, (optional time) | Charge/discharge watts, health %, cycle count, temperature, power source | Core |
| **Network** | ↓/↑ speed | Active interface, IP, session/day totals, top process | Later |
| **Disk** | Usage % or R/W | Per-volume capacity, read/write throughput, SMART status | Later |
| **GPU** | Usage % | GPU utilization, VRAM (if available), thermals | Later |
| **Sensors / Temperature** | Selected sensor °C | All SMC/thermal sensors, CPU/GPU/SSD temps | Later |
| **Fans** | RPM | Per-fan RPM, min/max | Later |
| **Bluetooth** | — (popover) | Connected device battery levels (AirPods, keyboard, mouse) | Later |

### Cross-cutting experience features
- **Sparkline-first**: every module shows a live mini graph of the last ~60 samples.
- **Compact Health item**: one optional menu bar item that stays quiet until an alert
  routed to it activates.
- **WidgetKit desktop/Notification Center widget**: system-native, low-frequency
  (small/medium/large).
- **Notification thresholds**: per-module rules (CPU > 90% for 30s; battery < 20%; disk
  < 10 GB; temperature > 90°C).
- **Theme & accent**: light/dark, accent color, sparkline style, menu bar density
  (compact/normal).
- **Onboarding**: 3 steps — a live menu bar preview → pick modules (recommended set
  preselected) → launch at login. Skippable, and reopenable from Help.
- **Power-aware sampling**: lower the sampling frequency on battery/sleep (lightness +
  battery friendliness).
- **Privacy**: zero telemetry; nothing leaves the device.
- **Launch at login**, **auto-update** (Sparkle).

---

## Monetization — **Fully free & open source** (decided)

No paywall, no license key, no Free/Pro split. All modules are available to everyone.
- **License:** MIT (see `LICENSE`).
- **Distribution:** signed + notarized **DMG** via GitHub Releases; Homebrew Cask later.
- **Sustainability (optional, no pressure):** GitHub Sponsors / "Buy me a coffee" link —
  never gates any feature.
- **Upside:** fast adoption, community trust/contribution, a model Stats has proven.
  "Zero telemetry + open source" is a strong privacy argument.

---

## Success metrics (our own measurement — NOT user data)
- Our own resource use: RAM < 60 MB, average CPU < 1% (idle sampling).
- ~0 crashes; "Low" energy impact in Activity Monitor.
- Adoption (downloads / stars) — no user tracking.

## Out of scope (not in v1)
- iOS/iPadOS companion (v2+).
- iCloud sync (v2+).
- Remote server monitoring.
- Plugin/script system.

## Release targets (summary — details in the roadmap)
- **v0.1 (MVP):** CPU + Memory + Battery in the menu bar, sparkline, popover, settings,
  launch-at-login.
- **v0.5:** Network, Disk, Bluetooth, onboarding, themes, notifications.
- **v1.0:** WidgetKit widget, advanced modules (GPU/Sensors/Fans), notarization + distribution.
