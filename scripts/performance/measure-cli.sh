#!/bin/zsh
# Benchmarks the real CLI embedded in a Release app with isolated preferences.
set -euo pipefail
zmodload zsh/datetime

usage() {
  echo "Usage: $0 --app <Mectrics.app> [--iterations N] [--baseline summary.json] [--output directory]"
}

repo_root=${0:A:h:h:h}
app_path=""
iterations=20
baseline=""
output_dir=""

while (( $# > 0 )); do
  case "$1" in
    --app) app_path=$2; shift 2 ;;
    --iterations) iterations=$2; shift 2 ;;
    --baseline) baseline=$2; shift 2 ;;
    --output) output_dir=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

[[ -n "$app_path" && "$iterations" == <-> && iterations -ge 3 ]] || {
  usage >&2
  exit 64
}
app_path=${app_path:A}
cli="$app_path/Contents/Helpers/mectrics"
info_plist="$app_path/Contents/Info.plist"
[[ -x "$cli" && -f "$info_plist" ]] || { echo "Embedded CLI not found" >&2; exit 66; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")

if [[ -n "$baseline" ]]; then
  baseline=${baseline:A}
  jq -e '.commands.doctor.p95Milliseconds' "$baseline" >/dev/null || {
    echo "Invalid CLI baseline: $baseline" >&2
    exit 65
  }
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
output_dir=${output_dir:-$repo_root/build/performance/cli/$version/$timestamp}
output_dir=${output_dir:A}
[[ ! -e "$output_dir" ]] || { echo "Output already exists: $output_dir" >&2; exit 73; }
mkdir -p "$output_dir/home"
samples="$output_dir/samples.csv"
echo "command,iteration,elapsed_milliseconds,exit_code" > "$samples"

run_command() {
  local name=$1
  shift
  local iteration started elapsed exit_status
  for iteration in {1..$iterations}; do
    started=$EPOCHREALTIME
    set +e
    CFFIXED_USER_HOME="$output_dir/home" "$cli" "$@" >/dev/null 2> "$output_dir/$name-$iteration.stderr"
    exit_status=$?
    set -e
    elapsed=$(( (EPOCHREALTIME - started) * 1000 ))
    printf '%s,%d,%.3f,%d\n' "$name" "$iteration" "$elapsed" "$exit_status" >> "$samples"
    case "$name:$exit_status" in
      doctor:0|doctor:1|doctor:2|check:0|check:1|check:2|snapshot:0) ;;
      *) echo "$name returned unexpected exit code $exit_status" >&2; exit 70 ;;
    esac
  done
}

run_command doctor doctor --json
run_command check check --json
run_command snapshot snapshot --json

quantile_for() {
  local name=$1 percentile=$2
  local count rank
  count=$(awk -F, -v name="$name" '$1 == name { count += 1 } END { print count + 0 }' "$samples")
  rank=$(( (count * percentile + 99) / 100 ))
  awk -F, -v name="$name" '$1 == name { print $3 }' "$samples" \
    | LC_ALL=C sort -n | sed -n "${rank}p"
}

typeset -A p50 p95 maximum ceiling
ceiling=(doctor ${MECTRICS_CLI_DOCTOR_CEILING_MS:-1000} check ${MECTRICS_CLI_CHECK_CEILING_MS:-1000} snapshot ${MECTRICS_CLI_SNAPSHOT_CEILING_MS:-3000})
typeset -a failures
for name in doctor check snapshot; do
  p50[$name]=$(quantile_for "$name" 50)
  p95[$name]=$(quantile_for "$name" 95)
  maximum[$name]=$(awk -F, -v name="$name" '$1 == name && $3 > max { max = $3 } END { printf "%.3f", max }' "$samples")
  limit=${ceiling[$name]}
  if [[ -n "$baseline" ]]; then
    baseline_p95=$(jq -r ".commands.$name.p95Milliseconds" "$baseline")
    regression_limit=$(awk -v value="$baseline_p95" 'BEGIN { printf "%.3f", value * 1.20 }')
    limit=$(awk -v absolute_limit="$limit" -v regression_limit="$regression_limit" \
      'BEGIN { print (absolute_limit < regression_limit ? absolute_limit : regression_limit) }')
  fi
  if awk -v value="${p95[$name]}" -v limit="$limit" 'BEGIN { exit !(value > limit) }'; then
    failures+=("$name p95 ${p95[$name]} ms exceeds $limit ms")
  fi
done

summary="$output_dir/summary.json"
if (( ${#failures[@]} == 0 )); then
  passed=true
  failures_json='[]'
else
  passed=false
  failures_json=$(printf '%s\n' "${failures[@]}" | jq -R . | jq -s .)
fi
jq -n \
  --arg version "$version" \
  --argjson iterations "$iterations" \
  --argjson doctorP50 "${p50[doctor]}" --argjson doctorP95 "${p95[doctor]}" --argjson doctorMax "${maximum[doctor]}" \
  --argjson checkP50 "${p50[check]}" --argjson checkP95 "${p95[check]}" --argjson checkMax "${maximum[check]}" \
  --argjson snapshotP50 "${p50[snapshot]}" --argjson snapshotP95 "${p95[snapshot]}" --argjson snapshotMax "${maximum[snapshot]}" \
  --argjson passed "$passed" \
  --argjson failures "$failures_json" \
  '{version: $version, iterations: $iterations, commands: {
      doctor: {p50Milliseconds: $doctorP50, p95Milliseconds: $doctorP95, maximumMilliseconds: $doctorMax},
      check: {p50Milliseconds: $checkP50, p95Milliseconds: $checkP95, maximumMilliseconds: $checkMax},
      snapshot: {p50Milliseconds: $snapshotP50, p95Milliseconds: $snapshotP95, maximumMilliseconds: $snapshotMax}
    }, passed: $passed, failures: $failures}' > "$summary"

for name in doctor check snapshot; do
  echo "$name: p50 ${p50[$name]} ms, p95 ${p95[$name]} ms, max ${maximum[$name]} ms"
done
echo "Summary: $summary"

if (( ${#failures[@]} > 0 )); then
  printf 'Performance gate failed: %s\n' "${failures[@]}" >&2
  exit 1
fi
echo "CLI performance gate passed."
