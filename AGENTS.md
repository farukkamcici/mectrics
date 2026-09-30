# AGENTS.md — Working agreement for mectrics

This file is the **source of truth** for conventions in this repository. It applies to any
AI agent or human contributor. `CLAUDE.md` points here.

## 0. Golden rule: English-only repository

**Everything committed to this repo is in English** — no exceptions:

- Source code: identifiers, types, function names, variables.
- Comments and documentation comments.
- All Markdown docs (`README.md`, `docs/**`).
- Commit messages, branch names, PR titles/descriptions.
- User-facing UI strings: **English is the base/development language** (localized to other
  languages via the String Catalog — see §2).

The only place another language may appear is a live chat conversation with the user (who
may write in Turkish). Nothing from that chat leaks into the repo in another language.

## 1. Project shape

- `Packages/MetricsKit/` — UI-independent metric engine (SwiftPM). Providers, scheduler,
  ring-buffer store, engine. **No UI, no localization** (data-only, English identifiers).
  - `swift build`, `swift test`, `swift run metricskit-demo` (internal live provider
    readout).
  - `swift run mectrics` runs the read-only user CLI. It reads alert configuration from
    the app and offers `check`, `snapshot`, event streaming, and rule listing.
    `Tests/MectricsCLITests` owns its process, exit-code, JSON-fixture, and failure-path
    contracts.
  - Builds in the **Swift 6 language mode** and must stay warning-free. `MetricProvider`
    requires `Sendable`; providers are `@unchecked Sendable` because the engine samples
    them on one serial queue. Guard anything read outside that queue with a lock.
- `Mectrics/` — the menu bar app (SwiftUI + AppKit).
- `project.yml` — XcodeGen project definition. **This is the source**; `Mectrics.xcodeproj`
  is generated. After editing `project.yml` **or adding/removing source files**, run
  `xcodegen generate`.
- `docs/` — the architecture deep dive, and nothing else. Contributor-facing only: planning
  notes, roadmaps, backlogs, and maintainer-only runbooks do not belong in the public
  repository. The release procedure lives in `scripts/release.sh`, which is self-documenting
  through its required environment variables.

Do **not** commit: `Mectrics.xcodeproj/`, `DerivedData/`, `.build/`, or
`Packages/MetricsKit/Package.resolved` (see `.gitignore`). That last one is not an
oversight: `xcodebuild` on the app writes the app's whole package graph into it — Sparkle
included, though MetricsKit does not depend on Sparkle — and `swift build` in the package
takes it out again, so whatever is committed is dirty after the next build either way.
SwiftPM versions also disagree on its `originHash`. The package's one dependency is
pinned to an exact version in `Package.swift`, so nothing rests on the file.

## 2. Internationalization (i18n)

- All user-facing strings go through `String(localized:)` or SwiftUI `Text`/`Label`.
- Never hardcode user-facing prose as a plain `String` without localization.
- App strings live in `Mectrics/Resources/Localizable.xcstrings`; widget strings live in
  `MectricsWidget/Localizable.xcstrings`. Both catalogs ship English, Turkish, Russian,
  Spanish, French, Brazilian Portuguese, and Simplified Chinese.
- The General Settings language picker is backed by `AppLanguage`. Adding a language means
  adding its case and identifier there, then translating every entry in both catalogs.
- Module display names: use `MetricID.localizedName` (app layer), not the package's
  `displayName` (which is the English fallback).
- Numeric/symbolic menu-bar strings (percentages, rates, arrows) are not localized.

## 3. Menu bar rendering rules

- **Item width must be stable.** Each module reserves a fixed text width from a worst-case
  template (`MetricStatusItem.template(for:)`) and right-aligns text inside it. Item width
  must never depend on the current value's digit count — this prevents items from shifting.
- Use `NSFont.monospacedDigitSystemFont` so digits are equal width.
- If you add a module or change a format, update its template so real values never exceed
  the reserved width.
- **A module may contribute several items.** Components are independent toggles
  (`AppModel.toggleComponent(_:for:)`), so Battery can show icon + health at once.
- **Every component includes a readable value.** A chart-only item is not offered:
  a sparkline with no number cannot be read at a glance.
- **Absence is not zero.** When a reading is missing, render a dash and never fabricate
  `0%` / `0`. Do not offer a component whose data this Mac cannot report.
- Components are picked by clicking a live preview chip, not from a select box — the
  user chooses what they can see.
- **Placement is per module, not one style for the whole menu bar.** Each module takes
  its own items (`enabledComponents`), or a card in the Dashboard
  (`groupedModules`), or neither — `MenuBarPlacement`. Someone who wants CPU in view every
  second and Disk only when asked can have exactly that, which a single global mode could
  not express. The two sets stay the source of truth rather than a third stored placement
  that could disagree with them, and the persisted raw values never change.
- **An upgrade may not rearrange a menu bar its owner arranged.** Every version before
  1.9 had no Dashboard, so a Mac arriving from one has never been asked which readings
  belong in it: nothing moves into cards, and its icon appears only where the Compact
  Health item it replaces already stood — the one slot where a new icon is not a change
  nobody asked for. A stored `enabledComponents`, or the legacy `enabledModules`, is what
  says a Mac already has a menu bar (`firstRunGroupedModules`,
  `firstRunDashboardItemEnabled`). Someone who never had that item gets no new icon and
  hears about the Dashboard from What's New, which is what What's New is for. **Check this
  against a real upgraded preference domain before a release, not only in tests**: the
  first attempt passed every test and still gave every existing install an icon nobody
  asked for.
- **A clean install starts with one icon.** `MenuBarPlacement.defaultGroupedModules` is
  CPU and memory, as cards; no module takes an item of its own until it is asked for. The
  menu bar is the scarce surface, and a first run that fills it with readings nobody
  picked spends it before the user has said anything.
- **The Dashboard can be switched off, but only once it is empty.** With cards inside
  there is nothing to decide — they would have nowhere to be shown — so its row states its
  place as text and the pop-up appears when the last card leaves. Empty it first, then
  turn it off. It is not locked in place: emptying the menu bar completely is recoverable,
  because launching Mectrics again opens Settings
  (`applicationShouldHandleReopen`), and locking the icon would spend the scarce surface
  on someone who only wants CPU there. The preview strip says how to come back, because a
  blank menu bar that is recoverable only if you know how is not recoverable. Do not
  justify this item with the health badge: every alert rule ships disabled, so on a clean
  install it never fires until a rule is configured.
- **The Dashboard is a row in the modules list, not a switch elsewhere.** It is one
  of the things the menu bar holds, so it reads like the modules beside it: a name, its
  place, and its contents underneath — the readings grouped into it, added and removed
  from that row. Placement is a pop-up and never a segmented control: three segments
  repeated down a list of modules read as a wall, and only one of them is ever the answer.
  The grouped placement is named for **where a module goes** ("Dashboard"), never for what
  happens to it ("Grouped"), which left the obvious question unanswered on screen.
- **The last look on stays on.** Clearing a module's only component used to drop it to
  `.off`, so the row collapsed under the pointer and the chips being edited vanished with
  it. One control, one decision: the chips choose which looks, the pop-up beside them
  takes the module out. The sole remaining chip is disabled and says why rather than
  swallowing the click.
- **No presets.** They were removed: a ready-made layout answers "how much detail" while
  the pane now asks "where does each module go", and a control that replaces every answer
  at once is a poor fit for a list you read row by row. Do not reintroduce them without an
  explicit decision.
- **Four placements, all derived from the two stores.** `enabledComponents` decides items
  and `groupedModules` decides cards, and the pair gives `.ownItems`, `.grouped`, `.both`
  and `.off` without a third value that could disagree with them. That derivation is why
  **asking for the Dashboard alone clears a module's components**: kept "for later" they
  would make `.grouped` and `.both` identical here. It is also honest — choosing the
  Dashboard alone says this module should take no menu bar items — and `.both` is there
  for anyone who wants to keep them.
- `enabledModules` and `setEnabled(_:for:)` mean the *watched* set
  (`MenuBarPlacement.watchedModules`) — every module placed anywhere. Sampling, widgets,
  summaries, onboarding, and recovery actions go through them, never through
  `enabledComponents` directly.
- **The Dashboard is fixed-width, and it is also the health item.**
  `MectricsStatusItem` has a fixed, even length, so its even-sided image sits on whole
  pixels at 1x. A badge **never changes that size**: a mark that grew when something went
  wrong would move every item after it. The accessibility label is assigned once; the
  image, value, and tooltip change only on a severity transition or a theme change, and an
  update repeating what is already shown is dropped before it reaches AppKit.
- **Health is a shape, not a colour, and only the badge is tinted.** The badge is the same
  symbol the Attention Log uses, punched out of the M so the two read as two marks. Two
  rules follow, both learned the hard way. **Never paint the whole mark** the severity
  colour: a template M is drawn near-white on a dark menu bar, so an orange one reads as a
  logo going out at the moment it has something to say. And a badged mark is drawn for
  **one appearance**, so the appearance belongs in its cache key and in the item's render
  inputs, and *every* colour it uses — the tint included, because `secondaryLabelColor` is
  one — is resolved inside `appearance.performAsCurrentDrawingAppearance`.

## 4. Surfaces and Settings

- **The menu bar is the only live surface.** The always-on-top floating panel and its
  global hotkey were removed; the supported overview lives in the menu bar — the Mectrics
  item's dashboard. It is a transient popover in the shared `NSPopover`, on screen only
  from a click until the next click elsewhere. Do not reintroduce a second always-visible
  rendering surface.
- **A condition that stops being watched must be announced, not just forgotten.** A rule
  switched off, or a signal whose reading goes away, ends its condition — and every surface
  showing it learns that only from an `onConditionUpdate`. A monitor that resets its own
  state without emitting leaves the condition on the menu bar, in the dashboard's banner,
  and as an Attention Log event that never closes. The transition is `.recovered`: to every
  consumer it means this condition is no longer active, which is exactly what happened.
- **One health indicator, and it is the Dashboard.** The separate Compact Health item
  is gone. It read the same `healthConditions` and showed the same worst condition as the
  dashboard's banner, so it was two icons answering one question — the duplication that
  retired the floating panel. The state now rides on the Dashboard as a badge, and the
  switch that used to add that item is gone with it: the Dashboard is always there.
- **Removing is on the surface; adding is in Settings.** The dashboard can take its own
  cards off, because that is the common errand and the card is right there. It never
  offers the modules it is *not* showing — a popover that did would become the pane it
  links to, and the pane is where a module's cost is stated. This is the one deliberate
  exception to "Settings holds configuration": it edits a set the surface already shows.
  The Mac's own card is a card like any other here: it can be taken off and put back the
  same way, and it has a row in the modules list beside the readings — a list that showed
  every card except one would leave that one adjustable only from inside the popover it
  appears in. Its placement offers Dashboard and Off, never the menu bar: a version string
  and an uptime are not a reading that changes, and an item that never moves is a slot
  spent on nothing. Its name lives in `DeviceCardName`, read by both the card and the row,
  because two copies of a name drift — they had already drifted to "Device" and
  "System info". One corner, one affordance — the remove control owns the top-trailing corner,
  so a hovered card shows its "opens details" chevron at the bottom instead.
  The control is a **real button revealed on hover, plus a context menu**, never a drawn
  badge over the card's own button: an overlay swallows the clicks aimed at it, which is
  what made the first attempt almost unclickable. And there is no edit *mode* — a mode to
  enter before a one-click errand is worse than the errand.
- The bundled CLI is a headless **automation interface**, not a second live dashboard. It
  reuses the app's saved rules, offers event streaming and one-shot checks, and keeps
  standard output pipe-safe. `check` and alert streaming sample only the metrics they need;
  `snapshot` samples every available module once. It is read-only; alert configuration
  remains in the app.
- Every Settings pane is reachable by a `mectrics://` route (`overview`, `menu-bar`,
  `alerts`), so a destination the app can show is a destination it can be sent to.
- **The Dock icon belongs to `DockPresence`, not to a window scan.** The app launches as
  `.accessory` and becomes `.regular` only while one of its own standard windows is on
  screen; every window controller reports opening and closing to that one object. Never
  decide this from `NSApplication.windows` — it also contains the window behind every
  status item, so "is any window visible" is true for the app's whole life and the icon
  never goes away.
- **Release notes belong to the version that shipped them.** `ReleaseHighlights` is keyed
  by marketing version and What's New shows the running build's entry; a version with no
  entry shows no window rather than someone else's news. Shipping a version means adding
  its notes — `ReleaseExperienceTests` fails if the current version has none.
- **A patch release never stands alone.** It returns the minor release's notes followed by
  its own, so 1.6.1 reads as what 1.6 brought plus what changed since, and someone who
  skipped 1.6.0 still learns what it added. A fix is never presented as if it were the
  whole release.
- Keep `check` exit codes stable: `0` healthy, `1` limit crossed, `2` unconfigured or
  indeterminate. Usage, internal software, and corrupt-configuration failures are `64`, `70`,
  and `78` respectively. Valid version 1 JSON fields do not change without an explicit schema
  migration and fixture update.
- A watch must never evaluate a failed or stale cached sample. Default JSON remains alert and
  recovery events only; opt-in heartbeat mode uses tagged `ready`, `heartbeat`, `alert`, and
  `status` records that expose sampling coverage and freshness. Watch rules are frozen at
  startup and the process must be restarted after an app-side rule change.
- The optional CLI installation is a symbolic link at `/usr/local/bin/mectrics` pointing
  into the signed app bundle. Never download or copy a second binary, overwrite an unrelated
  command at that path, or install a daemon. App removal also removes a Mectrics-owned link.
- **Settings holds configuration, not routine actions.** Quit, copy, and export belong to
  the surfaces that own them (popover, Diagnostics, Attention Log), not to a preferences
  pane. The destructive, one-time app removal action is the sole exception because no
  other surface owns the app lifecycle.
- Every Settings pane uses `Form(.grouped)` and shares one window size — switching tabs
  moves the selection, never the window.
- Prefer progressive disclosure over dimmed controls: hide a control that cannot act yet
  and show its current value as text instead.

## 5. Performance & privacy invariants

- **Zero telemetry.** The only network calls allowed are update checks. No usage or
  hardware data ever leaves the device.
- **The app never reaches the network without being asked first.** Automatic update checks
  are off in Info.plist and turned on only by an explicit answer, given in onboarding or
  once on a later quiet launch, and changeable in Settings. `SUEnableSystemProfiling` stays
  false and updates are never downloaded or installed unattended, so consent changes *when*
  the appcast is fetched and never *what* the request carries. `README.md` and `PRIVACY.md`
  state this; changing the behaviour means changing both.
- **Nothing modal on the launch path.** The XCTest host launches the real app, so a blocking
  alert during startup hangs the whole suite instead of failing it. Anything that could
  present one asks `UpdatePermissionPolicy.isRunningTests` first.
- Adaptive sampling: faster on AC, slower on battery; pause work that isn't visible —
  a sleeping display, a locked screen, and a switched-away session all count as invisible.
- Keep the hot path allocation-free (the ring buffer is pre-allocated).
- Targets: < 60 MB memory, low/steady CPU, "Energy Impact: Low" in Activity Monitor.
- Memory is reported in the decimal megabytes Activity Monitor uses (10⁶ bytes), which is
  what `summarize.sh` divides by. A figure computed in MiB is about 5% smaller and is not
  comparable with anything else quoted here.
- **Memory is measured as `phys_footprint`, never as `ps rss`.** Run
  `footprint -p $(pgrep -x Mectrics)` on a **Release** build and quote its
  `phys_footprint`. That is the figure Activity Monitor's "Memory" column shows and the
  one the budget above refers to. `ps rss` counts shared framework pages that every
  SwiftUI app maps and no app pays for individually; on this app it reads roughly three
  times higher and makes Mectrics look far heavier than it is. Quoting RSS in a README,
  an issue, or a launch thread understates the product against its own budget.
- `cost` decides how often a provider runs: `.light` every base cycle, `.medium`
  (battery, disk) and `.heavy` (SMC/GPU/sensors) thinned by `SamplingRuntimePolicy`.
- Performance baselines use a Release app with no debugger, coverage, or sanitizer. Run
  `scripts/performance/measure.sh` for whole-process gates and
  `scripts/performance/measure-cli.sh` for the embedded CLI. Raw, machine-local results
  stay under ignored `build/performance/`; never commit hardware identifiers or traces.
- Treat Instruments and optional `powermetrics` capture as diagnostic tools after a clean
  baseline fails. Their observer cost does not belong in the baseline number.
- Release memory means the post-warm-up `phys_footprint` p95. The 60 MB budget is a gate,
  not a one-off screenshot. Long runs also gate sustained growth. The budget describes the
  menu bar's steady state; an open Settings window adds most of a SwiftUI window's working
  set on top and measures above it, which is a fact about the surface, not a leak.
- Public performance claims name the Release version, workload, warm-up, measured duration,
  and power state. Report CPU median and p95 together, and say whether the memory-slope gate
  ran. Never generalize a short smoke run into a soak result or a guarantee for every Mac.
- Performance launchers use process-only preference overrides, suppress saved-window
  restoration, and restore the exact preferences snapshot after the process exits. A run
  must leave the contributor's real Mectrics preferences unchanged. A domain that did not
  exist before a run must not exist after it, and the removal is retried because cfprefsd
  can flush a departing process's writes after it has gone.
- A gate covers **two** workloads, because they fail differently: the menu bar alone, and
  Settings deliberately open. Both use `scripts/performance/profiles/`, so the rules and
  the layout under measurement are declared rather than remembered.
- **Never hand AppKit a menu bar image that has not changed.** Assigning `button.image`
  invalidates the status item and round trips to the window server; it costs far more
  than drawing the image did. Status items compare their render inputs first. Per-cycle
  item work must also stay free of string-catalog lookups: an accessibility label that
  names the module and the look never changes, so it is set once at construction.
- **The menu bar is rebuilt only when its list of items changes.** `onModulesChanged`
  tears down and re-creates every `NSStatusItem`, which means new windows and new
  structural regions in the window server. Component availability therefore only grows
  within a session: a sensor that reads out of range for one cycle is a failed read, not
  hardware that vanished, and the item already renders a dash for a missing value. The
  Dashboard is **one entry in that list however many cards it holds**, so grouping or
  ungrouping a module calls `onWatchedModulesChanged` — republish widgets, update Energy
  Guard — and not `onModulesChanged`. Only the first card and the last one change the
  list, because they create and remove the item itself.
- **Every visibility report is balanced and batched.** A popover reports its modules
  visible as one set and hidden as the same set (`onDetailVisibilityChanged`,
  `AppModel.setVisibleDetailModules`), so opening the dashboard is one forced refresh, not
  one per card. Every way a popover ends — toggled, replaced, dismissed by AppKit, or
  orphaned by a rebuild, which closes it first — reports hidden exactly once. Popover and
  detail-window visibility are tracked apart, because both can show the same module.
- **A closed popover releases its content.** Its window is only ordered out, so a view
  tree kept in it would go on observing the model and running `.task` loops off screen.
  Every opening installs fresh content.
- **Rebuild on the item list, never on the settings behind it.** `onModulesChanged` is for
  a change in *which* status items exist. Editing a grouped module's components changes
  none, so comparing the raw preferences instead of the resolved item list rebuilt the menu
  bar — and destroyed the open dashboard — every time a card was taken off.
- **Follow the sampling cycle only if the value can change that often.** Reading `latest`
  ties a view to every cycle, which is right for a reading and wrong for anything coarser:
  the dashboard's uptime reads in minutes, so it is driven by a one-minute `TimelineView`
  rather than re-evaluated sixty times for every time it has news. The health badge is the
  same rule at the other end — it changes on a severity transition, not on a cycle.
- **A Settings pane's own body must never read a value that changes every cycle.**
  Live readings belong to small leaf views (`MenuBarComponentPreview`, `AlertRuleLiveLine`,
  `AlertRuleSummary`), and those leaves reserve a fixed width from the same template the
  real menu bar item uses. A pane rebuilt once a second rebuilds every tooltip and hover
  region with it, and AppKit answers a tracking-area change by re-resolving the pointer —
  cost that grows the longer the window stays open. This is why `AppModel` caches what a
  view needs but a sample does not change (`componentOptions`,
  `availableSystemAlertSignals`).
- **Reading the SMC is the most expensive thing this app does**, so it is sampled only
  where a temperature is actually on screen: a `.temperature` menu bar component or the
  menu bar builder (separate items only), an open popover, dashboard, or detail window for
  CPU/Memory/GPU, or a rule that asks for `.sensors` directly. A module merely having a
  menu bar item or a dashboard card does not earn it.
- Prefer `IORegistryEntryCreateCFProperty` over `IORegistryEntryCreateCFProperties`:
  copying a driver's whole property dictionary to read one key is orders of magnitude
  more expensive.

## 6. Adding a metric provider

1. Add a `MetricProvider` in `Packages/MetricsKit/Sources/MetricsKit/Providers/`.
2. Return `isAvailable = false` when the hardware/permission is absent (module auto-hides).
3. Add it to `MetricsKit.coreProviders()`.
4. Add menu-bar text in `MenuBarText` (+ a stable template in `MetricStatusItem`).
5. Add popover rows in `DetailPopoverView` (localized labels), the primary value in
   `DashboardFormat.primaryValue(for:sample:)` (shared by the detail and the dashboard),
   and a dashboard card in `DashboardPopoverView`.
6. Add a sanity test in `MetricsKitTests`.

## 7. Build / test / run

```bash
# Core engine (no Xcode)
cd Packages/MetricsKit && swift test && swift run metricskit-demo

# App
xcodegen generate
xcodebuild -project Mectrics.xcodeproj -scheme Mectrics -configuration Debug build
```

## 8. Commits

- English, imperative-ish subject; concise body explaining the *why*.
- **Never add Claude (or any AI agent) as a commit contributor/author.** Do not add
  `Co-Authored-By:` trailers, `Generated with` lines, or any AI attribution. Commits are
  authored solely by the human contributor.
- Commit or push only when the user asks. Branch before committing on `main` if unsure.

Private signed candidates use `scripts/release-candidate.sh`. It writes to the versioned
`build/candidate/` tree, signs, notarizes, and staples the DMG, but never edits the appcast,
creates a tag, or publishes a GitHub release. `scripts/release.sh` remains the publishing
preparation path.

## 9. Product decisions (fixed)

- Distribution: **Direct / DMG** (Developer ID + notarization).
- Minimum macOS: **15 (Sequoia)**.
- License/model: **free & open source** (no Free/Pro split, no licensing code).
- Repository: **public** since 2026-07-29 (`github.com/farukkamcici/mectrics`). Assume
  anything committed is publicly readable; never commit keys, notary credentials, or
  personal identifiers. Specifically:
  - **No Apple Developer Team ID in the repo.** `project.yml` fills `DEVELOPMENT_TEAM` from
    the `MECTRICS_TEAM_ID` environment variable at generation time; unset means unsigned.
  - **No email addresses.** Contact runs through GitHub (private security advisories, issue
    templates), not a mailbox in a Markdown file.
  - **No personal circumstances in docs.** Write for a contributor who just arrived, not
    for the maintainer. `SUPublicEDKey` in `project.yml` is a *public* key and belongs
    there — the private half never leaves the signing machine's Keychain.
- Decisions that were tried and reversed — the floating panel and its global hotkey, the
  30-day archive and CSV export — stay reversed. Do not reintroduce them without an
  explicit decision from the user.
- Memory-pressure and thermal-state alert rules were removed in `9af7262` as power-user
  vocabulary that restated the memory and temperature rules, then **reinstated by the
  user** after launch feedback. They are back because the original reasoning was wrong on
  the facts: a hot sensor is not a throttled machine, and a full memory bar is not a
  machine under pressure. What stays true from that removal is the objection to the
  wording, so these rules are named for what a person notices — how much the Mac has been
  slowed — not for Apple's `nominal`/`fair`/`serious`/`critical` scale. Critical severity
  is now reachable from three signals, not only a battery needing service.

## 10. Public-facing files

The repository is public and is presented as an open source project. Keep these in sync
with reality — a stale claim in `README.md` is a bug:

- `README.md` — **written for someone deciding whether to run the app**, not for someone
  about to work on it. What it does, what it shows, how to get it, what it promises about
  privacy. Build commands, engine internals, and conventions belong in `CONTRIBUTING.md`
  and `docs/architecture.md`; do not migrate them back into the README.
  It opens on the product film as a bare `user-attachments` link, which GitHub renders as
  an inline player. That is the only way a README plays video: GitHub strips `<video>`, and
  a video committed to the repository never renders as a player. To replace the film,
  upload the new cut in the web editor (10 MB limit) and swap the link.
- `CONTRIBUTING.md` — setup, code signing, the development loop, provider and translation
  recipes. It restates the rules; **this file remains the source of truth**, so change
  rules here first.
- `docs/architecture.md` — the technical deep dive: app/engine split, technology rationale,
  the metric source map, rendering rules, performance strategy, repository layout.
- `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` (private reporting via
  GitHub Security Advisories), `CHANGELOG.md` (Keep a Changelog format).
- `.github/` — issue forms, pull request template, Dependabot, and CI.
- `docs/README.md` — index of the docs folder.

CI (`.github/workflows/ci.yml`) runs three jobs on every push and pull request: SwiftPM
build and tests for MetricsKit, an unsigned `xcodebuild` of the app, and repository hygiene
(no generated output committed, no broken relative Markdown links). Adding a file that
breaks a documented link fails the build.

Docs record intent at the time of writing. Where a doc and the code disagree, the code
wins and the doc gets corrected.

## 11. Extending these rules

When the user establishes a new convention, add it here (and reflect it in `CLAUDE.md` if
Claude-specific). Keep this file the single source of truth.
