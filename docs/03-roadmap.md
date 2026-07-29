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
- [x] Providers: **Network** (interface counter Δ), **Disk** (capacity + IOKit throughput),
      **Bluetooth** (IORegistry battery). Menu bar + popover integration, tests.
- [x] English-first + i18n architecture (String Catalog), CLAUDE.md/AGENTS.md conventions.
- [x] Menu bar width stability (fixed reserved width, right-aligned text).
- [x] **Onboarding** (3 steps: welcome / modules / setup), shown once on first launch.
- [x] **Themes & accent** (9 accent choices incl. system), compact/normal menu bar mode.
- [x] **Notification thresholds** (CPU/Memory/Disk above, Battery below; crossing-edge
      trigger + 15 min cooldown per module).
- **Output:** a daily-usable, "beta-ready" product.

## Phase 3 — Advanced modules & distribution (v1.0)
**Goal:** hardware modules, widget, open-source release, DMG distribution.
- [x] Provider: **GPU** (IOAccelerator PerformanceStatistics — Apple Silicon + Intel).
- [x] Providers: **Sensors/Temperature (SMC)** (key enumeration, plausibility filter,
      CPU/GPU cluster maxima) and **Fans (SMC)** (self-hides on fanless machines).
      Verified on Apple Silicon; Intel uses the same key protocol (untested hardware).
- [x] **WidgetKit extension** (small/medium/large, App Group snapshot).
- [x] Sustained-threshold notifications (configurable 0/30/60/120/300-second duration).
- [x] ~~Rolling 30-day hourly history with CSV export~~ — **removed.** The archive only
      ever fed a CSV export; the Attention Log covers "what happened" and popover
      sparklines read the in-memory ring buffer.
- [x] **Hardened Runtime + notarized DMG packaging**.
- [x] **Sparkle** auto-update integrated (feed configured, automatic checks off). The
      appcast still has to be published; tracked as PX-017A.
- [x] LICENSE, README, and privacy statement.
- [x] Public GitHub repository (2026-07-29).
- [ ] Landing page, README screenshots, and the first GitHub Release.
- **Output:** a public, open-source v1.0.

## Phase 4 — v1.x+ (later)
- Advanced per-process view (mini Activity Monitor).
- App Store build (sensor-limited).
- iOS/iPad companion + iCloud sync.
- Localization (multiple languages via the String Catalog).

## Competitive backlog (researched 2026-07-28)
Sources: iStat Menus 7 feature list, Stats (exelban) most-upvoted issues, MacRumors
"iStat vs Stats" thread, Usage app. Ordered by expected value/effort:

**Shipped**
- [x] **Combined mode** — the optional Compact Health item opens a prioritized overview
      (top-voted Stats issue #1084; iStat 7 headline feature).
- [x] **Attention Log** — meaningful activation/recovery events instead of continuous
      Battery or Disk history charts (PX-021).
- [x] **Hardware-domain grouping** — temperatures live inside CPU and GPU, not in a
      separate Sensors module.
- [x] **Visual menu bar builder** — click live preview chips instead of dense checkboxes.

**Still open**
- [ ] **Per-app breakdowns** — top apps by network and disk I/O (iStat has both;
      `nettop`/`fs_usage`-style sampling on popover open, like our Top processes).
- [ ] **Data Today** — daily network totals with per-day rollover (Usage), persisted.
- [ ] **Zero-telemetry + fully offline as a headline** — iStat shows public IP via
      network calls; we can make "makes literally zero network requests" a verifiable
      claim (document it, CI check for network symbols). Sparkle's update check is the
      one deliberate exception and only runs when the user asks for it.

**Dropped**
- **Alert on kernel memory-pressure level** — implemented, then removed: it restated the
  memory usage rule in vocabulary most people cannot act on.

**Deliberately out (privacy/scope)**
- Weather, world clocks, calendar (iStat) — needs network + location; not a monitor's job.
- Public IP / ping — requires external calls; conflicts with the zero-network promise.
- Fan *control* (writes to SMC) — read-only by principle; control apps exist.

---

## Decisions made ✅
1. **Distribution:** **Direct / DMG** (Developer ID + notarization). Apple Developer account
   owned. Full sensor/GPU/fan access (no sandbox restriction).
2. **Minimum macOS:** **15 Sequoia** (dev machine macOS 27 / Xcode 26 / Swift 6.3, Apple Silicon).
3. **Monetization:** **fully free & open source.** No Free/Pro split, no licensing code →
   simpler architecture.

## Still to finalize (small)
- **Sponsors** (optional) — not enabled; decide alongside the first release.

## Risks & mitigations
| Risk | Mitigation |
|------|------------|
| SMC/GPU keys differ and are fragile on Apple Silicon | Reference Stats' open source; test on a hardware matrix; keep sensors optional. |
| App Store sandbox blocks sensors | Direct distribution first; App Store as a separate, limited SKU later. |
| The app itself eats battery/CPU (the iStat complaint) | Adaptive sampling + visibility-aware redraw baked into the architecture. |
| Expectation that WidgetKit is real-time | Feature the menu bar as the live surface; position WidgetKit as "at a glance". |
| A broken update can damage release trust | Sign the Sparkle feed, publish from the same notarized artifact, and test upgrades on a clean account. |

## Where we are now
**Phase 3 product work is done.** GPU/Sensors/Fans, WidgetKit, sustained-threshold
notifications, notarized DMG packaging, the
[premium experience pass](05-premium-experience-backlog.md), and the
[approved feature program](07-approved-feature-program.md) are all complete and verified
on the reference Mac; the repository is public.

What is left before v1.0 is release plumbing rather than product work: publish the
appcast and the first GitHub Release, measure a Release build against the performance
budgets, run the clean-account Gatekeeper check, and add a landing page with screenshots.
