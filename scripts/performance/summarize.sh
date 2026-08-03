#!/bin/zsh
# Summarizes a measure.sh CSV and enforces the idle Release budgets.
set -euo pipefail

if [[ $# -ne 2 || "$1" != "--samples" ]]; then
  echo "Usage: $0 --samples <samples.csv>" >&2
  exit 64
fi

samples=${2:A}
[[ -f "$samples" ]] || { echo "Samples file not found: $samples" >&2; exit 66; }

expected_header="timestamp,elapsed_seconds,phase,cpu_percent,phys_footprint_bytes,connections"
header=$(head -n 1 "$samples")
[[ "$header" == "$expected_header" ]] || {
  echo "Unexpected samples header" >&2
  exit 65
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/mectrics-performance.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

awk -F, '$3 == "measured" { print $4 }' "$samples" > "$work_dir/cpu"
awk -F, '$3 == "measured" { print $5 }' "$samples" > "$work_dir/memory"
sample_count=$(wc -l < "$work_dir/cpu" | tr -d ' ')
(( sample_count >= 3 )) || {
  echo "At least three post-warm-up samples are required" >&2
  exit 65
}

quantile() {
  local file=$1
  local percentile=$2
  local count rank
  count=$(wc -l < "$file" | tr -d ' ')
  rank=$(( (count * percentile + 99) / 100 ))
  LC_ALL=C sort -n "$file" | sed -n "${rank}p"
}

cpu_median=$(quantile "$work_dir/cpu" 50)
cpu_p95=$(quantile "$work_dir/cpu" 95)
cpu_max=$(LC_ALL=C sort -n "$work_dir/cpu" | tail -n 1)
memory_p95_bytes=$(quantile "$work_dir/memory" 95)
memory_max_bytes=$(LC_ALL=C sort -n "$work_dir/memory" | tail -n 1)
memory_p95_mb=$(awk -v value="$memory_p95_bytes" 'BEGIN { printf "%.2f", value / 1000000 }')
memory_max_mb=$(awk -v value="$memory_max_bytes" 'BEGIN { printf "%.2f", value / 1000000 }')
max_connections=$(awk -F, '$3 == "measured" && $6 > max { max = $6 } END { print max + 0 }' "$samples")
measured_duration=$(awk -F, '$3 == "measured" { if (!seen) { first = $2; seen = 1 }; last = $2 } END { printf "%.3f", last - first }' "$samples")

# Least-squares slope is more stable than comparing only the first and last sample.
memory_slope_mb_per_hour=$(awk -F, '
  $3 == "measured" {
    x = $2
    y = $5 / 1000000
    n += 1; sx += x; sy += y; sxx += x * x; sxy += x * y
  }
  END {
    denominator = n * sxx - sx * sx
    slope = denominator == 0 ? 0 : (n * sxy - sx * sy) / denominator
    printf "%.3f", slope * 3600
  }
' "$samples")

max_high_cpu_seconds=$(awk -F, -v threshold=10 '
  $3 == "measured" {
    if ($4 > threshold) {
      if (!active) { started = $2; active = 1 }
      duration = $2 - started
      if (duration > longest) longest = duration
    } else {
      active = 0
    }
  }
  END { printf "%.3f", longest + 0 }
' "$samples")

max_footprint_mb=${MECTRICS_MAX_FOOTPRINT_MB:-60}
max_cpu_median=${MECTRICS_MAX_CPU_MEDIAN_PERCENT:-3}
max_cpu_p95=${MECTRICS_MAX_CPU_P95_PERCENT:-5}
max_sustained_cpu_seconds=${MECTRICS_MAX_SUSTAINED_CPU_SECONDS:-30}
max_memory_slope=${MECTRICS_MAX_MEMORY_SLOPE_MB_PER_HOUR:-1}
max_idle_connections=${MECTRICS_MAX_IDLE_CONNECTIONS:-0}
minimum_slope_duration=${MECTRICS_MINIMUM_SLOPE_DURATION_SECONDS:-1800}

float_greater_than() {
  awk -v lhs="$1" -v rhs="$2" 'BEGIN { exit !(lhs > rhs) }'
}

typeset -a failures
if float_greater_than "$memory_p95_mb" "$max_footprint_mb"; then
  failures+=("memory p95 ${memory_p95_mb} MB exceeds ${max_footprint_mb} MB")
fi
if float_greater_than "$cpu_median" "$max_cpu_median"; then
  failures+=("CPU median ${cpu_median}% exceeds ${max_cpu_median}%")
fi
if float_greater_than "$cpu_p95" "$max_cpu_p95"; then
  failures+=("CPU p95 ${cpu_p95}% exceeds ${max_cpu_p95}%")
fi
if float_greater_than "$max_high_cpu_seconds" "$max_sustained_cpu_seconds"; then
  failures+=("CPU stayed above 10% for ${max_high_cpu_seconds}s")
fi
if (( max_connections > max_idle_connections )); then
  failures+=("idle network connections ${max_connections} exceeds ${max_idle_connections}")
fi

slope_enforced=false
if ! float_greater_than "$minimum_slope_duration" "$measured_duration"; then
  slope_enforced=true
  if float_greater_than "$memory_slope_mb_per_hour" "$max_memory_slope"; then
    failures+=("memory slope ${memory_slope_mb_per_hour} MB/hour exceeds ${max_memory_slope}")
  fi
fi

summary_path="${samples:h}/summary.json"
if (( ${#failures[@]} == 0 )); then
  passed=true
  failures_json='[]'
else
  passed=false
  failures_json=$(printf '%s\n' "${failures[@]}" | jq -R . | jq -s .)
fi
jq -n \
  --argjson sampleCount "$sample_count" \
  --argjson measuredDurationSeconds "$measured_duration" \
  --argjson cpuMedianPercent "$cpu_median" \
  --argjson cpuP95Percent "$cpu_p95" \
  --argjson cpuMaxPercent "$cpu_max" \
  --argjson memoryP95MB "$memory_p95_mb" \
  --argjson memoryMaxMB "$memory_max_mb" \
  --argjson memorySlopeMBPerHour "$memory_slope_mb_per_hour" \
  --argjson maximumConnections "$max_connections" \
  --argjson maximumSustainedHighCPUSeconds "$max_high_cpu_seconds" \
  --argjson memorySlopeEnforced "$slope_enforced" \
  --argjson passed "$passed" \
  --argjson failures "$failures_json" \
  '{
    sampleCount: $sampleCount,
    measuredDurationSeconds: $measuredDurationSeconds,
    cpu: {
      medianPercent: $cpuMedianPercent,
      p95Percent: $cpuP95Percent,
      maximumPercent: $cpuMaxPercent,
      maximumSustainedAboveTenPercentSeconds: $maximumSustainedHighCPUSeconds
    },
    memory: {
      p95MB: $memoryP95MB,
      maximumMB: $memoryMaxMB,
      slopeMBPerHour: $memorySlopeMBPerHour,
      slopeEnforced: $memorySlopeEnforced
    },
    network: { maximumOpenConnections: $maximumConnections },
    passed: $passed,
    failures: $failures
  }' > "$summary_path"

echo "Performance summary"
echo "  CPU median / p95 / max: $cpu_median% / $cpu_p95% / $cpu_max%"
echo "  Memory p95 / max:       $memory_p95_mb MB / $memory_max_mb MB"
echo "  Memory slope:           $memory_slope_mb_per_hour MB/hour (enforced: $slope_enforced)"
echo "  Open connections max:   $max_connections"
echo "  Summary:                $summary_path"

if (( ${#failures[@]} > 0 )); then
  echo "Performance gate failed:" >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Performance gate passed."
