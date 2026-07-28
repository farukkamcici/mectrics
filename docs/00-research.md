# 00 — Market & Competitor Research

> Goal: study "Usage"-style Mac hardware-metric apps, extract the features users expect
> from this category, and identify differentiation opportunities for **mectrics**.

## 1. Products reviewed

| Product | Model | Highlights | Weaknesses |
|---------|-------|------------|------------|
| **Usage** (usage.pro) | Paid + Setapp, macOS/iOS/iPadOS | 40+ menu bar components, "most CPU-friendly" claim, iCloud sync, privacy-focused, nice widgets, per-process CPU/RAM | Closed source, sensor depth below iStat |
| **Stats** (exelban, open source) | Free, MIT, 25k+ ⭐ | CPU/GPU/RAM/Disk/Network/Sensors/Battery/Bluetooth/Clock, native SwiftUI, low resource use, 40+ languages, highly customizable | UI a bit dense/technical, weak onboarding, widget comms off by default (system load) |
| **iStat Menus** (Bjango) | ~$12–30 one-time | Deepest sensor/fan/voltage coverage, historical data, custom sensors, notification thresholds, most mature | **No sparklines**, no keyboard shortcuts, non-movable popover, limited dashboard customization, paid upgrades per major version, battery-drain complaints from some users |
| **MoniThor** | Free | Live sparklines, 8 accent color themes, draggable compact panel, native Apple-Silicon-optimized Swift | New, small ecosystem |
| **Stats Panel / Activity Bar / Air Stats** | Freemium | Lightness, a simple "just CPU/RAM/Network" option | Shallow feature set |

## 2. Most-wanted features (competitor + forum synthesis)

1. **Live sparkline / trend graphs** — not a static number but a mini graph of the last
   ~60 samples (CPU, RAM, network...). iStat's biggest gap.
2. **Keyboard shortcuts** — open the panel without the mouse while in full screen.
3. **Draggable / free-floating panel** — instead of a popover anchored to the menu bar icon.
4. **Low resource use** — native Swift 30–80 MB vs Electron 200–400 MB. The monitor itself
   must not eat battery/CPU. This is the root of iStat's battery complaints.
5. **Deep but readable metrics** — per-core CPU, memory *pressure* (not just usage),
   network up/down, battery health + cycle count, disk read/write throughput, temps/fans.
6. **Notification thresholds** — "alert if CPU > 90% for 30s", "battery below 20%",
   "disk full".
7. **Privacy** — collecting no data is a clear selling point (Usage emphasizes this).
8. **Theme / accent color** — visual personalization.
9. **Simple default + optional depth** — new users shouldn't drown; power users can dig in.
   This is Stats' onboarding weakness.
10. **Per-process view** — a quick "what's eating my CPU/RAM?" answer (mini Activity Monitor).

## 3. Common complaints (to avoid)

- Cluttered menu bar and hard-to-read micro-graphs.
- Mandatory paid upgrades per major version (the iStat model pushes many users to Stats).
- The app itself consuming battery/CPU (especially continuing to measure during sleep).
- Complex, unguided first-run setup.
- WidgetKit widgets not being real-time (system timeline throttling).

## 4. Differentiation thesis for mectrics

> **"iStat's depth + Stats' open spirit + a genuinely light, modern, simple experience."**

Positioning pillars:
1. **Sparkline-first menu bar** — every module shows a live mini graph (close iStat's #1 gap).
2. **Dual widget modes** — (a) a WidgetKit desktop widget (low frequency, system-native),
   (b) the app's own live **floating panel** (real-time, draggable, always-on-top). The user
   picks either or both.
3. **Radical lightness** — native SwiftUI/AppKit, sampling frequency adapted to power/sleep
   (slow down on battery), target < 60 MB RAM and low CPU.
4. **Onboarding + smart defaults** — a 3-step first run; "Simple" and "Pro" profiles.
5. **Privacy guarantee** — zero telemetry, sandbox/hardened runtime, clear privacy statement.
6. **Fair model** — a strong free core; free & open source (no per-version paywall).

## Sources
- [Usage — usage.pro](https://usage.pro/)
- [Stats — mac-stats.com](https://mac-stats.com/) / [GitHub exelban/stats](https://github.com/exelban/stats)
- [iStat Menus — bjango.com](https://bjango.com/mac/istatmenus/)
- [MoniThor — best menu bar apps guide](https://monithor.dev/guides/best-mac-menu-bar-apps)
- [Setapp — best Mac monitoring software](https://setapp.com/app-reviews/best-mac-monitoring-software)
- [MacRumors — iStat Menus battery drain thread](https://forums.macrumors.com/threads/istat-menus-battery-drain-issue.2265412/)
