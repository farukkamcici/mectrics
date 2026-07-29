# 05 — Premium Experience Backlog

Status: the premium experience pass is complete as of 2026-07-29. What remains is release
work — publishing the update feed, measuring a Release build, and the clean-account
install check — plus one open icon decision.

Detailed closure units for the approved follow-on features are defined in
[`07-approved-feature-program.md`](07-approved-feature-program.md). A parent task in this
document remains open until every child task assigned to it in that program is accepted.

## Product experience goal

Mectrics should feel calm, precise, native, and trustworthy from the first second. The
premium quality comes from hierarchy, responsiveness, restraint, and excellent edge-case
behavior — not from adding decoration to every surface.

The intended first impression is:

1. The app opens immediately and already has useful defaults.
2. A live preview explains the product faster than prose.
3. Every window, menu, popover, and keyboard command behaves like a first-class Mac app.
4. Dense system data becomes a small number of clear answers.
5. Privacy, accessibility, and low energy use are visible product qualities.

## Research synthesis

The most relevant patterns from Apple's current guidance and award selections are:

- **Clarity before ornament.** The 2026 Apple Design Awards praise Primary for a minimal
  UI that gets out of the content's way and Moonlitt for simple, elegant interaction and
  easy onboarding.
- **Charts need a point of view.** Tide Guide is recognized for making rich data crisp and
  understandable. Apple recommends giving every chart a clear goal, a strong hierarchy,
  useful context, direct scrubbing, and a nonvisual summary.
- **Onboarding is optional product use, not a presentation.** Apple recommends a fast,
  interactive, skippable flow after launch, with strong defaults and nonessential setup
  postponed.
- **Native behavior is part of the visual design.** Mac users expect standard window,
  menu, keyboard, focus, active/inactive, and multi-display behavior.
- **Accessibility is a quality multiplier.** The 2026 Inclusivity winner, Guitar Wiz,
  combines VoiceOver, larger text, Increased Contrast, and Differentiate Without Color
  instead of treating accessibility as a final audit.
- **Motion explains state.** Apple recommends brief, precise, interruptible motion that
  respects Reduce Motion and avoids animating frequent interactions unnecessarily.
- **Settings should be smaller than the product.** Good defaults reduce setup; only
  infrequently changed preferences belong in Settings, while contextual controls stay
  near the surface they affect.

Primary sources:

- [2026 Apple Design Award winners](https://developer.apple.com/design/awards/)
- [Apple HIG: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Apple HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
- [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Apple HIG: Charts](https://developer.apple.com/design/human-interface-guidelines/charts)
- [WWDC22: Design an effective chart](https://developer.apple.com/videos/play/wwdc2022/110340/)

## Current experience audit

### Strong foundation

- Stable-width, monospaced menu bar rendering.
- Native SwiftUI/AppKit surfaces and standard controls.
- Working menu bar modules, detail popovers, the Compact Health item, widget snapshot
  pipeline, alerts, and Settings.
- A centered Settings window with close-to-menu-bar lifecycle behavior.
- Three-step onboarding and useful defaults.
- A visual menu bar builder rather than a checkbox-only configuration screen.
- Zero telemetry and a notarized direct-download build.

### Gaps closed by the premium pass

The audit gaps that opened this document are closed and verified on the reference Mac:
first launch now demonstrates live readings, `ExperienceDesignSystem` is the shared visual
system, `MetricDataState` is one state language across every surface, the accessibility
and Reduce Motion behavior is release-gated, Settings separates preferences from
contextual controls, About/What's New/diagnostics complete the trust surface, and the
widget registers in the gallery and reads live values.

### Remaining gaps

- The update feed is configured but not published, so no upgrade has been installed
  through Sparkle yet (PX-017A).
- Energy and memory budgets have not been measured on a Release build (PX-018).
- Automated visual regression coverage does not exist; appearance and lifecycle checks
  are manual (PX-019).
- No Intel Mac and no fan-equipped Mac have exercised GPU, Sensors, and Fans; see the
  hardware compatibility matrix in
  [`06-experience-quality-gate.md`](06-experience-quality-gate.md).

## Execution plan

Do not expand into per-process monitoring. The existing functionality is sufficient for a
premium v1 experience.

### Milestone A — Premium foundation (P0)

- [x] **PX-001 — Create an experience baseline and design tokens** `M`
  - Capture every current surface in Light, Dark, and Increased Contrast appearances.
  - Define a small token set for spacing, corner radii, type roles, accent usage, chart
    strokes, separators, materials, and animation durations.
  - Add reusable native components for section headers, metric values, status badges,
    empty states, and inline notices.
  - Acceptance: no feature surface invents its own spacing, card, status, or chart style.

- [x] **PX-002 — Redesign the first 45 seconds** `L`
  - Launch directly into a useful native window; do not add a blocking splash screen.
  - Replace the prose-first welcome with a live menu bar preview and real local readings.
  - Keep setup short, interactive, optional, and available again from Help.
  - Start with a recommended module set; postpone fine customization to the visual
    builder.
  - Explain zero telemetry in one concise proof-oriented line.
  - Acceptance: a clean install shows its first live metric within 2 seconds on the
    reference Mac, onboarding can be skipped, and completion takes under 45 seconds.

- [x] **PX-003 — Finish the Mac window and app lifecycle** `M`
  - Open Settings centered at a deliberate compact size on first use.
  - Restore the last pane, but clamp saved frames to the visible area of the current
    display.
  - Closing the last standard window removes the Dock icon while metrics continue
    running; reopening Settings restores the regular app presence.
  - Verify `Command-,`, `Command-W`, `Command-Q`, Escape, app activation, and reopen from
    Finder/Dock/menu bar.
  - Acceptance: behavior is correct across two displays, display removal, Space changes,
    relaunch, and sleep/wake.

- [x] **PX-004 — Simplify Settings information architecture** `M`
  - Keep a stable, noncustomizable toolbar with a clearly selected pane and matching
    window title.
  - Restore the last selected pane and disable minimize/zoom for pane-sized Settings.
  - Rename and regroup panes around user intent: General, Menu Bar, Alerts.
  - Keep task-specific actions, such as module ordering and panel layout, next to their
    live previews instead of duplicating them in General.
  - Remove settings that merely repeat a systemwide preference.
  - Acceptance: every option has one home, every change previews immediately, and no pane
    requires unexplained scrolling at its default size.

- [x] **PX-005 — Design one state language for the whole app** `M`
  - Define collecting, live, unavailable, disabled, permission-required, stale, and error
    states.
  - Never display a fabricated zero when the app has no valid sample.
  - Pair each recoverable state with one direct action and one plain-language reason.
  - Preserve the last valid value during short refreshes and mark it stale when necessary.
  - Acceptance: every provider state has a deterministic representation in the menu bar,
    popover, widget, and Settings preview.

- [x] **PX-006 — Make accessibility a release gate** `L`
  - Add meaningful VoiceOver labels, values, hints, grouping, and reading order.
  - Support Full Keyboard Access with visible focus and no keyboard traps.
  - Respect Increased Contrast, Reduce Transparency, Reduce Motion, and Differentiate
    Without Color.
  - Never encode pressure, health, or alert status with color alone.
  - Give compact charts a spoken summary; give detailed charts navigable values and Audio
    Graph support through Swift Charts.
  - Acceptance: Accessibility Inspector reports no high-priority issues, every workflow
    is keyboard-completable, and the appearance matrix is manually verified.

- [x] **PX-007 — Establish restrained motion and feedback** `S`
  - Use motion only for hierarchy, state changes, and direct manipulation.
  - Keep common transitions brief and interruptible; avoid animating every sampling tick.
  - Replace spatial transitions with fades or immediate changes under Reduce Motion.
  - Ensure menu bar widths, labels, and window layouts never shift when values update.
  - Acceptance: no animation delays an action, no continuous decorative animation runs in
    the background, and all Reduce Motion paths are tested.

- [x] **PX-008 — Standardize copy, numbers, units, and help** `M`
  - Use concise sentence case, consistent module names, and consistent unit precision.
  - Explain what a metric means near the metric, not in a distant documentation page.
  - Add tooltips to unfamiliar symbols and secondary controls.
  - Replace implementation terms such as fractions, providers, or snapshots in UI copy.
  - Acceptance: a terminology/formatting table covers every metric and all new strings are
    localizable through the String Catalog.

### Milestone B — Signature Mectrics experience (P1)

- [x] **PX-009 — Build a calm combined overview** `L`
  - Implement the optional Compact Health item specified by PX-009A.
  - Lead with active conditions selected for the health surface, not a wall of
    equal-weight modules.
  - Let users reach module detail in one click and retain separate menu bar items as an
    alternative mode.
  - Acceptance: PX-009A is complete.

- [x] **PX-011 — Refine menu bar items and detail popovers** `L`
  - Create one consistent popover anatomy: identity, primary value, chart, supporting
    facts, contextual actions.
  - Make collection/stale/error states clear without changing item width.
  - Define and test Escape, repeated click, outside click, Space switching, and Settings
    handoff behavior.
  - Keep rare global actions in menus; do not reintroduce the removed Show/Hide Panel
    button in every module popover.
  - Acceptance: all modules share the same visual rhythm while retaining only the detail
    rows that help interpret that module.

- [x] **PX-012 — Make the menu bar builder a flagship interaction** `L`
  - Give each module its own row, and pick components by clicking live preview chips
    inside it — several components per module stay available.
  - Keep a live, accurate preview using real values, including for modules that are not
    in the menu bar yet.
  - Add keyboard alternatives, undo, Reset to Recommended, and exactly three initial
    presets that vary along one axis: Essentials, Recommended, and Detailed.
  - Explain the `Command`-drag macOS menu bar behavior in context, once.
  - Acceptance: a first-time user can create a menu layout without reading
    documentation, and PX-012A is complete.

- [x] **PX-014 — Unify widgets with the app** `M`
  - Restore native widget gallery discovery and App Group data sharing before visual
    polish.
  - Share typography, color semantics, state language, and chart style.
  - Design explicit collecting, stale, and unavailable timelines.
  - Deep-link a selected widget metric into the relevant app detail surface.
  - Acceptance: PX-014A and PX-014B are complete, and all widget families pass snapshot
    review in Light, Dark, tinted, and missing-data states.

- [x] **PX-015 — Make alerts explainable and testable** `M`
  - Preserve all existing threshold rules and migrate their settings without silently
    enabling a new delivery.
  - Let each rule choose among Notification, Compact Health item, and Attention Log
    destinations.
  - Add per-rule previews and a test-notification action.
  - Explain threshold, sustained duration, cooldown, and current state inline.
  - Show permission status with a direct system-settings recovery action.
  - Add available disk capacity and macOS battery service as first-class signals
    alongside the existing percentage rules. Kernel memory pressure and thermal state
    were tried and removed: power-user vocabulary that restated an existing rule.
  - Acceptance: PX-015A, PX-015B, and PX-015C are complete, and users can predict exactly
    when an alert will activate and where it will appear.

### Milestone C — Release-grade trust and delight (P1)

- [x] **PX-016 — Complete brand assets** `M`
  - The icon is validated at 16, 32, 64, 128, 256, 512, and 1024 points, 1x and 2x. The
    mark is a single bold letterform on a solid field: no text, no thin detail, and a
    silhouette that still reads at menu and Finder sizes.
  - App, widget, Settings, notification, and menu bar symbols come from one SF Symbols
    mapping (`MetricSymbol`).
  - **Scope decision (2026-07-29):** ship the flat PNG icon set. A layered Icon Composer
    source would only add the macOS 26+ dynamic material and tint variants, which is a
    refinement, not a correctness problem — revisit it if a future macOS treatment makes
    the flat icon look wrong.
  - Acceptance: no icon relies on text or thin detail, and every asset is crisp at 1x/2x.

- [ ] **PX-017 — Add the complete trust surface** `L`
  - Integrate Sparkle with a signed appcast and a visible Check for Updates command.
  - Add a native About window with version/build, website, license, privacy, and update
    status.
  - Add concise release notes and a skippable What's New surface for meaningful changes.
  - Make support diagnostics explicit and local-only, with preview before export.
  - Acceptance: PX-017A, PX-017B, and PX-017C are complete, and install, update,
    rollback/recovery messaging, About, privacy, diagnostics, and quit paths are
    understandable without external documentation.

- [ ] **PX-018 — Set and enforce performance budgets** `M`
  - Measure cold launch, first sample, idle CPU, memory, wakeups, and energy impact with
    release builds.
  - Pause hidden UI work and avoid chart/model allocations on hot sampling paths.
  - Document reference hardware and measurement conditions.
  - Acceptance: first live metric is under 2 seconds, memory remains below 60 MB, menu
    interactions remain responsive under load, and idle Energy Impact is Low.

- [x] **PX-019 — Keep every supported state reproducible without hardware** `M`
  - Cover each metric state, alert lifecycle, preset, route, summary, and export path with
    deterministic tests that need no real hardware condition.
  - Keep the manual appearance and lifecycle matrix in
    [`06-experience-quality-gate.md`](06-experience-quality-gate.md) as the visual gate.
  - **Scope decision (2026-07-29):** pixel snapshot testing and XCUITest automation were
    dropped. Snapshots would add an external testing dependency to a product whose selling
    point is a small local footprint, and XCUITest cannot drive `NSStatusItem` popovers in
    an accessory app, so the suite would assert little while breaking often.
  - Acceptance: the release checklist can reproduce every supported state from tests plus
    the documented manual matrix.

- [ ] **PX-020 — Run a release-candidate quality pass** `M`
  - Done on the reference Mac: install, first launch, relaunch, sleep/wake, login launch,
    every visible string, hit target, focus ring, tooltip, and empty state.
  - Remaining: an upgrade installed through the published feed, Gatekeeper validation of
    the notarized DMG on a clean Mac account, and any Intel or multi-display machine that
    becomes available.
  - Acceptance: no P0/P1 issue remains and the notarized DMG passes Gatekeeper validation
    on a clean Mac account.

### Milestone D — Approved local intelligence (P1)

- [x] **PX-021 — Add a local Attention Log** `L`
  - Record meaningful condition activation and recovery, not continuous Battery or Disk
    charts.
  - Keep records bounded, local, deduplicated, and free of personal identifiers.
  - Acceptance: the independently closable PX-021 task in
    `07-approved-feature-program.md` is complete.

- [x] **PX-022 — Add Automatic Energy Guard** `M`
  - Adapt heavy sampling to Low Power Mode, thermal state, power source, visibility, and
    sleep/wake without hiding the behavior.
  - Acceptance: the independently closable PX-022 task in
    `07-approved-feature-program.md` is complete.

- [x] **PX-023 — Add validated routing and contextual actions** `M`
  - Give widgets and metric details one allowlisted route model and useful native next
    actions.
  - Acceptance: PX-023A and PX-023B are complete.

- [x] **PX-024 — Add a privacy-safe System Summary** `S`
  - Copy a concise allowlisted current-state summary without personal identifiers.
  - Acceptance: the independently closable PX-024 task in
    `07-approved-feature-program.md` is complete.

## Existing functionality and engineering tasks

These tasks already exist in the code or roadmap. They should not displace the premium
experience milestones unless they block a release:

- [ ] Sparkle update integration and public GitHub Release workflow; the app ships with
      Sparkle configured, so what remains is publishing the feed (PX-017A).
- [x] Combined mode; delivered as the Compact Health item (PX-009).
- [x] Attention Log (PX-021).
- [ ] Top applications by network and disk I/O.
- [ ] Daily network totals with persisted day rollover.
- [x] ~~Kernel memory-pressure alert~~ — removed with PX-015C; it restated the memory
      usage rule in power-user vocabulary.
- [x] Bluetooth device-name discovery hardening and fallback labels. Names now fall back
      through the known product keys to the registry entry name, duplicate registry nodes
      and out-of-range levels are dropped, and a scan without devices clears the name
      channel so a later scan cannot pair a stale name with another device.
- [x] ~~User-editable global hotkey recorder~~ — removed with the floating panel; the app
      has no global hotkey.
- [x] Network counters based on `NET_RT_IFLIST2` for long-uptime robustness. `getifaddrs`
      remains a fallback, and a decreasing total reads as no traffic instead of a spike.
- [x] Visibility-aware sampling and sleep pausing, especially for heavy providers;
      delivered by Energy Guard (PX-022).
- [ ] Intel sensor validation. The hardware compatibility matrix is documented in
      [`06-experience-quality-gate.md`](06-experience-quality-gate.md); GPU, Sensors, and
      Fans still need an Intel machine, and Fans need any fan-equipped Mac.
- [x] Swift 6 language-mode migration for MetricsKit. The package builds warning-free in
      the Swift 6 language mode; `MetricProvider` now requires `Sendable`.
- [ ] Landing page, README screenshots, and GitHub Releases. The repository itself is
      public as of 2026-07-29.

## Deliberate non-goals

- No splash screen that delays access.
- No glass, gradients, cards, shadows, or animation without a hierarchy or feedback job.
- No custom replacement for a standard Mac control solely to look different.
- No dashboard that gives every metric equal visual weight.
- No new telemetry, account, cloud, weather, public-IP, or location dependency.
- No feature expansion that postpones accessibility, state design, or release QA.

Tried and dropped, with the reason, so they are not proposed again:

- **A dedicated history experience** (formerly PX-010) and continuous Battery or Disk
  history charts. The 30-day archive existed only to feed a CSV export, and no surface
  asked a question that needed it. Reopen only when a specific user question cannot be
  answered by the Attention Log, current details, or alerts.
- **The floating panel** (formerly PX-013), its global hotkey, its two layout modes, and
  its per-display placement. It answered the same question as the menu bar while costing
  a second rendering surface; the Compact Health item is the supported overview.
- **Kernel memory-pressure and thermal-state alert rules.** Power-user vocabulary that
  restated rules the app already states plainly.
- **Pixel snapshot tests and XCUITest automation** (see PX-019).

## What remains

1. PX-017A — publish the release feed, then install an upgrade through it.
2. PX-018 — measure the Release build against the performance budgets.
3. PX-020 — clean-account Gatekeeper check once the notarized DMG is published.
4. Landing page and README screenshots.

The independently closable child tasks live in
[`07-approved-feature-program.md`](07-approved-feature-program.md).
