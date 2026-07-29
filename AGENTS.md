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
  - `swift build`, `swift test`, `swift run mectrics-cli` (live terminal readout).
- `Mectrics/` — the menu bar app (SwiftUI + AppKit).
- `project.yml` — XcodeGen project definition. **This is the source**; `Mectrics.xcodeproj`
  is generated. After editing `project.yml` **or adding/removing source files**, run
  `xcodegen generate`.
- `docs/` — product plan, architecture, roadmap, research.

Do **not** commit: `Mectrics.xcodeproj/`, `DerivedData/`, `.build/` (see `.gitignore`).

## 2. Internationalization (i18n)

- All user-facing strings go through `String(localized:)` or SwiftUI `Text`/`Label`.
- Never hardcode user-facing prose as a plain `String` without localization.
- Strings are extracted into `Mectrics/Resources/Localizable.xcstrings` (String Catalog).
  To add a language: open the catalog in Xcode, add the language, translate. No code change.
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
- **One module owns at most one menu bar item.** Choosing a look replaces the previous
  one (`AppModel.setComponent(_:for:)`); it never adds a second item for that module.
- **Absence is not zero.** When a reading is missing, render a dash and never fabricate
  `0%` / `0`. Do not offer a component whose data this Mac cannot report.

## 4. Surfaces and Settings

- **The menu bar is the only live surface.** The always-on-top floating panel and its
  global hotkey were removed; the optional **Compact Health** item is the supported
  overview. Do not reintroduce a second always-visible rendering surface.
- **Settings holds configuration, not actions.** Quit, copy, and export belong to the
  surfaces that own them (popover, Diagnostics, Attention Log), not to a preferences pane.
- Every Settings pane uses `Form(.grouped)` and shares one window size — switching tabs
  moves the selection, never the window.
- Prefer progressive disclosure over dimmed controls: hide a control that cannot act yet
  and show its current value as text instead.

## 5. Performance & privacy invariants

- **Zero telemetry.** The only network calls allowed are (optional) update checks. No usage
  or hardware data ever leaves the device.
- Adaptive sampling: faster on AC, slower on battery; pause work that isn't visible.
- Keep the hot path allocation-free (the ring buffer is pre-allocated).
- Targets: < 60 MB RAM, low/steady CPU, "Energy Impact: Low" in Activity Monitor.
- Heavy providers (SMC/GPU/sensors) use `cost = .heavy` and are sampled less often.

## 6. Adding a metric provider

1. Add a `MetricProvider` in `Packages/MetricsKit/Sources/MetricsKit/Providers/`.
2. Return `isAvailable = false` when the hardware/permission is absent (module auto-hides).
3. Add it to `MetricsKit.coreProviders()`.
4. Add menu-bar text in `MenuBarText` (+ a stable template in `MetricStatusItem`).
5. Add popover rows + primary value in `DetailPopoverView` (localized labels).
6. Add a sanity test in `MetricsKitTests`.

## 7. Build / test / run

```bash
# Core engine (no Xcode)
cd Packages/MetricsKit && swift test && swift run mectrics-cli

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

## 9. Product decisions (fixed)

- Distribution: **Direct / DMG** (Developer ID + notarization).
- Minimum macOS: **15 (Sequoia)**.
- License/model: **free & open source** (no Free/Pro split, no licensing code).

## 10. Extending these rules

When the user establishes a new convention, add it here (and reflect it in `CLAUDE.md` if
Claude-specific). Keep this file the single source of truth.
