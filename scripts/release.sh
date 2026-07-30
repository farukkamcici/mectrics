#!/bin/zsh
#
# Builds a release: archive with Hardened Runtime, export with a Developer ID Application
# signature, verify it, create a drag-to-Applications DMG, sign and notarize the DMG, and
# staple the ticket. The result is build/release/Mectrics.dmg (local output, not committed).
#
#   MECTRICS_TEAM_ID=... MECTRICS_NOTARY_PROFILE=... ./scripts/release.sh
#
# Requires a Developer ID Application certificate and a notarytool keychain profile
# (`xcrun notarytool store-credentials`). Never pass credentials on the command line.
set -euo pipefail

repo_root=${0:A:h:h}
release_root="$repo_root/build/release"
archive_path="$release_root/Mectrics.xcarchive"
export_path="$release_root/export"
export_options_path="$release_root/ExportOptions.plist"
staging_path="$release_root/dmg"
dmg_path="$release_root/Mectrics.dmg"

: "${MECTRICS_TEAM_ID:?Set MECTRICS_TEAM_ID to your Apple Developer Team ID.}"
# xcodegen reads this to fill DEVELOPMENT_TEAM, which is not committed in project.yml.
export MECTRICS_TEAM_ID
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

# ---- appcast
#
# SUFeedURL points at appcast.xml on the main branch, so a release is not finished
# until that file describes it. generate_appcast signs each entry with the private
# EdDSA key from the login Keychain, the half that never leaves this machine.
version=$(defaults read "$app_path/Contents/Info" CFBundleShortVersionString)

appcast_tool=${MECTRICS_APPCAST_TOOL:-$(command -v generate_appcast || true)}
if [[ -z "$appcast_tool" ]]; then
  appcast_tool=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*artifacts/sparkle/Sparkle/bin/generate_appcast' -print -quit 2>/dev/null || true)
fi
: "${appcast_tool:?Could not find generate_appcast. Set MECTRICS_APPCAST_TOOL to its path.}"

# generate_appcast reads a directory of archives, so give it one holding only the DMG.
appcast_staging="$release_root/appcast"
rm -rf "$appcast_staging"
mkdir -p "$appcast_staging"
cp "$dmg_path" "$appcast_staging/"

"$appcast_tool" \
  --download-url-prefix "https://github.com/farukkamcici/mectrics/releases/download/v$version/" \
  --maximum-versions 5 \
  -o "$repo_root/appcast.xml" \
  "$appcast_staging"

echo
echo "Release ready:  $dmg_path"
echo "Appcast:        $repo_root/appcast.xml (version $version)"
echo
echo "Next: create the v$version tag and GitHub Release, attach the DMG, then commit"
echo "appcast.xml — the enclosure URL above only resolves once the release exists."
