# Documentation

[**Architecture**](architecture.md) — the app/engine split, technology choices and their
rationale, where each metric comes from, the menu bar rendering rules, the performance
strategy, and the repository layout.

For the conventions you must follow when contributing, see [`AGENTS.md`](../AGENTS.md) —
that is the source of truth, not these documents. For setup and the development loop, see
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Where to look

Each question is answered once, at the depth the person asking needs.

| You want to know | Read |
|---|---|
| What Mectrics costs while it runs, in plain terms | [`README.md`](../README.md) — "Light on the machine" |
| What was measured, on what, and which budgets are met today | [Architecture → Power and performance](architecture.md#power-and-performance) |
| *Why* it costs that, and where the cost actually is | [Architecture → Where the cost actually is](architecture.md#where-the-cost-actually-is) |
| How to reproduce a measurement yourself | [`CONTRIBUTING.md`](../CONTRIBUTING.md#performance-validation) |
| The rules a change must not break | [`AGENTS.md`](../AGENTS.md) §5 |
| What changed for users in a release | [`CHANGELOG.md`](../CHANGELOG.md) |

Where a document and the code disagree, the code wins and the document gets corrected.

## Assets

[`assets/`](assets/) holds the README banner (`banner-light.svg`, `banner-dark.svg`),
generated as a pair by [`scripts/generate-banner.py`](../scripts/generate-banner.py) so
GitHub can serve the right one per theme via `<picture>`. Screenshots belong here too.
