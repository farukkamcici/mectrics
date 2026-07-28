# 03 — Roadmap & Development Plan

> You are new to macOS, so the plan follows a "smallest working vertical slice first"
> approach. Each phase ends with something working you can actually see.

## 0. Prerequisites
| # | Task | Who |
|---|------|-----|
| 0.1 | Xcode installed (App Store) + Command Line Tools | You (once) |
| 0.2 | Apple Developer account ($99/yr) — needed for notarization & distribution | **You** (owned ✅) |
| 0.3 | Project scaffold, MetricsKit package, initial code | Me |
| 0.4 | Bundle ID, App Group ID (e.g. `com.mectrics.app`) | Together (I propose) |

> Note: a Developer account is **not** needed for development / local runs (it runs on your
> own Mac unsigned / ad-hoc signed). It's only required at the **distribution/notarization**
> stage.

---

## Phase 1 — MVP (v0.1): "Live CPU/Memory/Battery in the menu bar" ✅
**Goal:** app launches, shows CPU %, Memory %, Battery % + sparkline in the menu bar; detail
popover on click; toggle modules in settings; launch at login.

- [x] Xcode workspace + main app target + `MetricsKit` SPM package.
- [x] `SamplingScheduler` + `MetricStore` (ring buffer).
- [x] Providers: **CPU** (`host_processor_info`), **Memory** (`host_statistics64`),
      **Battery** (IOKit IOPS).
- [x] `MenuBarController` + custom drawing (number + sparkline).
- [x] Module detail popover (SwiftUI).
- [x] Settings window (SwiftUI): toggle modules, sampling frequency.
- [x] Launch-at-login via `SMAppService`.
- [x] Adaptive sampling (AC/battery).
- **Output:** a real monitor running on your Mac.

## Phase 2 — Core expansion (v0.5)
**Goal:** the full free core + experience features.
- [x] Providers: **Network** (getifaddrs Δ), **Disk** (capacity + IOKit throughput),
      **Bluetooth** (IORegistry battery). Menu bar + popover integration, tests. *(Clock later)*
- [x] English-first + i18n architecture (String Catalog), CLAUDE.md/AGENTS.md conventions.
- [x] Menu bar width stability (fixed reserved width, right-aligned text).
- [x] **Floating panel** (NSPanel live widget) — draggable, always-on-top, position
      persistence, toggle from Settings/popover.
- [x] **Onboarding** (3 steps: welcome / modules / setup), shown once on first launch.
- [x] **Themes & accent** (9 accent choices incl. system), compact/normal menu bar mode.
- [x] **Notification thresholds** (CPU/Memory/Disk above, Battery below; crossing-edge
      trigger + 15 min cooldown per module).
- [x] **Global hotkey** (⌃⌥M toggles the floating panel — Carbon, no permissions needed).
- **Output:** a daily-usable, "beta-ready" product.

## Phase 3 — Advanced modules & distribution (v1.0)
**Goal:** hardware modules, widget, open-source release, DMG distribution.
- [x] Provider: **GPU** (IOAccelerator PerformanceStatistics — Apple Silicon + Intel).
- [x] Providers: **Sensors/Temperature (SMC)** (key enumeration, plausibility filter,
      CPU/GPU cluster maxima) and **Fans (SMC)** (self-hides on fanless machines).
      Verified on Apple Silicon; Intel uses the same key protocol (untested hardware).
- [ ] **WidgetKit extension** (small/medium/large, App Group snapshot).
- [ ] Advanced notifications, data history/export.
- [ ] **Hardened Runtime + notarization**, **Sparkle** auto-update, DMG packaging.
- [ ] GitHub repo (open source, LICENSE), README, landing/privacy statement, GitHub Releases.
- **Output:** a public, open-source v1.0.

## Phase 4 — v1.x+ (later)
- Advanced per-process view (mini Activity Monitor).
- App Store build (sensor-limited).
- iOS/iPad companion + iCloud sync.
- Localization (multiple languages via the String Catalog).

---

## Decisions made ✅
1. **Distribution:** **Direct / DMG** (Developer ID + notarization). Apple Developer account
   owned. Full sensor/GPU/fan access (no sandbox restriction).
2. **Minimum macOS:** **15 Sequoia** (dev machine macOS 27 / Xcode 26 / Swift 6.3, Apple Silicon).
3. **Monetization:** **fully free & open source.** No Free/Pro split, no licensing code →
   simpler architecture.

## Still to finalize (small)
- **Open-source license:** MIT (permissive) vs GPLv3 (like Stats, keeps derivatives open).
  → Proposal: start with **MIT** (flexibility), change if desired.
- **Bundle ID / brand:** `com.mectrics.app` (proposal). Name "mectrics" assumed final.
- **GitHub org/repo** and Sponsors (optional) — at the distribution phase.

## Risks & mitigations
| Risk | Mitigation |
|------|------------|
| SMC/GPU keys differ and are fragile on Apple Silicon | Reference Stats' open source; test on a hardware matrix; keep sensors optional. |
| App Store sandbox blocks sensors | Direct distribution first; App Store as a separate, limited SKU later. |
| The app itself eats battery/CPU (the iStat complaint) | Adaptive sampling + visibility-aware redraw baked into the architecture. |
| Expectation that WidgetKit is real-time | Feature the floating panel as the "live widget"; position WidgetKit as "at a glance". |
| Notarization/signing is new to you | I'll script it; you only need the Developer account + a one-time certificate setup. |

## Where we are now
**Phase 2 is feature-complete** (v0.5): providers, floating panel, onboarding, themes &
compact mode, notification thresholds, global hotkey. Next: Phase 3 — GPU/Sensors/Fans
(SMC), WidgetKit, notarization + DMG, open-source release.
