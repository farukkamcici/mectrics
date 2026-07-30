#!/bin/zsh
#
# Removes Mectrics and everything it stored on this Mac.
#
#     ./scripts/uninstall.sh          # asks first, lists what it will delete
#     ./scripts/uninstall.sh --yes    # no prompt
#
# Deleting Mectrics.app on its own leaves your settings behind, which is why a
# reinstall skips onboarding — macOS keeps preferences and containers when an
# app goes to the Trash. This removes those too, so a reinstall starts clean.
#
# No administrator rights are needed: Mectrics installs no helper tool, no
# LaunchDaemon, and writes nothing outside your own home folder.
set -euo pipefail

assume_yes=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && assume_yes=1

app="/Applications/Mectrics.app"
targets=(
  "$app"
  "$HOME/Library/Preferences/com.mectrics.app.plist"
  "$HOME/Library/Group Containers/group.com.mectrics.app"
  "$HOME/Library/Containers/com.mectrics.app.widget"
  "$HOME/Library/Application Support/Mectrics"
  "$HOME/Library/Caches/com.mectrics.app"
  "$HOME/Library/Caches/com.mectrics.app.sparkle"
  "$HOME/Library/HTTPStorages/com.mectrics.app"
  "$HOME/Library/Saved Application State/com.mectrics.app.savedState"
)

present=()
for t in "${targets[@]}"; do
  [[ -e "$t" ]] && present+=("$t")
done

if (( ${#present[@]} == 0 )); then
  echo "Nothing to remove — Mectrics is not installed and left no data."
  exit 0
fi

echo "This will delete:"
printf '  %s\n' "${present[@]}"
echo
echo "Your Attention Log and any saved diagnostics are included. Copy them first"
echo "if you want to keep them."

if (( ! assume_yes )); then
  echo
  printf "Continue? [y/N] "
  read -r reply
  [[ "$reply" == [yY] ]] || { echo "Cancelled."; exit 1; }
fi

# Quit first. A running Mectrics writes its preferences on the way out, which
# would put the file straight back after it was deleted.
osascript -e 'quit app "Mectrics"' 2>/dev/null || true
for _ in 1 2 3 4 5; do
  pgrep -x Mectrics >/dev/null 2>&1 || break
  sleep 1
done
pkill -x Mectrics 2>/dev/null || true
pkill -f 'MectricsWidget.appex' 2>/dev/null || true

# Preferences live in cfprefsd's cache as well as on disk, so remove the domain
# through defaults before unlinking the file.
defaults delete com.mectrics.app 2>/dev/null || true

# One protected path must not abandon the rest, so each target is its own attempt.
# ~/Library/Containers belongs to containermanagerd: removing the widget's sandbox
# is refused unless the caller holds Full Disk Access, and that is not worth asking
# for to delete one JSON snapshot.
failed=()
for t in "${present[@]}"; do
  rm -rf "$t" 2>/dev/null || failed+=("$t")
done

echo
if (( ${#failed[@]} == 0 )); then
  echo "Removed. Mectrics left no helper tools, daemons, or files elsewhere."
else
  echo "Removed everything except:"
  printf '  %s\n' "${failed[@]}"
  echo
  echo "macOS protects those paths from the command line. Drag them to the Trash in"
  echo "Finder (⇧⌘G to paste the path), or leave them — they hold nothing but a cached"
  echo "snapshot, and macOS reclaims the container once the extension is gone."
fi

echo
echo "If you had turned on Launch at login, macOS may still list a stale entry"
echo "under System Settings → General → Login Items. Removing it there is the"
echo "last step; an app cannot unregister itself once it has been deleted."
