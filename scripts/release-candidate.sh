#!/bin/zsh
# Builds a signed, notarized release candidate without changing appcast.xml or the
# normal build/release output. Nothing is uploaded to GitHub and no tag is created.
set -euo pipefail

repo_root=${0:A:h:h}
version=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$repo_root/project.yml")

if [[ -z "$version" || "$version" != <->.<->.<-> ]]; then
  echo "Could not read a semantic MARKETING_VERSION from project.yml" >&2
  exit 70
fi

candidate_root=${MECTRICS_CANDIDATE_ROOT:-$repo_root/build/candidate/$version}

MECTRICS_RELEASE_ROOT="$candidate_root" \
MECTRICS_SKIP_APPCAST=1 \
  exec "$repo_root/scripts/release.sh"
