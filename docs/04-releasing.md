# 04 — Release and Notarization

The release script archives the app with Hardened Runtime, exports it with a
Developer ID Application signature, verifies the exported signature, creates a
drag-to-Applications DMG, signs the DMG, submits it to Apple's notary service,
and staples the ticket.

## One-time setup

1. Add the Apple Developer account to Xcode and create a Developer ID Application
   certificate.
2. Enable the App Group `group.com.mectrics.app` for both bundle identifiers:
   `com.mectrics.app` and `com.mectrics.app.widget`.
3. Store notary credentials in Keychain:

```bash
xcrun notarytool store-credentials mectrics-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

## Build the release

```bash
MECTRICS_TEAM_ID="YOUR_TEAM_ID" \
MECTRICS_NOTARY_PROFILE="mectrics-notary" \
./scripts/release.sh
```

The notarized artifact is written to `build/release/Mectrics.dmg`. The `build/`
directory is local output and must not be committed.

## Sparkle updates

The application embeds Sparkle's public EdDSA key and reads its appcast from:

`https://raw.githubusercontent.com/farukkamcici/mectrics/main/appcast.xml`

The corresponding private key lives only in the release operator's macOS Keychain.
Never export it into this repository, CI logs, or a release directory. Automatic checks
are disabled; Mectrics accesses the feed only after the user chooses
**Check for Updates…**.

After notarization and stapling, generate the appcast from the exact DMG that will be
published:

```bash
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' \
  -type d -print -quit)"
"$SPARKLE_BIN/generate_appcast" build/release
```

Verify that the appcast's version and build match the DMG, publish both without
modification, and test an older signed build against the feed. If an update fails
signature, notarization, download, or installation validation, do not replace the
current app. Keep the current signed DMG available for manual recovery; roll forward
with a higher build number rather than rewriting a published artifact.
