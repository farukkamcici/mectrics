#!/bin/zsh
# Fast contract tests for the local performance gate; does not launch the app.
set -euo pipefail

repo_root=${0:A:h:h:h}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mectrics-performance-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

pass_dir="$test_root/pass"
fail_dir="$test_root/fail"
mkdir -p "$pass_dir" "$fail_dir"

printf '%s\n' \
  'timestamp,elapsed_seconds,phase,cpu_percent,phys_footprint_bytes,connections' \
  '1,0,warmup,20,30000000,0' \
  '2,5,measured,0.2,30000000,0' \
  '3,10,measured,0.4,30100000,0' \
  '4,15,measured,0.6,30200000,0' \
  > "$pass_dir/samples.csv"

"$repo_root/scripts/performance/summarize.sh" \
  --samples "$pass_dir/samples.csv" >/dev/null
jq -e '.passed == true and (.failures | length == 0)' \
  "$pass_dir/summary.json" >/dev/null

printf '%s\n' \
  'timestamp,elapsed_seconds,phase,cpu_percent,phys_footprint_bytes,connections' \
  '1,0,measured,5,70000000,1' \
  '2,5,measured,5,70000000,1' \
  '3,10,measured,5,70000000,1' \
  > "$fail_dir/samples.csv"

if "$repo_root/scripts/performance/summarize.sh" \
  --samples "$fail_dir/samples.csv" >/dev/null 2>&1; then
  echo "A fixture over every budget unexpectedly passed" >&2
  exit 1
fi
jq -e '.passed == false and (.failures | length >= 3)' \
  "$fail_dir/summary.json" >/dev/null

# A Release launch must not seed UserDefaults with `defaults write`: modern macOS
# routes that command through the real per-user preferences daemon even when
# CFFIXED_USER_HOME points at a test directory. Process-only argument defaults keep
# the run deterministic and prevent window restoration without touching user state.
if grep -Ev '^[[:space:]]*#' "$repo_root/scripts/performance/measure.sh" \
  | grep -q 'defaults write'; then
  echo "The performance launcher must not write to the real preferences domain" >&2
  exit 1
fi
grep -q -- '-ApplePersistenceIgnoreState YES' \
  "$repo_root/scripts/performance/measure.sh"
grep -q 'alert_rules=__mectrics_performance_empty__' \
  "$repo_root/scripts/performance/measure.sh"
grep -q 'enabled_components=__mectrics_performance_empty__' \
  "$repo_root/scripts/performance/measure.sh"
grep -q 'defaults export com.mectrics.app' \
  "$repo_root/scripts/performance/measure.sh"
grep -q 'defaults import com.mectrics.app' \
  "$repo_root/scripts/performance/measure.sh"

# A profile reaches the app as process-only argument data, never as a written domain.
grep -q -- '-alertRules "\$alert_rules"' "$repo_root/scripts/performance/measure.sh"

# Every shipped profile has to be readable by the launcher and describe all three
# keys it substitutes, or a run silently measures the wrong configuration.
for profile in "$repo_root"/scripts/performance/profiles/*.json; do
  jq -e '.alertRules and .systemAlertRules and .enabledComponents' \
    "$profile" >/dev/null || {
    echo "Profile is incomplete: $profile" >&2
    exit 1
  }
done

# A window nobody asked for changes the workload without changing the report, so the
# launcher has to notice one appearing during a run that did not request Settings.
grep -q 'settings_frame_before' "$repo_root/scripts/performance/measure.sh"
grep -q 'A Settings window was opened during a run that did not ask for one' \
  "$repo_root/scripts/performance/measure.sh"

# The Settings scenarios rely on the app's own route table; an unknown pane must be
# rejected before anything is launched.
if "$repo_root/scripts/performance/measure.sh" \
  --app /nonexistent.app --settings nowhere >/dev/null 2>&1; then
  echo "An unknown Settings pane unexpectedly passed validation" >&2
  exit 1
fi

echo "Performance gate contracts passed."
