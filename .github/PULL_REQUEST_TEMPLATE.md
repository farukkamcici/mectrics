# Summary

<!-- What changes, and why. Link the issue it closes: Closes #123 -->

## How I verified it

<!--
  Say what you actually ran and saw. For visual changes, describe the menu bar and popover
  state before and after — screenshots are welcome.
-->

- [ ] `swift test` passes in `Packages/MetricsKit`
- [ ] `xcodebuild -project Mectrics.xcodeproj -scheme Mectrics -configuration Debug build` succeeds with no new warnings
- [ ] Checked in the running app (menu bar + popover), not only in tests

## Conventions checklist

- [ ] Everything in the diff is in English — code, comments, docs, commit messages
- [ ] User-facing strings go through `String(localized:)` or SwiftUI `Text`
- [ ] Menu bar item width still does not depend on the current value (width template updated if a format changed)
- [ ] Missing readings render as a dash, never as a fabricated `0`
- [ ] No telemetry, and no network call outside the explicit update check
- [ ] `xcodegen generate` was run if files were added or removed; `Mectrics.xcodeproj/` is not committed
- [ ] No AI attribution in commits (no `Co-Authored-By:` or "Generated with" trailers)
