# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

> **Read [`AGENTS.md`](AGENTS.md) first — it is the source of truth for all conventions.**
> This file only adds Claude-specific notes.

## Absolute must-knows (see AGENTS.md for detail)

- **English-only repo.** Code, comments, docs, commit messages, and base UI strings are all
  in English. The user may chat in Turkish; that never changes what lands in the repo.
- **i18n:** user-facing strings via `String(localized:)` / `Text` → String Catalog
  (`Mectrics/Resources/Localizable.xcstrings`). Never hardcode user-facing prose.
- **Menu bar width must be stable** — fixed reserved widths, right-aligned text
  (`MetricStatusItem`). Never let item width depend on the current value.
- **Zero telemetry**, adaptive sampling, keep it lightweight (< 60 MB RAM).
- `project.yml` is the source; run `xcodegen generate` after adding files or editing it.
  Never commit `Mectrics.xcodeproj/`, `DerivedData/`, `.build/`.

## Fast local loop (no Xcode UI)

```bash
cd Packages/MetricsKit && swift test && swift run mectrics-cli
```

## Build & run the app

```bash
xcodegen generate
xcodebuild -project Mectrics.xcodeproj -scheme Mectrics -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Mectrics-*/Build/Products/Debug/Mectrics.app
```

## Notes

- This is a menu bar agent (`LSUIElement`), so there is no Dock icon or window — verify via
  the menu bar and the popover, or via `mectrics-cli` for the raw metrics.
- Screenshotting the desktop menu bar requires Screen Recording permission granted to the
  host app; otherwise `screencapture` fails with "could not create image from display".
- When the user sets a new rule, record it in `AGENTS.md` (source of truth).
