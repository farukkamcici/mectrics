#!/bin/zsh
# Measures a Release app or an existing process without attaching a debugger.
set -euo pipefail
zmodload zsh/datetime

usage() {
  cat <<'EOF'
Usage:
  measure.sh --app <Mectrics.app> [options]
  measure.sh --pid <pid> [options]

Options:
  --duration <seconds>   Total duration (default: 2160; 31 measured minutes)
  --warmup <seconds>     Samples excluded from the gate (default: 300)
  --interval <seconds>   Sampling interval (default: 5)
  --scenario <name>      Filesystem-safe scenario name (default: idle)
  --profile <file>       Menu bar layout and alert rules to run with
                         (see scripts/performance/profiles/)
  --settings <pane>      Open Settings on general | menu-bar | alerts
  --output <directory>   New output directory
  --powermetrics         Also capture privileged diagnostic power data

Budget overrides:
  MECTRICS_MAX_FOOTPRINT_MB
  MECTRICS_MAX_CPU_MEDIAN_PERCENT
  MECTRICS_MAX_CPU_P95_PERCENT
  MECTRICS_MAX_SUSTAINED_CPU_SECONDS
  MECTRICS_MAX_MEMORY_SLOPE_MB_PER_HOUR
  MECTRICS_MAX_IDLE_CONNECTIONS
EOF
}

repo_root=${0:A:h:h:h}
app_path=""
target_pid=""
duration=2160
warmup=300
interval=5
scenario=idle
output_dir=""
capture_power=false
profile_path=""
settings_pane=""

while (( $# > 0 )); do
  case "$1" in
    --app) app_path=$2; shift 2 ;;
    --pid) target_pid=$2; shift 2 ;;
    --duration) duration=$2; shift 2 ;;
    --warmup) warmup=$2; shift 2 ;;
    --interval) interval=$2; shift 2 ;;
    --scenario) scenario=$2; shift 2 ;;
    --profile) profile_path=$2; shift 2 ;;
    --settings) settings_pane=$2; shift 2 ;;
    --output) output_dir=$2; shift 2 ;;
    --powermetrics) capture_power=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

case "$settings_pane" in
  ""|general|menu-bar|alerts) ;;
  *) echo "Settings pane must be general, menu-bar, or alerts" >&2; exit 64 ;;
esac
if [[ -n "$settings_pane" && -z "$app_path" ]]; then
  echo "--settings needs --app: only a launched app can be sent a route" >&2
  exit 64
fi
if [[ -n "$profile_path" && ! -f "$profile_path" ]]; then
  echo "Profile not found: $profile_path" >&2
  exit 66
fi

if [[ -n "$app_path" && -n "$target_pid" ]] || [[ -z "$app_path" && -z "$target_pid" ]]; then
  echo "Choose exactly one of --app or --pid" >&2
  exit 64
fi
for value in "$duration" "$warmup" "$interval"; do
  [[ "$value" == <-> ]] || { echo "Durations must be whole seconds" >&2; exit 64; }
done
(( interval > 0 && duration > warmup + (interval * 2) )) || {
  echo "Duration must leave at least three samples after warm-up" >&2
  exit 64
}
[[ "$scenario" =~ '^[A-Za-z0-9._-]+$' ]] || {
  echo "Scenario may contain only letters, numbers, dot, underscore, and hyphen" >&2
  exit 64
}

launched_pid=""
power_pid=""
preferences_backup_dir=""
preferences_had_domain=false
version=unknown
if [[ -n "$app_path" ]]; then
  app_path=${app_path:A}
  app_binary="$app_path/Contents/MacOS/Mectrics"
  info_plist="$app_path/Contents/Info.plist"
  [[ -x "$app_binary" && -f "$info_plist" ]] || {
    echo "Not a runnable Mectrics app: $app_path" >&2
    exit 66
  }
  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
else
  [[ "$target_pid" == <-> ]] && kill -0 "$target_pid" 2>/dev/null || {
    echo "Process is not running: $target_pid" >&2
    exit 69
  }
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
if [[ -z "$output_dir" ]]; then
  output_dir="$repo_root/build/performance/runs/$version/$timestamp-$scenario"
fi
output_dir=${output_dir:A}
if [[ -e "$output_dir" ]]; then
  echo "Output directory already exists: $output_dir" >&2
  exit 73
fi
mkdir -p "$output_dir"

cleanup() {
  if [[ -n "$power_pid" ]] && kill -0 "$power_pid" 2>/dev/null; then
    kill -TERM "$power_pid" 2>/dev/null || true
    wait "$power_pid" 2>/dev/null || true
  fi
  if [[ -n "$launched_pid" ]] && kill -0 "$launched_pid" 2>/dev/null; then
    kill -TERM "$launched_pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$launched_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$launched_pid" 2>/dev/null; then
      kill -KILL "$launched_pid" 2>/dev/null || true
    fi
    wait "$launched_pid" 2>/dev/null || true
    # The preferences daemon can still be flushing the exiting process's writes.
    # Restoring before it settles leaves the run's keys behind.
    for _ in {1..30}; do
      pgrep -x Mectrics >/dev/null 2>&1 || break
      sleep 0.1
    done
    sleep 1
  fi
  if [[ -n "$preferences_backup_dir" ]]; then
    preferences_backup="$preferences_backup_dir/com.mectrics.app.plist"
    preferences_path="$HOME/Library/Preferences/com.mectrics.app.plist"
    if $preferences_had_domain; then
      # `defaults import` merges into an existing domain. Delete the test-mutated
      # domain first so keys created by frameworks during the run cannot survive.
      defaults delete com.mectrics.app >/dev/null 2>&1 || true
      defaults import com.mectrics.app "$preferences_backup" >/dev/null
    else
      # A domain that did not exist before the run must not exist after it. The
      # daemon can recreate an empty plist moments after the delete, so the removal
      # is retried until the file stays gone.
      for _ in {1..10}; do
        defaults delete com.mectrics.app >/dev/null 2>&1 || true
        if [[ ! -f "$preferences_path" ]]; then
          break
        fi
        if [[ "$(/usr/bin/plutil -convert json -o - "$preferences_path")" == "{}" ]]; then
          /bin/unlink "$preferences_path"
        fi
        [[ -f "$preferences_path" ]] || break
        sleep 0.5
      done
    fi
    [[ ! -f "$preferences_backup" ]] || /bin/unlink "$preferences_backup"
    rmdir "$preferences_backup_dir"
    preferences_backup_dir=""
  fi
}
trap cleanup EXIT INT TERM

if [[ -n "$app_path" ]]; then
  isolated_home="$output_dir/home"
  mkdir -p "$isolated_home"
  preferences_backup_dir=$(mktemp -d "${TMPDIR:-/tmp}/mectrics-preferences.XXXXXX")
  preferences_backup="$preferences_backup_dir/com.mectrics.app.plist"
  if defaults export com.mectrics.app "$preferences_backup" >/dev/null 2>&1; then
    preferences_had_domain=true
  fi
  # Showing the Settings window persists its frame. Remembering whether that key was
  # already there lets the run notice a window nobody asked for — a click on the menu
  # bar item halfway through turns a menu-bar-only measurement into a different one,
  # and the numbers look plausible either way.
  settings_frame_before=no
  defaults read com.mectrics.app "NSWindow Frame mectrics.settings" >/dev/null 2>&1 \
    && settings_frame_before=yes
  # Command-line defaults have the highest precedence and disappear with the process.
  # `defaults write` still talks to the per-user preferences daemon even when
  # CFFIXED_USER_HOME is set. Invalid data placeholders deliberately shadow any saved
  # layout and alert blobs; AppModel then falls back to its clean-install defaults. A
  # profile replaces those placeholders with real JSON, passed as old-style plist data
  # (`<hex>`) so it still never touches the user's domain. Frameworks may still persist
  # bookkeeping through cfprefsd, so cleanup restores the exact pre-run snapshot.
  alert_rules=__mectrics_performance_empty__
  system_alert_rules=__mectrics_performance_empty__
  enabled_components=__mectrics_performance_empty__
  if [[ -n "$profile_path" ]]; then
    profile_value() {
      jq -e -c ".$1" "$profile_path" 2>/dev/null | xxd -p | tr -d '\n'
    }
    for key in alertRules systemAlertRules enabledComponents; do
      encoded=$(profile_value "$key") || {
        echo "Profile is missing \"$key\": $profile_path" >&2
        exit 65
      }
      case "$key" in
        alertRules) alert_rules="<$encoded>" ;;
        systemAlertRules) system_alert_rules="<$encoded>" ;;
        enabledComponents) enabled_components="<$encoded>" ;;
      esac
    done
    cp "$profile_path" "$output_dir/profile.json"
  fi

  # Launched through LaunchServices so the run can be handed a `mectrics://` route the
  # way a user's click would deliver one. A second copy would answer that route and
  # skew the measurement, so the run refuses to start beside an existing process.
  pgrep -x Mectrics >/dev/null 2>&1 && {
    echo "Another Mectrics is already running; quit it before measuring" >&2
    exit 69
  }
  /usr/bin/open -a "$app_path" \
    --env CFFIXED_USER_HOME="$isolated_home" \
    --stdout "$output_dir/app.stdout" \
    --stderr "$output_dir/app.stderr" \
    --args \
    -ApplePersistenceIgnoreState YES \
    -NSQuitAlwaysKeepsWindows NO \
    -completedOnboardingVersion 2 \
    -lastPresentedWhatsNewVersion "$version" \
    -compactHealthEnabled NO \
    -adaptMonitoringToEnergyState YES \
    -showMenuBarIcons YES \
    -alertRules "$alert_rules" \
    -systemAlertRules "$system_alert_rules" \
    -enabledComponents "$enabled_components"
  sleep 3
  launched_pid=$(pgrep -x Mectrics | head -1)
  [[ -n "$launched_pid" ]] || {
    echo "Mectrics exited during launch; see $output_dir/app.stderr" >&2
    exit 70
  }
  target_pid=$launched_pid
  if [[ -n "$settings_pane" ]]; then
    /usr/bin/open -a "$app_path" "mectrics://$settings_pane"
    sleep 3
    kill -0 "$target_pid" 2>/dev/null || {
      echo "Mectrics exited while opening Settings" >&2
      exit 70
    }
  fi
fi

process_name=$(ps -p "$target_pid" -o comm= | sed 's|.*/||')
jq -n \
  --arg version "$version" \
  --arg scenario "$scenario" \
  --arg process "$process_name" \
  --arg startedAt "$timestamp" \
  --arg profile "${profile_path:t:r}" \
  --arg settingsPane "$settings_pane" \
  --argjson pid "$target_pid" \
  --argjson durationSeconds "$duration" \
  --argjson warmupSeconds "$warmup" \
  --argjson intervalSeconds "$interval" \
  '{version: $version, scenario: $scenario, process: $process, pid: $pid,
    startedAt: $startedAt, durationSeconds: $durationSeconds,
    warmupSeconds: $warmupSeconds, intervalSeconds: $intervalSeconds,
    profile: (if $profile == "" then "clean install defaults" else $profile end),
    settingsPane: (if $settingsPane == "" then "closed" else $settingsPane end),
    cpuMethod: "process CPU-time delta divided by wall-time delta"}' \
  > "$output_dir/metadata.json"

if $capture_power; then
  if (( EUID == 0 )); then
    power_command=(powermetrics)
  elif sudo -n true 2>/dev/null; then
    power_command=(sudo -n powermetrics)
  else
    echo "--powermetrics requires root or an existing non-interactive sudo authorization" >&2
    exit 77
  fi
  power_samples=$(( (duration + interval - 1) / interval ))
  "${power_command[@]}" \
    --samplers tasks,disk,network \
    --show-process-energy \
    --show-process-samp-norm \
    --show-process-io \
    --show-process-netstats \
    --sample-rate $(( interval * 1000 )) \
    --sample-count "$power_samples" \
    --output-file "$output_dir/powermetrics.txt" &
  power_pid=$!
fi

samples="$output_dir/samples.csv"
echo "timestamp,elapsed_seconds,phase,cpu_percent,phys_footprint_bytes,connections" > "$samples"
# A public performance claim has to name the power state, and adaptive sampling makes
# a run that switched to battery a different measurement. Recorded per sample so the
# claim is checkable rather than remembered.
power_log="$output_dir/power-source.csv"
echo "elapsed_seconds,power_source" > "$power_log"
start=$EPOCHREALTIME
previous_cpu_seconds=""
previous_cpu_elapsed=""

while true; do
  kill -0 "$target_pid" 2>/dev/null || {
    echo "Measured process exited early" >&2
    exit 70
  }
  elapsed=$(( EPOCHREALTIME - start ))
  (( elapsed <= duration )) || break
  phase=measured
  (( elapsed < warmup )) && phase=warmup

  cpu_time=$(ps -p "$target_pid" -o time= | tr -d ' ')
  cpu_seconds=$(awk -F: '
    NF == 2 { printf "%.3f", ($1 * 60) + $2 }
    NF == 3 { printf "%.3f", ($1 * 3600) + ($2 * 60) + $3 }
  ' <<< "$cpu_time")
  [[ -n "$cpu_seconds" ]] || {
    echo "Could not read cumulative CPU time for process $target_pid" >&2
    exit 70
  }
  if [[ -n "$previous_cpu_seconds" ]]; then
    cpu=$(awk \
      -v current="$cpu_seconds" \
      -v previous="$previous_cpu_seconds" \
      -v elapsed="$elapsed" \
      -v previous_elapsed="$previous_cpu_elapsed" \
      'BEGIN {
        wall = elapsed - previous_elapsed
        printf "%.3f", (wall > 0 ? ((current - previous) / wall) * 100 : 0)
      }')
  else
    cpu=0
  fi
  previous_cpu_seconds=$cpu_seconds
  previous_cpu_elapsed=$elapsed
  footprint_output=$(footprint -p "$target_pid" --noCategories -f bytes 2>/dev/null || true)
  footprint_bytes=$(awk '/phys_footprint:/ { print $2; exit }' <<< "$footprint_output")
  [[ -n "$footprint_bytes" ]] || {
    echo "Could not read phys_footprint for process $target_pid" >&2
    exit 70
  }
  connections=$(
    { /usr/sbin/lsof -nP -a -p "$target_pid" -i 2>/dev/null || true; } \
      | awk 'NR > 1 { count += 1 } END { print count + 0 }'
  )

  printf '%s,%.3f,%s,%s,%s,%s\n' \
    "$(date -u +%s)" "$elapsed" "$phase" "$cpu" "$footprint_bytes" "$connections" \
    >> "$samples"
  printf '%.3f,%s\n' \
    "$elapsed" \
    "$(pmset -g batt | awk -F"'" 'NR == 1 { print $2; exit }')" \
    >> "$power_log"
  sleep "$interval"
done

if [[ -n "$app_path" && -z "$settings_pane" && "$settings_frame_before" == no ]] \
  && defaults read com.mectrics.app "NSWindow Frame mectrics.settings" >/dev/null 2>&1; then
  cleanup
  launched_pid=""
  power_pid=""
  trap - EXIT INT TERM
  echo "A Settings window was opened during a run that did not ask for one." >&2
  echo "That is a different workload; discard $output_dir and measure again." >&2
  exit 75
fi

cleanup
launched_pid=""
power_pid=""
trap - EXIT INT TERM

"$repo_root/scripts/performance/summarize.sh" --samples "$samples"
echo "Raw samples: $samples"
