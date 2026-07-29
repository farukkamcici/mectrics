# 07 — Approved Feature Program

Status: implemented and closed on 2026-07-29, except PX-017A, which waits on a published
release feed. The closure evidence, including the manual verification the owner performed
on the reference Mac, is recorded in
[`06-experience-quality-gate.md`](06-experience-quality-gate.md).

This document turns the approved product decisions into independently closable tasks.
It complements the higher-level experience backlog in
`05-premium-experience-backlog.md` and the verification matrix in
`06-experience-quality-gate.md`.

## Product direction

Mectrics should answer two questions:

1. Does this Mac need attention now?
2. If it does, what can the user do next?

The approved work therefore favors meaningful events, low-noise alerts, contextual
actions, low energy use, and reliable system integration over additional continuous
charts or a denser dashboard.

The following decisions are fixed for this program:

- Preserve the existing CPU, memory, disk, battery, and temperature threshold rules.
- Add new alert signals and delivery choices without silently replacing existing rules.
- Keep all event, metric, summary, and diagnostic data local.
- Do not add continuous Battery or Disk history charts.
- The 30-day archive and its CSV export were removed; the Attention Log is the record
  of what happened, and its own export covers portability.
- Keep separate menu bar items available when the optional compact health item ships.
- Use native SwiftUI, AppKit, WidgetKit, UserNotifications, and Foundation behavior.
- Keep every new user-facing string in the String Catalog.

## Task closure protocol

The checkboxes in this document are the authoritative completion state for this program.
A task remains unchecked while it is being implemented. Mark it complete only after all
of the following are true:

1. Its implementation and migration behavior are complete.
2. New user-facing strings are localizable and the repository remains English-only.
3. MetricsKit tests and the relevant app tests pass.
4. The Debug app builds. Release/signing work also requires a Release archive.
5. The task-specific manual acceptance checks below have been exercised.
6. Accessibility, Light/Dark appearance, Increased Contrast, and Reduce Motion are
   verified where the task changes UI.
7. Completion evidence is added to `06-experience-quality-gate.md` or the release
   candidate record.

A parent task in `05-premium-experience-backlog.md` closes only after every child task
listed here for that parent has closed. Partial implementation is not completion.

## Implementation order (completed)

The program was implemented in dependency order: the route model before widget deep
links, so the app has one allowlisted entry point for widgets, notifications, and future
system integrations; and the alert event model before the Attention Log and Compact
Health item, so those surfaces share one definition of an active condition. Only PX-017A
remains, because it needs a published release feed rather than more application code.

## Widget recovery and integration

### Resolved gallery-discovery defect

The widget was embedded and Developer ID signed but never appeared in the widget gallery.
The cause was repository-owned: the extension lacked
`com.apple.security.app-sandbox`, which macOS requires to register a WidgetKit
extension. Enabling App Sandbox for the extension only — never for the main metrics
process, which needs local hardware access — restored gallery discovery, and removing the
Debug-only private-container fallback made the signed App Group the single snapshot path.
Widgets now read live values from the gallery on the reference Mac.

- [x] **PX-014A — Restore native widget gallery discovery and shared data** `P0 / M`

  Outcome: a cleanly installed Mectrics build appears in the macOS widget gallery and
  every supported family reads the app's latest shared snapshot.

  Scope:

  - Enable App Sandbox for the widget extension only; do not sandbox the main metrics
    process, which requires local hardware access.
  - Keep the App Group entitlement on both targets and make the Debug/Release entitlement
    behavior explicit in `project.yml`.
  - Verify that the extension is embedded once, signed with the expected team, and
    registered as a WidgetKit extension.
  - Remove the Debug-only private-container fallback after signed Debug App Group sharing
    works, or document a deliberate fallback if local unsigned builds require it.
  - Add a widget diagnostics row in the app only if the system cannot be made reliably
    discoverable without it; do not add a private registration workaround.
  - Test a build made with the latest stable Xcode separately from beta OS/toolchain
    testing.

  Acceptance:

  - Install the exported app into `/Applications` on a clean macOS account.
  - Launch Mectrics once, open the widget gallery, search for Mectrics, and add small,
    medium, and large widgets without Terminal intervention.
  - `pluginkit` lists `com.mectrics.app.widget` for the installed application.
  - The installed app and extension pass `codesign --verify --deep --strict`.
  - Both signatures contain the expected App Group and the extension contains
    `com.apple.security.app-sandbox`.
  - A live snapshot written by the app appears in all three widget families.
  - Relaunch, reboot, app replacement, and notarized-DMG installation do not make the
    widget disappear.
  - The result is verified on macOS 15 or the oldest available supported system and on
    the current stable macOS release; beta-only behavior is recorded separately.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-014B — Deep-link each widget metric into Mectrics** `P1 / M`

  Depends on: PX-014A and PX-023A.

  Outcome: selecting a metric in a widget opens that metric's native detail surface,
  rather than opening an unrelated Settings pane.

  Scope:

  - Use `Link` for individual rows in families that have enough interaction area and
    `widgetURL(_:)` as the whole-widget fallback.
  - Route through the allowlisted metric route defined by PX-023A.
  - Reuse the existing detail content in a compact app-owned detail window when a
    menu-bar popover has no valid anchor.
  - Preserve the normal menu bar popover interaction when the user enters from a status
    item.
  - Define deterministic fallback behavior for unavailable, disabled, stale, and unknown
    metric routes.

  Acceptance:

  - Every visible metric row opens the matching metric detail.
  - The small-family fallback opens a useful overview or its primary visible metric.
  - A disabled or unavailable metric opens an explanatory state with its recovery action.
  - An invalid or unknown URL cannot execute an arbitrary action and falls back safely.
  - The route works from a cold launch, while the app is running as an accessory app, and
    while Settings is already open.
  - Keyboard, VoiceOver, window activation, `Command-W`, and close-last-window behavior
    remain correct.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

## Alerts, attention, and the compact health item

- [x] **PX-015A — Preserve current alert rules and add explicit destinations** `P1 / L`

  Outcome: existing threshold alerts remain intact, while each rule can control where
  its state appears.

  Scope:

  - Preserve and migrate the current CPU, memory, disk, battery, and temperature rules,
    including enabled state, threshold, sustained duration, and cooldown behavior.
  - Replace the implicit notification-only model with explicit destinations:
    Notification, Compact Health item, and Attention Log.
  - Provide calm defaults: enabled rules log their lifecycle; notifications and compact
    health visibility remain explicit user choices.
  - Do not create duplicate notifications when one condition is shown on multiple
    surfaces.
  - Keep a single active-condition identity across threshold evaluation, the log, and the
    compact health item.
  - Keep delivery settings progressively disclosed so the common Alerts row stays easy
    to scan.

  Acceptance:

  - An upgrade preserves every existing rule and does not enable a new notification
    without the user's choice.
  - A rule can be notification-only, log-only, health-item-only, or any supported
    combination without being deleted.
  - Changing a destination does not reset the threshold or sustained-duration values.
  - One sustained violation produces one active condition and no duplicate deliveries.
  - Disabled rules create no new attention events or notifications.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-015B — Add live rule previews, test delivery, and permission recovery** `P1 / M`

  Outcome: users can understand and test a rule before relying on it.

  Scope:

  - Show the current reading, comparison direction, threshold, sustained duration,
    cooldown, destination, and whether the rule is currently normal, pending, or active.
  - Add a Test Notification action that is clearly labeled as a test and does not create
    a real threshold event.
  - Read the actual `UNNotificationSettings` authorization state.
  - When authorization is denied or delivery is disabled, show one direct recovery action
    to the relevant System Settings page.
  - Explain that the system controls final notification presentation.

  Acceptance:

  - Preview text updates immediately as a rule changes and matches evaluator semantics.
  - Test Notification succeeds when authorized and reports a useful recovery state when
    denied.
  - Permission is requested only in response to enabling or testing notifications.
  - The Alerts pane remains keyboard-completable and understandable with VoiceOver.
  - Snapshot fixtures cover normal, pending, active, denied, stale, and unavailable
    states.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-015C — Add actionable system-state rules** `P1 / M`

  Outcome: Mectrics can alert on conditions that are more meaningful than percentage
  alone without removing percentage rules.

  Scope:

  - Add disk available-capacity rules expressed in localized bytes, such as less than
    20 GB, alongside the existing disk-used percentage rule.
  - Add battery service/health status only when the provider exposes a reliable
    system-reported condition; do not infer failure from cycle count alone.
  - Apply sustained-duration and recovery semantics appropriate to each signal.

  Acceptance:

  - Each new rule has a plain-language trigger, preview, active state, and recovery state.
  - Kernel memory pressure and thermal state were **removed** after review: both are
    power-user vocabulary that most people cannot act on, and each restated a rule that
    already exists in plainer terms (memory usage, CPU temperature).
  - Disk headroom uses the same capacity meaning shown in the Disk detail and declares
    any required-reason API use in `PrivacyInfo.xcprivacy`.
  - Battery health never reports a service condition without a supported provider value.
  - Deterministic tests cover activation, recovery, deduplication, cooldown, migration,
    and unavailable hardware.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-021 — Add a local Attention Log instead of more history charts** `P1 / L`

  Depends on: PX-015A. PX-015C may add additional event types later.

  Outcome: the user can answer “What needed attention?” from a short event history rather
  than interpreting continuous Battery or Disk charts.

  Scope:

  - Persist bounded event records for meaningful state transitions: rule pending,
    activated, recovered, notification delivered, thermal protection, and Energy Guard
    activation.
  - Store stable event type, metric, severity, start/end time, observed value/unit,
    trigger summary, destination result, and recovery result.
  - Deduplicate one continuous incident into a single record whose end time is updated on
    recovery.
  - Group the native list by day and lead with unresolved events.
  - Add metric and status filters only if the unfiltered list becomes difficult to scan.
  - Provide Clear Log and local export actions with confirmation and preview.
  - Exclude process names, IP addresses, Wi-Fi identifiers, serial numbers, and unrelated
    hardware identifiers.
  - Retain events for 30 days by default and bound storage independently of sample
    history.

  Acceptance:

  - A sustained threshold crossing creates one event and its recovery closes that event.
  - Relaunch, sleep/wake, clock changes, and duplicate samples do not duplicate incidents.
  - An empty log explains that Mectrics records only meaningful local events.
  - Clearing the log does not change alert rules or metric history.
  - Export preview exactly matches the file written.
  - VoiceOver reads metric, severity, start, duration/recovery, and trigger in a coherent
    order.
  - No Battery or Disk history chart is introduced.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-009A — Add an optional Compact Health menu bar item** `P1 / L`

  Depends on: PX-015A and PX-021.

  Outcome: one space-efficient item communicates whether the Mac needs attention and
  opens a calm prioritized overview.

  Scope:

  - Keep all current separate metric items available as an alternative.
  - Use a stable-width neutral icon in the normal state and a symbol plus accessible label
    for attention states; never rely on color alone.
  - Show “All systems normal” when no selected condition is active.
  - Rank active conditions by severity and recency, showing only the most important items
    before module details.
  - Let each condition open its metric detail or recovery action in one step.
  - Do not turn the popover into an equal-weight card dashboard.

  Acceptance:

  - Compact mode and separate-item mode can be switched without losing layout or rule
    settings.
  - The menu bar item does not change width as states update.
  - Normal, pending, warning, critical, stale, and unavailable fixtures are deterministic.
  - The default popover is useful without scrolling on the reference display.
  - Full Keyboard Access, VoiceOver, Increased Contrast, Differentiate Without Color, and
    Reduce Motion pass.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

## Energy and contextual usefulness

- [x] **PX-022 — Add Automatic Energy Guard** `P1 / M`

  Outcome: Mectrics automatically lowers its own monitoring cost when macOS signals that
  energy or thermal headroom is limited.

  Scope:

  - Observe AC/battery state, `ProcessInfo.isLowPowerModeEnabled`, system thermal state,
    sleep/wake, and whether heavy metric surfaces are visible.
  - Define three internal policies: Normal, Reduced, and Protected.
  - Slow or pause heavy Sensors and Bluetooth work first; keep low-cost status and enabled
    alert evaluation responsive.
  - Resume full sampling when the user opens the relevant detail, then return to the
    appropriate automatic policy.
  - Show one concise status in General and the Attention Log when Energy Guard materially
    changes behavior.
  - Offer one default-on “Adapt monitoring to power and thermal state” preference and a
    temporary full-sampling override only if testing shows a real need.
  - Prevent rapid state oscillation with explicit hysteresis or a minimum transition
    interval.

  Acceptance:

  - Deterministic tests cover AC, battery, Low Power Mode, serious/critical thermal state,
    sleep/wake, visible heavy detail, and recovery.
  - Existing sustained alerts remain wall-clock correct under reduced sampling.
  - No enabled low-cost alert silently stops without an explanatory state.
  - Activity Monitor/Instruments measurements demonstrate lower work in Reduced and
    Protected modes.
  - The status is understandable without adding a new always-visible menu bar item.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-023A — Add one validated app route model and metric detail window** `P1 / M`

  Outcome: widgets and app actions can open a specific trusted destination consistently.

  Scope:

  - Define a small allowlisted route enum for overview, metric detail, Alerts, Attention
    Log, About, What's New, and diagnostics.
  - Register one Mectrics URL scheme in `project.yml` and reject unknown hosts, paths,
    metric identifiers, and parameters.
  - Route external metric entry to a reusable compact detail window because an external
    source has no reliable menu bar anchor.
  - Reuse the existing metric-detail content and state/recovery language.
  - Integrate the detail window into activation-policy, display-clamping, reopen, and
    close-last-window behavior.

  Acceptance:

  - Every allowlisted route opens the expected existing or new surface.
  - Unknown and malformed routes perform no privileged or arbitrary action.
  - Cold launch and warm launch produce the same destination.
  - Repeated routes reuse the intended window rather than creating duplicates.
  - `Command-W`, `Command-Q`, focus restoration, and multi-display clamping behave like
    native Mac windows.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-023B — Add contextual actions to metric details** `P1 / S`

  Depends on: PX-023A.

  Outcome: metric details offer the most relevant next action without turning every
  popover into an action grid.

  Scope:

  - CPU and Memory: open the relevant Activity Monitor view.
  - Disk: open Storage Settings or Disk Utility as appropriate.
  - Battery: open Battery Settings.
  - Network: open Network Settings and offer Copy Local Address only when available.
  - Bluetooth: open Bluetooth Settings.
  - Sensors/GPU/Fans: expose only actions with a reliable native destination.
  - Reuse existing recovery actions and place no more than one primary and one secondary
    contextual action on a metric detail.
  - Launch system apps through documented `NSWorkspace` APIs and handle missing or changed
    destinations gracefully.

  Acceptance:

  - Every action opens the expected native destination on supported macOS versions.
  - Unavailable actions are omitted rather than disabled without explanation.
  - Copy actions expose only the visible value and produce localized confirmation.
  - Settings and Quit remain global actions and do not crowd every metric section.
  - Pointer, keyboard, and VoiceOver activation all work.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-024 — Add a privacy-safe Copy System Summary action** `P1 / S`

  Outcome: the user can copy a concise current-state summary for troubleshooting without
  exporting history or private identifiers.

  Scope:

  - Include app version/build, macOS version, Mac architecture/model family when safe,
    enabled metric states, current formatted readings, active attention conditions, and
    Energy Guard state.
  - Exclude usernames, hostnames, process names, serial numbers, MAC addresses, IP
    addresses, Wi-Fi/Bluetooth device names, file paths, and raw hardware identifiers.
  - Use one versioned plain-text schema with stable internal fields and labels localized
    through the String Catalog.
  - Add Copy System Summary to General and the most relevant overview/troubleshooting
    surface.

  Acceptance:

  - A fixture test verifies the exact allowlist and proves excluded fields never appear.
  - Missing metrics are represented by their state, never fabricated as zero.
  - Clipboard output is readable in plain-text applications and stable enough for support
    documentation.
  - Copying requires a direct user action and shows brief nonmodal confirmation.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

## Menu bar layout presets

- [x] **PX-012A — Add Reset to Recommended and three layout presets** `P1 / M`

  Outcome: users can reach a useful menu bar layout quickly without losing access to
  precise manual customization.

  Scope:

  - Add exactly three initial presets that vary along one axis — how much detail the
    user wants: Essentials, Recommended, and Detailed. Naming them for density rather
    than for hardware or profession keeps the user from having to place themselves on
    three different scales at once.
  - Define each preset as ordered module/component selections using the same model as the
    visual builder.
  - Make Reset to Recommended restore the current product default for the detected Mac.
  - Preview a preset before applying it.
  - Treat Apply as one undoable builder transaction.
  - Preserve unsupported modules as unavailable rather than introducing broken items.

  Acceptance:

  - Preset definitions have deterministic tests and never exceed stable-width templates.
  - Applying and undoing a preset restores the prior complete layout.
  - Reset to Recommended works on laptop, desktop, fanless, and unavailable-GPU fixtures.
  - Presets do not change alert, panel, appearance, or sampling preferences.
  - The builder remains fully keyboard accessible.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

## Updates, About, What's New, and diagnostics

- [ ] **PX-017A — Integrate secure Sparkle updates** `P0 / L`

  Outcome: direct-download users can check for and install authentic updates through a
  standard Mac update flow.

  Scope:

  - Add Sparkle 2 through Swift Package Manager in `project.yml`.
  - Use a stable HTTPS appcast, an EdDSA public key embedded in the app, monotonically
    increasing build numbers, and the same notarized artifact published to Releases.
  - Add Check for Updates to the application menu and update status to About.
  - Decide automatic-check defaults explicitly; do not make a network request before the
    documented user choice or product policy.
  - Keep the private EdDSA key in Keychain and out of the repository and CI logs.
  - Document rollback/recovery and failed-update behavior.

  Acceptance:

  - A signed older build updates to a signed newer build through a test appcast.
  - Tampered archive, invalid signature, unavailable feed, and no-update states are
    exercised.
  - The updated app and embedded widget pass code-signing, notarization, stapling, and
    Gatekeeper validation.
  - The appcast references the exact published artifact and correct version/build.
  - No private key or credential is committed.

  Completion evidence: required before closure.

- [x] **PX-017B — Add native About and skippable What's New surfaces** `P0 / M`

  Depends on: PX-017A for final update status.

  Outcome: version, privacy, license, update, and meaningful release changes are
  understandable inside the app.

  Scope:

  - Replace the generic About panel with a native Mectrics About window showing
    version/build, website, source/license, privacy, and update status.
  - Show What's New only once per meaningful version, never on every launch.
  - Keep What's New short, skippable, keyboard accessible, and available again from Help.
  - Do not use a splash screen or delay live monitoring.

  Acceptance:

  - About values come from the built bundle and match the release artifact.
  - What's New appears once after an applicable upgrade, never on clean relaunch, and can
    be reopened from Help.
  - Offline/update-error states remain useful.
  - Window lifecycle and the full appearance/accessibility matrix pass.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

- [x] **PX-017C — Add previewable local diagnostics export** `P1 / M`

  Depends on: PX-024.

  Outcome: users can inspect exactly what a support package contains before saving it.

  Scope:

  - Build diagnostics from the privacy-safe System Summary plus bounded application logs,
    provider availability/errors, alert configuration without delivery history content,
    widget registration facts, and recent Attention Log entries only when selected.
  - Present a native preview with individually selectable sections.
  - Exclude metric sample history by default and never include credentials, usernames,
    hostnames, serial numbers, IP/MAC addresses, process names, or unrelated file paths.
  - Save only after an explicit user action through a standard save panel.
  - Keep diagnostics local; Mectrics must not upload or automatically attach the file.

  Acceptance:

  - Preview and exported content are byte-for-byte equivalent after archive formatting.
  - Automated redaction tests cover every prohibited field.
  - The user can cancel without leaving a temporary export behind.
  - Widget-discovery diagnostics clearly distinguish embedded, signed, registered,
    gallery-visible, and snapshot-readable states.
  - The export is readable without proprietary tools and its schema/version is stated.

  Completion evidence: 2026-07-29 closure record in `06-experience-quality-gate.md`.

## Explicitly deferred or excluded

The following work is not part of this approved program:

- Continuous Battery or Disk history charts.
- A general-purpose 1-hour/24-hour/7-day/30-day chart dashboard.
- Per-process network and disk monitoring.
- Daily network totals.
- Weather, calendar, world clocks, public-IP lookup, ping services, or location access.
- Fan control or any other write access to SMC.
- Cloud accounts, telemetry, remote monitoring, or automatic diagnostics upload.
- Wi-Fi name collection, serial-number collection, or hardware fingerprinting.
- Additional layout presets beyond Essentials, Recommended, and Detailed without new
  evidence.

## Primary research references

- [Apple: Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Apple: Linking widgets to app scenes](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
- [Apple: App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Apple: Low Power Mode state](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)
- [Apple: Process thermal state](https://developer.apple.com/documentation/foundation/processinfo)
- [Apple: Notification settings](https://developer.apple.com/documentation/usernotifications/unnotificationsettings)
- [Apple: NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Sparkle 2 documentation](https://sparkle-project.org/documentation/)
- [Sparkle: Publishing an update](https://sparkle-project.org/documentation/publishing/)
- [Stats project and energy guidance](https://github.com/exelban/stats)
- [iStat Menus combined mode and rules](https://weather.bjango.com/mac/istatmenus/)
