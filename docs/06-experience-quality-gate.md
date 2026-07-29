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
| Clock | Current local time | System-formatted time | Not used as a detail metric | Time formatting follows the user’s locale |

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
popover, both floating-panel layouts, and every supported widget family.

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

The following release-gate checks remain open and therefore keep PX-001, PX-003, PX-006,
and PX-007 incomplete:

- Increased Contrast and Reduce Motion must be toggled and the full surface matrix
  repeated on a release candidate.
- The full VoiceOver reading order and every supported widget family still require
  manual inspection.
- Two-display behavior, display removal, Space changes, and sleep/wake require suitable
  hardware and an extended lifecycle session.

## Approved feature program verification record

The 2026-07-28 local implementation pass produced the following additional evidence:

- All 23 MetricsKit tests and all 44 app tests passed with stable Xcode 26.6.
- Deterministic tests cover alert migration and delivery state, native system-condition
  alerts, Attention Log retention/deduplication/export, Compact Health resolution and
  stable width, Energy Guard policies, allowlisted routing/actions, System Summary
  privacy, diagnostics redaction and byte-equivalent preview/export, layout presets,
  What's New policy, and floating-panel display geometry.
- A universal Release archive completed with Hardened Runtime. Its app, embedded widget,
  and Sparkle framework pass deep strict code-signature validation.
- The archived app and widget contain the same App Group. The widget also contains App
  Sandbox, and both privacy manifests are present and valid.
- The user placed Small and Medium Mectrics widgets from the native gallery. The supplied
  screenshot shows correct family sizing but an empty “Waiting for Mectrics” timeline.
  The private Debug fallback was removed, signed App Group snapshot writes now succeed,
  and the shared snapshot is readable. Large-family, relaunch, reboot, replacement, and
  notarized-install checks remain open.
- Sparkle 2.9.4 is pinned in `project.yml`, the public EdDSA key is embedded, the private
  key is stored in Keychain, and automatic checks are disabled. The configured HTTPS
  appcast remains unavailable until the repository and release feed are published.
- The signed Release app was installed in `/Applications`. It still needs its launch-once
  and visual checks because the macOS UI-control service was unavailable during the final
  pass.

These results are implementation evidence, not task closure. PX checkboxes remain open
until the manual appearance/accessibility matrix, performance measurements, complete
widget lifecycle matrix, signed appcast upgrade/failure tests, clean-account testing,
Developer ID export, notarization, stapling, and Gatekeeper checks all pass.
