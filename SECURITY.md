# Security Policy

## Supported versions

mectrics is pre-1.0. Only the latest commit on `main` and the most recent release receive
security fixes.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's
[private vulnerability reporting](https://github.com/farukkamcici/mectrics/security/advisories/new)
on this repository. If that form is unavailable to you, open a regular issue that says only
that you have a security report and asks for a contact channel — do not include details.

Please include, as far as you can:

- the affected version or commit,
- your macOS version and Mac model,
- reproduction steps or a proof of concept,
- what an attacker gains.

You can expect an acknowledgement within a week. Fixes ship in the next release, and
reporters are credited in the changelog unless they prefer otherwise.

## What is in scope

- Privilege escalation, arbitrary code execution, or sandbox escape via the app or its
  widget extension.
- Anything that causes data to leave the device, since the project guarantees zero
  telemetry. A network request the user did not trigger is a security bug, not a feature
  request.
- Tampering with the Sparkle update path: feed spoofing, signature bypass, or downgrade
  attacks.
- Unsafe handling of the App Group container shared between the app and the widget.
- Local files written outside the app's own container without the user choosing a location.

## What is out of scope

- Reading system metrics through public APIs, IORegistry, or the SMC. These are read-only
  interfaces available to any user-level process; exposing them is the purpose of the app.
- The absence of App Sandbox on the main app target. IOKit access for metrics requires it
  to be off; the Release build uses Hardened Runtime and is signed and notarized, and the
  widget extension *is* sandboxed.
- Findings that require physical access to an unlocked Mac, or an attacker who already has
  administrator rights.
- Denial of service caused by deliberately extreme system load.

## Hardening notes for reviewers

- Release builds enable Hardened Runtime and are signed with a Developer ID certificate,
  then notarized and stapled — see [`scripts/release.sh`](scripts/release.sh).
- Automatic update checks are disabled (`SUEnableAutomaticChecks: false`). The appcast is
  fetched only on an explicit **Check for Updates…**, and is verified against the EdDSA
  public key pinned in `project.yml`.
- The metric engine has no network code at all.
