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

Sparkle requires a stable HTTPS appcast URL and an EdDSA public key. Add it only after
the public GitHub repository and release URL are final, then generate the appcast from
the same notarized DMG.
