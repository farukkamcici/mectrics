#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
release_root="$repo_root/build/release"
archive_path="$release_root/Mectrics.xcarchive"
export_path="$release_root/export"
export_options_path="$release_root/ExportOptions.plist"
staging_path="$release_root/dmg"
dmg_path="$release_root/Mectrics.dmg"

: "${MECTRICS_TEAM_ID:?Set MECTRICS_TEAM_ID to your Apple Developer Team ID.}"
: "${MECTRICS_NOTARY_PROFILE:?Set MECTRICS_NOTARY_PROFILE to a notarytool keychain profile.}"
MECTRICS_SIGNING_IDENTITY=${MECTRICS_SIGNING_IDENTITY:-Developer ID Application}

command -v xcodegen >/dev/null
xcrun notarytool history --keychain-profile "$MECTRICS_NOTARY_PROFILE" >/dev/null

mkdir -p "$release_root"
xcodegen generate
rm -rf "$archive_path" "$export_path"
xcodebuild archive \
  -project Mectrics.xcodeproj \
  -scheme Mectrics \
  -configuration Release \
  -archivePath "$archive_path" \
  -destination "generic/platform=macOS" \
  DEVELOPMENT_TEAM="$MECTRICS_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

rm -f "$export_options_path"
plutil -create xml1 "$export_options_path"
plutil -insert method -string developer-id "$export_options_path"
plutil -insert signingStyle -string automatic "$export_options_path"
plutil -insert teamID -string "$MECTRICS_TEAM_ID" "$export_options_path"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options_path" \
  -allowProvisioningUpdates

app_path="$export_path/Mectrics.app"
codesign --verify --deep --strict --verbose=2 "$app_path"

rm -rf "$staging_path"
mkdir -p "$staging_path"
ditto "$app_path" "$staging_path/Mectrics.app"
ln -s /Applications "$staging_path/Applications"

rm -f "$dmg_path"
hdiutil create \
  -volname "Mectrics" \
  -srcfolder "$staging_path" \
  -ov \
  -format UDZO \
  "$dmg_path"

codesign --force \
  --timestamp \
  --sign "$MECTRICS_SIGNING_IDENTITY" \
  "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"

xcrun notarytool submit "$dmg_path" \
  --keychain-profile "$MECTRICS_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

echo "Release ready: $dmg_path"
