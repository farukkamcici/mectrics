# Documentation

[**Architecture**](architecture.md) — the app/engine split, technology choices and their
rationale, where each metric comes from, the menu bar rendering rules, the performance
strategy, and the repository layout.

For the conventions you must follow when contributing, see [`AGENTS.md`](../AGENTS.md) —
that is the source of truth, not these documents. For setup and the development loop, see
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

Where a document and the code disagree, the code wins and the document gets corrected.

## Assets

[`assets/`](assets/) holds the README banner (`banner-light.svg`, `banner-dark.svg`),
generated as a pair by [`scripts/generate-banner.py`](../scripts/generate-banner.py) so
GitHub can serve the right one per theme via `<picture>`. Screenshots belong here too.
