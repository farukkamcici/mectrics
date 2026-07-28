# 05 — Premium Experience Backlog

Status: proposed implementation sequence, researched 2026-07-28.

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
- Working menu bar modules, detail popovers, floating panel, widgets, alerts, and Settings.
- A centered Settings window with close-to-menu-bar lifecycle behavior.
- Three-step onboarding and useful defaults.
- A visual menu bar builder rather than a checkbox-only configuration screen.
- Persistent 30-day history, CSV export, zero telemetry, and a notarized direct-download
  build.

### Largest quality gaps

- First launch explains features before demonstrating a live result.
- There is no shared visual system for spacing, type hierarchy, materials, chart styling,
  empty states, and status treatments.
- Historical data is persisted but not presented as a useful history experience.
- Small sparklines show shape but not time, range, average, selection, or meaning.
- Loading, unavailable, disabled, permission, and failure states are not designed as one
  coherent system.
- VoiceOver, Full Keyboard Access, Increased Contrast, Reduce Transparency, Differentiate
  Without Color, and Reduce Motion are not release-gated.
- Preferences and contextual customization are not yet separated rigorously.
- Update, release-note, About, and recovery flows are incomplete.
- Visual regression coverage and a multi-display/macOS appearance QA matrix are missing.

## Execution plan

Do not expand into per-process monitoring until Milestones A and B are complete. The
existing functionality is sufficient to build a premium v1 experience.

### Milestone A — Premium foundation (P0)

- [ ] **PX-001 — Create an experience baseline and design tokens** `M`
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

- [ ] **PX-003 — Finish the Mac window and app lifecycle** `M`
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
    popover, floating panel, widget, and Settings preview.

- [ ] **PX-006 — Make accessibility a release gate** `L`
  - Add meaningful VoiceOver labels, values, hints, grouping, and reading order.
  - Support Full Keyboard Access with visible focus and no keyboard traps.
  - Respect Increased Contrast, Reduce Transparency, Reduce Motion, and Differentiate
    Without Color.
  - Never encode pressure, health, or alert status with color alone.
  - Give compact charts a spoken summary; give detailed charts navigable values and Audio
    Graph support through Swift Charts.
  - Acceptance: Accessibility Inspector reports no high-priority issues, every workflow
    is keyboard-completable, and the appearance matrix is manually verified.

- [ ] **PX-007 — Establish restrained motion and feedback** `S`
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

- [ ] **PX-009 — Build a calm combined overview** `L`
  - Add an optional single menu bar item that opens an all-modules overview.
  - Lead with current status and the few conditions that need attention, not a wall of
    equal-weight cards.
  - Let users reach module detail in one click and retain separate menu bar items as an
    alternative mode.
  - Acceptance: the overview is useful at its default size without scrolling on the
    reference display and remains fully keyboard accessible.

- [ ] **PX-010 — Turn stored history into insight** `XL`
  - Add a History window with 1h, 24h, 7d, and 30d ranges.
  - Use consistent Swift Charts axes, units, grid density, and color semantics.
  - Support pointer scrubbing with a large plot-area hit target.
  - Show current, minimum, average, maximum, and an objective text summary.
  - Add annotations for alert threshold crossings and power-source changes where useful.
  - Do not hide essential information behind chart interaction.
  - Acceptance: every chart has a stated question, a visible time range, a useful empty
    state, VoiceOver values, a summary, and correct Light/Dark rendering.

- [ ] **PX-011 — Refine menu bar items and detail popovers** `L`
  - Create one consistent popover anatomy: identity, primary value, chart, supporting
    facts, contextual actions.
  - Make collection/stale/error states clear without changing item width.
  - Define and test Escape, repeated click, outside click, Space switching, and Settings
    handoff behavior.
  - Keep rare global actions in menus; do not reintroduce the removed Show/Hide Panel
    button in every module popover.
  - Acceptance: all modules share the same visual rhythm while retaining only the detail
    rows that help interpret that module.

- [ ] **PX-012 — Make the menu bar builder a flagship interaction** `L`
  - Use direct manipulation for add, remove, and reorder with clear drop targets.
  - Keep a live, accurate preview using real values when available.
  - Add keyboard alternatives, undo, and Reset to Recommended.
  - Explain the `Command`-drag macOS menu bar behavior in context, once.
  - Acceptance: a first-time user can create and reorder a menu layout without reading
    documentation.

- [ ] **PX-013 — Polish the floating panel as a native utility** `M`
  - Restore position per display and recover gracefully when a display disappears.
  - Add edge snapping with a subtle threshold and no forced movement.
  - Reveal secondary controls on hover/focus without hiding essential status.
  - Ensure panel close means hide panel, not quit or stop monitoring.
  - Acceptance: the panel remains readable over light and dark content and behaves
    predictably across Spaces and full-screen apps.

- [ ] **PX-014 — Unify widgets with the app** `M`
  - Share typography, color semantics, state language, and chart style.
  - Design explicit collecting, stale, and unavailable timelines.
  - Deep-link a selected widget metric into the relevant app detail/history surface.
  - Acceptance: all widget families pass snapshot review in Light, Dark, tinted, and
    missing-data states.

- [ ] **PX-015 — Make alerts explainable and testable** `M`
  - Add per-rule previews and a test-notification action.
  - Explain threshold, sustained duration, cooldown, and current state inline.
  - Show permission status with a direct system-settings recovery action.
  - Add memory-pressure level as a first-class rule rather than only a percentage.
  - Acceptance: users can predict exactly when an alert will fire before enabling it.

### Milestone C — Release-grade trust and delight (P1)

- [ ] **PX-016 — Complete brand assets for the current macOS design language** `M`
  - Validate the existing icon at 16, 32, 64, 128, 256, 512, and 1024 points.
  - Prepare a layered Icon Composer source for the current macOS visual system while
    preserving a clear silhouette at menu and Finder sizes.
  - Define consistent app, widget, Settings, notification, and menu bar symbol usage.
  - Acceptance: no icon relies on text or thin detail, and every asset is crisp at 1x/2x.

- [ ] **PX-017 — Add the complete trust surface** `L`
  - Integrate Sparkle with a signed appcast and a visible Check for Updates command.
  - Add a native About window with version/build, website, license, privacy, and update
    status.
  - Add concise release notes and a skippable What's New surface for meaningful changes.
  - Make support diagnostics explicit and local-only, with preview before export.
  - Acceptance: install, update, rollback/recovery messaging, About, privacy, and quit
    paths are understandable without external documentation.

- [ ] **PX-018 — Set and enforce performance budgets** `M`
  - Measure cold launch, first sample, idle CPU, memory, wakeups, and energy impact with
    release builds.
  - Pause hidden UI work and avoid chart/model allocations on hot sampling paths.
  - Document reference hardware and measurement conditions.
  - Acceptance: first live metric is under 2 seconds, memory remains below 60 MB, menu
    interactions remain responsive under load, and idle Energy Impact is Low.

- [ ] **PX-019 — Add visual and interaction regression coverage** `L`
  - Add deterministic preview fixtures for every metric and state.
  - Snapshot core surfaces across Light/Dark, Increased Contrast, and long localized
    strings.
  - Add UI tests for onboarding, Settings navigation, window lifecycle, builder reorder,
    popover actions, and alert configuration.
  - Acceptance: the release checklist can reproduce every supported state without waiting
    for real hardware conditions.

- [ ] **PX-020 — Run a release-candidate quality pass** `M`
  - Test clean install, upgrade, first launch, relaunch, sleep/wake, login launch, and app
    removal.
  - Test Apple Silicon laptops/desktops and at least one Intel Mac where possible.
  - Test one-display/two-display, display disconnect, multiple Spaces, and full-screen
    applications.
  - Review every visible string, hit target, focus ring, tooltip, and empty state.
  - Acceptance: no P0/P1 issue remains and the notarized DMG passes Gatekeeper validation
    on a clean Mac account.

## Existing functionality and engineering tasks

These tasks already exist in the code or roadmap. They should not displace the premium
experience milestones unless they block a release:

- [ ] Sparkle update integration and public GitHub Release workflow.
- [ ] Combined mode; tracked as PX-009.
- [ ] History UI; persistence and CSV export are complete, UI is tracked as PX-010.
- [ ] Top applications by network and disk I/O.
- [ ] Daily network totals with persisted day rollover.
- [ ] Kernel memory-pressure alert; tracked as part of PX-015.
- [ ] Bluetooth device-name discovery hardening and fallback labels.
- [ ] User-editable global hotkey recorder.
- [ ] Network counters based on `NET_RT_IFLIST2` for long-uptime robustness.
- [ ] Visibility-aware sampling and sleep pausing, especially for heavy providers.
- [ ] Intel sensor validation and a documented hardware compatibility matrix.
- [ ] Swift 6 language-mode migration for MetricsKit.
- [ ] Public repository, landing page, screenshots, and GitHub Releases.

## Deliberate non-goals for the premium pass

- No splash screen that delays access.
- No glass, gradients, cards, shadows, or animation without a hierarchy or feedback job.
- No custom replacement for a standard Mac control solely to look different.
- No dashboard that gives every metric equal visual weight.
- No new telemetry, account, cloud, weather, public-IP, or location dependency.
- No feature expansion that postpones accessibility, state design, or release QA.

## Recommended first implementation batch

Complete these tasks together because each changes the next:

1. PX-001 — baseline and design tokens.
2. PX-005 — shared state language.
3. PX-002 — first-launch redesign.
4. PX-003 and PX-004 — window lifecycle and Settings architecture.
5. PX-006, PX-007, and PX-008 — accessibility, motion, and content pass.

After that foundation is stable, implement PX-009 through PX-012 as the signature
experience batch.
