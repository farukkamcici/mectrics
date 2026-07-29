# 06 — Experience Quality Gate

This document records the shared presentation language and the manual release matrix for
the premium foundation. It complements the implementation plan in
`05-premium-experience-backlog.md`.

## Design tokens

`Mectrics/UI/ExperienceDesignSystem.swift` is the source of truth for app-surface
spacing, radii, type roles, chart strokes and fills, low-emphasis surfaces, semantic
status treatments, and brief state-change motion. Native controls retain their platform
metrics; tokens apply to composition around those controls.

The reusable presentation components are:

- `ExperienceSectionHeader`
- `MetricValueText`
- `MetricStatusBadge`
- `MetricEmptyState`
- `InlineNotice`

Semantic status always combines text or a distinct symbol with color. Reduce Motion
removes app-authored spatial transitions, Reduce Transparency replaces panel material
with the window background, and Increased Contrast strengthens boundaries.

## State language

| State | Meaning | Value behavior | Recovery |
| --- | --- | --- | --- |
| Collecting | No valid reading has arrived yet | Show an em dash, never zero | Refresh |
| Live | A fresh valid reading is updating | Show the current value | None |
| Unavailable | The Mac has no matching hardware or capability | Show an em dash | None |
| Disabled | The user is not monitoring the metric | Show an em dash | Enable in context |
| Permission required | macOS access is needed | Preserve a prior value if present | Open System Settings |
| Last known | The latest valid reading is older than expected | Preserve and mark the value | Refresh |
| Needs attention | Three consecutive attempts failed | Preserve and mark the last valid value | Refresh |

`MetricDataState.resolve` owns precedence. The app publishes the resolved state with
WidgetKit snapshots so the menu bar, popover, widget, and Menu Bar
Settings preview use the same result.

## Terminology and formatting

| Metric | Primary meaning | Menu bar | Detail and panel | Supporting context |
| --- | --- | --- | --- | --- |
| CPU | Total processor use | Whole percent | One decimal percent | System/user/idle, load average, core use, hottest CPU temperature |
| Memory | Physical memory in use | Whole percent or compact used bytes | One decimal percent | Used, wired, compressed, free, swap, pressure |
| Battery | Remaining charge | Whole percent, charge symbol, health, or cycles | Whole percent | Charge state, time estimate, health, cycles, temperature |
| Network | Current transfer rate | Down/up with compact K/M/G rate | Bytes per second | Download, upload, session totals, local address |
| Disk | Startup-volume capacity in use | Whole percent, ring, used, or free | One decimal percent | Used, purgeable, free, total, read, write |
| GPU | Graphics processor use | Whole percent | One decimal percent | GPU count, in-use memory, hottest GPU temperature |
| Sensors | Hottest available temperature | Whole degrees | One decimal Celsius | Hottest CPU/GPU reading and sensor count |
| Fans | Fastest available fan | Compact RPM | Whole or compact RPM | Fan count and per-fan RPM |
| Bluetooth | Lowest reported connected-device battery | Whole percent | Whole percent | Connected device count and device battery levels |

Rules:

- User-facing module names come from `MetricID.localizedName`.
- Percentages are whole numbers in compact surfaces and use one decimal only where the
  extra precision aids comparison.
- Storage uses localized byte formatting; rates state a time basis.
- Menu-bar rate strings stay within the fixed-width formatter contract.
- Temperature uses Celsius until a user-selectable unit preference exists.
- Prose uses sentence case and avoids engine terms such as provider, fraction, or
  snapshot.
- Every user-facing string is emitted into an app or widget String Catalog.

## Manual appearance and interaction matrix

Run the matrix on the release candidate and record the result in the release notes.
“All surfaces” means onboarding, General, Menu Bar, Alerts, each available detail
popover, the Compact Health item, the Attention Log, About, and every supported widget
family.

| Check | Light | Dark | Increased Contrast |
| --- | --- | --- | --- |
| All surfaces are readable and preserve hierarchy | Required | Required | Required |
| State is understandable without color | Required | Required | Required |
| Keyboard focus is visible and traversal has no trap | Required | Required | Required |
| VoiceOver label, value, hint, grouping, and order | Required | Required | Required |
| Reduce Transparency panel fallback | Required | Required | Required |
| Reduce Motion onboarding, disclosure, popover, and window paths | Required | Required | Required |

Lifecycle checks:

- `Command-,`, `Command-W`, `Command-Q`, and Escape
- close-last-window Dock transition and menu-bar continuity
- Finder/Dock reopen and Help → Show Welcome
- selected Settings pane and frame restore after relaunch
- display removal clamping, Space changes, and sleep/wake

## Hardware compatibility matrix

Every provider reads a documented or long-stable system interface, but only the Apple
Silicon column has been exercised on real hardware. Record any new machine here as it is
tested, and state the machine in the release notes.

| Module | Interface | Apple Silicon | Intel | Notes |
| --- | --- | --- | --- | --- |
| CPU | `host_processor_info` | Verified | Expected | Architecture-independent Mach call |
| Memory | `host_statistics64` + `vm_stat` fields | Verified | Expected | Architecture-independent |
| Battery | IOKit `IOPowerSources` + `AppleSmartBattery` | Verified | Expected | Desktops report unavailable |
| Network | `sysctl(NET_RT_IFLIST2)`, `getifaddrs` fallback | Verified | Expected | 64-bit counters; loopback excluded by `IFF_LOOPBACK` |
| Disk | `URLResourceValues` + IOKit block-storage statistics | Verified | Expected | Startup volume only |
| GPU | IOAccelerator `PerformanceStatistics` | Verified | Untested | Intel/AMD publish the same dictionary under different accelerator classes |
| Sensors | SMC key enumeration (`T…`, 1–125 °C filter) | Verified (116 keys) | Untested | Intel CPU keys start with `TC`, which the CPU classifier already accepts |
| Fans | SMC `FNum`/`F…Ac`/`F…Mx` | Verified (fanless: hidden) | Untested | Needs a fan-equipped machine to confirm RPM values |
| Bluetooth | IORegistry `BatteryPercent` / per-component keys | Verified | Expected | Device-dependent, not architecture-dependent |

Legend: **Verified** — observed on the reference Mac. **Expected** — the interface is
architecture-independent and no chip-specific code path exists. **Untested** — the code
handles the case, but no machine has confirmed it.

Reference Mac: Apple Silicon MacBook Air, 8 GB, fanless, macOS 27, Xcode 26.6.
Open hardware gaps: an Intel Mac (GPU, Sensors, Fans) and any fan-equipped Mac.
A machine that reports no usable keys degrades to the module being hidden rather than
showing a fabricated value, so an untested machine cannot display wrong data.

## Foundation verification record

The 2026-07-28 premium-foundation pass produced the following evidence:

- The app and widget built successfully in Debug, and all 21 MetricsKit tests passed.
- A clean-install engine test delivered the first live metric in less than two seconds.
- Onboarding was completed and skipped using only the keyboard. Help → Show Welcome
  reopened it with live CPU, memory, battery, and network readings.
- General, Menu Bar, Alerts, onboarding, detail, and floating-panel surfaces were
  inspected in Light and Dark appearances on the available display.
- Accessibility Inspector reported no high-priority issues in Settings or onboarding.
- `Command-,`, `Command-W`, `Command-Q`, Escape, pane restoration, window-title changes,
  Dock-policy transitions, and live Settings previews were exercised.
- Resolved data states are covered by deterministic tests and are included in shared
  widget snapshots. Legacy snapshots remain decodable.
- Both String Catalogs synchronize without stale entries, and every metric is covered by
  the terminology and formatting table above.

The appearance, accessibility, and lifecycle checks that were open in that record were
completed later; see the closure record below.

## Approved feature program verification record

The 2026-07-28 local implementation pass produced the following additional evidence:

- All 23 MetricsKit tests and all 44 app tests passed with stable Xcode 26.6.
- Deterministic tests cover alert migration and delivery state, native system-condition
  alerts, Attention Log retention/deduplication/export, Compact Health resolution and
  stable width, Energy Guard policies, allowlisted routing/actions, System Summary
  privacy, diagnostics redaction and byte-equivalent preview/export, layout presets, and
  the What's New policy.
- A universal Release archive completed with Hardened Runtime. Its app, embedded widget,
  and Sparkle framework pass deep strict code-signature validation.
- The archived app and widget contain the same App Group. The widget also contains App
  Sandbox, and both privacy manifests are present and valid.
- The user placed Small and Medium Mectrics widgets from the native gallery. The supplied
  screenshot shows correct family sizing but an empty “Waiting for Mectrics” timeline.
  The private Debug fallback was removed, signed App Group snapshot writes now succeed,
  and the shared snapshot is readable. The remaining widget lifecycle checks were
  completed in the 2026-07-29 closure record below.
- Sparkle 2.9.4 is pinned in `project.yml`, the public EdDSA key is embedded, the private
  key is stored in Keychain, and automatic checks are disabled. The configured HTTPS
  appcast remains unavailable until the repository and release feed are published.
- The signed Release app was installed in `/Applications`; its launch-once and visual
  checks were completed in the 2026-07-29 closure record below.

## Engine hardening verification record

The 2026-07-29 engineering pass closed the remaining non-release items in the
"Existing functionality and engineering tasks" list of `05-premium-experience-backlog.md`:

- `NetworkProvider` now reads 64-bit counters from `sysctl(NET_RT_IFLIST2)` and keeps
  `getifaddrs` as a fallback. Loopback is excluded by `IFF_LOOPBACK` rather than by name,
  and a decreasing total reports a zero rate instead of a wrap-around spike. Deterministic
  tests cover the first pass, a normal interval, a counter reset, and the resumed baseline.
- `BluetoothProvider` resolves names through the known product keys, then the registry
  entry name, ignoring registry class names; duplicate registry nodes and out-of-range
  levels are dropped, and an empty scan clears the name channel so the app's numbered
  fallback label can never inherit a previous device's name.
- MetricsKit builds warning-free in the **Swift 6 language mode** (no per-target
  `swiftLanguageMode(.v5)`), and `MetricProvider` requires `Sendable`.
- The hardware compatibility matrix above documents what each provider reads and what has
  actually been observed. Intel validation remains open because no Intel Mac is available.
- Evidence: 26 MetricsKit tests and 46 app tests passed, the Debug app and widget built
  successfully, and `mectrics-cli` showed live CPU, memory, battery, network, and disk
  readings from the new counter path.

## 2026-07-29 closure record

The owner ran the manual appearance, accessibility, and lifecycle matrix above on the
reference Mac against the installed build and reported every surface — menu bar items,
detail popovers, the Compact Health item, onboarding, General/Menu Bar/Alerts, the
Attention Log, About, What's New, diagnostics, and the widget families — as correct.
The repository was made public the same day.

On that evidence, and with the automated results recorded above, these tasks are closed:

- `05-premium-experience-backlog.md`: PX-001 through PX-009, PX-011, PX-012, PX-014,
  PX-015, PX-016, PX-019 (the last two at their revised scope), and PX-021 through
  PX-024.
- `07-approved-feature-program.md`: every child task except PX-017A.

Still open, with the reason each needs something this pass could not supply:

| Task | Blocked on |
| --- | --- |
| PX-017A | A published appcast and GitHub Release; the feed URL currently 404s, so no upgrade has been installed through Sparkle |
| PX-018 | Release-build measurements. The Debug build's `phys_footprint` sits at 94–97 MB, stable over five minutes (no leak), but the 60 MB budget is defined against a Release build |
| PX-020 | Gatekeeper validation of the notarized DMG on a clean Mac account, which needs the published artifact |
| Intel validation | An Intel Mac, and any fan-equipped Mac for the Fans module |
| Minimum-OS validation | A macOS 15 or 16 machine. Everything so far was verified on macOS 27, and the deployment target is macOS 15 |

Everything above is a record of what was actually observed. Nothing is closed on
inference: a check that has not been run stays in the open table until it is. PX checkboxes remain open
until the manual appearance/accessibility matrix, performance measurements, complete
widget lifecycle matrix, signed appcast upgrade/failure tests, clean-account testing,
Developer ID export, notarization, stapling, and Gatekeeper checks all pass.
