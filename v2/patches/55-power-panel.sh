#!/usr/bin/env bash
# Hexciri fork patch 55: power panel — sleep drain, battery health, charge limit
# (upstream omarchy PR #20379, verified against its .diff 2026-11-27).
#
# What lands:
#   * bin/hexciri-battery-status --shell gains battery health % (full vs
#     design capacity, clamped 1..100), charge-limit metadata (supported /
#     state / mode / end / start), and last-sleep drain (duration, %/h, W,
#     S0ix %) read from /run/hexciri/last-sleep. Thresholds now trust sysfs
#     charge_control_end_threshold over UPower 1.91+ hwdb defaults (75/80%
#     printed even when disabled) — sysfs at 100% means the limit is off.
#   * bin/hexciri-battery-limit (new): 80% charge cap with on/off/once
#     (top up to 100% once, then re-arm) /toggle/status, via UPower
#     EnableChargeThreshold, marker at ~/.local/state/hexciri/battery/.
#   * default/systemd/system-sleep/hexciri-sleep-stats (new): pre/post
#     suspend hook recording battery energy + S0ix residency to
#     /run/hexciri/last-sleep and /var/lib/hexciri/sleep-history.tsv.
#   * Power panel: charge-limit section (toggle + one-time top-up row),
#     health + last-sleep rows in the stats grid, shallow-S0ix warning,
#     limit tick on the progress bar, keyboard cursor across limit/topup/
#     profile rows. Battery service re-arms the limit after a top-up once
#     the battery hits 100% or power is unplugged (2s debounce for USB-C PD
#     renegotiation glitches). ToggleSwitch knob geometry goes exact-integer
#     so the compact header switch never touches the track border.
#   * default/i18n/en/shell.json: the 10 power.* keys the panel uses.
#
# Fork adaptations (vs upstream verbatim):
#   * Renames only: omarchy- -> hexciri-, OMARCHY_ -> HEXCIRI_,
#     /run/omarchy -> /run/hexciri, /var/lib/omarchy -> /var/lib/hexciri,
#     /omarchy/battery -> /hexciri/battery, omarchy. -> hexciri. The
#     `# omarchy:summary` / `# omarchy:subcommand` comments in the new bin
#     are kept: the fork keeps that prefix (see bin/hexciri-battery-status).
#   * bin/hexciri-battery-limit needs NO install.sh allowlist change:
#     is_allowed_bin already matches battery-*.
#   * SKIPPED, bin/omarchy-debug hunk: hexciri-debug is not in
#     is_allowed_bin, so it is not in FORK_OUT and the hunk has no landing.
#     Adding `debug` to the allowlist would land it (and the hunk).
#   * SKIPPED, docs/file-layout.md: docs/ is not copied to FORK_OUT.
#   * SKIPPED, test/shell.d/*: test/ is not in FORK_OUT. The upstream
#     battery-status / battery / power test additions were instead re-run
#     as a behavior sim against the patched sim tree (see README section).
#   * NEEDS THE PLACEMENT STEP: install.sh copies only fprintd-resume out
#     of default/systemd/system-sleep/ (line 1647) and never installs
#     FORK_OUT/etc/ to the live system, so hexciri-sleep-stats is staged
#     in FORK_OUT only until install.sh gains a placement step:
#       sudo install -Dm755 "$FORK_OUT/default/systemd/system-sleep/hexciri-sleep-stats" \
#         /usr/lib/systemd/system-sleep/hexciri-sleep-stats
#     Until that lands, no last-sleep file is ever written and the panel
#     simply shows no sleep row (battery-status skips it when absent).
#   * Upstream quirk kept verbatim: Service.qml checkTopUpOnceRearm passes
#     UPower.onBattery for both onBattery and wasOnBattery, so the unplug
#     re-arm comes from the 2s debounce timer, not that call.
#
# Sim base: pin tarball 94a8c3c + install.sh rename map + patch 25's power
# Panel.qml edits (the only prior patch touching these files). Run 1 edits,
# run 2 zero edits; bash -n on the three bash files; node --check on the
# two .js files; python json.load on shell.json.
#
# Standalone: bash v2/patches/55-power-panel.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.


set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "55-power-panel.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  if [ "${IS_RERUN:-0}" = "1" ]; then
    case "$1" in
      Kept*|*already\ present*|*already\ correct*|*already\ current*|Theme\ already\ applied:*|*already\ enabled*)
        printf '[hexciri] %s\n' "$1" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
        return 0
        ;;
    esac
  fi
  printf '[hexciri] %s\n' "$1"
}
warn() { printf 'WARN: %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "55-power-panel.sh: $1" >&2; exit 1; }
CHANGED=0
# Write a new file from stdin; idempotent via content compare, dies rather
# than clobbering a different existing file. $1 = FORK_OUT-relative path,
# $2 = mode (755 for bin/, 644 for config/drop-ins).
install_new_file() {
  local rel="$1" mode="$2" dest tmp
  dest="$FORK_OUT/$rel"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ]; then
    if cmp -s "$tmp" "$dest"; then
      printf '%s: already present, skipping\n' "$rel" >>"$_patch_log"
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
    die "$rel already exists with different content, refusing to clobber it"
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod "$mode" "$dest"
  CHANGED=$((CHANGED + 1))
  printf 'patched: created %s\n' "$rel" >>"$_patch_log"
}

# --- 1. new bin hexciri-battery-limit ---
install_new_file "bin/hexciri-battery-limit" 755 <<'HEXCIRI_EOF_BATTERY_LIMIT'
#!/bin/bash

# omarchy:summary=Manage the battery charge limit (80% cap, 100% once, or full)
# omarchy:subcommand=status [--shell] — Show the current battery charge limit state
# omarchy:subcommand=on — Enable the hardware battery charge limit
# omarchy:subcommand=off — Disable the charge limit and allow full charging
# omarchy:subcommand=once — Charge to 100% once, then re-enable the limit automatically
# omarchy:subcommand=toggle — Toggle the battery charge limit on or off

set -euo pipefail

state_dir="${HEXCIRI_BATTERY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hexciri/battery}"
once_file="$state_dir/top-up-once"
power_supply_path="${HEXCIRI_POWER_SUPPLY_PATH:-/sys/class/power_supply}"

usage() {
  echo "Usage: hexciri-battery-limit [status [--shell]|on|off|once|toggle]" >&2
  exit 2
}

action="${1:-status}"
shell_output=false
if [[ $action == "status" && ${2:-} == "--shell" ]]; then
  shell_output=true
elif (( $# > 1 )); then
  usage
fi

upower_prop() {
  local path=$1 prop=$2 raw
  raw=$(busctl get-property org.freedesktop.UPower "$path" org.freedesktop.UPower.Device "$prop" 2>/dev/null) || return 1
  # busctl prints e.g. "b true", "u 80", "s \"BAT1\""
  raw=${raw#* }
  raw=${raw#\"}
  raw=${raw%\"}
  printf '%s\n' "$raw"
}

# Enumerate all present system batteries that support hardware charge limits.
mapfile -t battery_paths < <(
  busctl --no-pager tree --list org.freedesktop.UPower 2>/dev/null | grep '/org/freedesktop/UPower/devices/battery_' || true
)

supported_batteries=()
for path in "${battery_paths[@]}"; do
  [[ -n $path ]] || continue
  [[ $(upower_prop "$path" PowerSupply || true) == "true" ]] || continue
  [[ $(upower_prop "$path" ChargeThresholdSupported || true) == "true" ]] || continue
  supported_batteries+=("$path")
done

effective_state() {
  if (( ${#supported_batteries[@]} == 0 )); then
    printf 'unsupported\n'
    return 0
  fi

  local enabled_count=0 path enabled native sysfs_end
  for path in "${supported_batteries[@]}"; do
    enabled=$(upower_prop "$path" ChargeThresholdEnabled || echo "false")
    if [[ $enabled == "true" ]]; then
      (( enabled_count++ ))
    else
      native=$(upower_prop "$path" NativePath || true)
      if [[ -n $native && -r $power_supply_path/$native/charge_control_end_threshold ]]; then
        sysfs_end=$(<"$power_supply_path/$native/charge_control_end_threshold")
        if [[ $sysfs_end =~ ^[0-9]+$ ]] && (( sysfs_end > 0 && sysfs_end < 100 )); then
          (( enabled_count++ ))
        fi
      fi
    fi
  done

  if (( enabled_count == ${#supported_batteries[@]} )); then
    printf 'on\n'
  elif (( enabled_count > 0 )); then
    printf 'mixed\n'
  elif [[ -f $once_file ]]; then
    printf 'once\n'
  else
    printf 'off\n'
  fi
}

apply_threshold() {
  local want=$1 path actual
  if (( ${#supported_batteries[@]} == 0 )); then
    echo "Battery charge limit is not supported on this machine." >&2
    exit 1
  fi

  for path in "${supported_batteries[@]}"; do
    busctl call org.freedesktop.UPower "$path" org.freedesktop.UPower.Device EnableChargeThreshold b "$want" >/dev/null
    actual=$(upower_prop "$path" ChargeThresholdEnabled || echo "")
    if [[ $actual != "$want" ]]; then
      echo "UPower did not apply charge threshold ($want) on $path (got: ${actual:-unknown})." >&2
      exit 1
    fi
  done
}

notify_shell() {
  hexciri-shell -q battery refreshChargeLimit >/dev/null 2>&1 || true
}

case "$action" in
  status)
    cur=$(effective_state)
    if [[ $shell_output == "true" ]]; then
      printf 'state\t%s\n' "$cur"
      if (( ${#supported_batteries[@]} > 0 )); then
        first=${supported_batteries[0]}
        settings_mask=$(upower_prop "$first" ChargeThresholdSettingsSupported || echo "0")
        end_val=$(upower_prop "$first" ChargeEndThreshold || true)
        start_val=$(upower_prop "$first" ChargeStartThreshold || true)
        printf 'supported\t1\n'
        if (( settings_mask == 4 )); then
          printf 'mode\tfirmware\n'
        else
          printf 'mode\tthreshold\n'
        fi
        [[ -n $end_val ]] && printf 'end\t%s\n' "$end_val"
        [[ -n $start_val ]] && printf 'start\t%s\n' "$start_val"
      else
        printf 'supported\t0\n'
      fi
    else
      printf '%s\n' "$cur"
    fi
    ;;
  on)
    apply_threshold true
    rm -f "$once_file"
    notify_shell
    ;;
  off)
    apply_threshold false
    rm -f "$once_file"
    notify_shell
    ;;
  once)
    apply_threshold false
    mkdir -p "$state_dir"
    printf '%s\n' "$(date +%s)" >"$once_file"
    notify_shell
    ;;
  toggle)
    cur=$(effective_state)
    if [[ $cur == "on" || $cur == "once" ]]; then
      apply_threshold false
      rm -f "$once_file"
    else
      apply_threshold true
      rm -f "$once_file"
    fi
    notify_shell
    ;;
  *)
    usage
    ;;
esac
HEXCIRI_EOF_BATTERY_LIMIT

bash -n "$FORK_OUT/bin/hexciri-battery-limit" || die "bash -n failed on bin/hexciri-battery-limit"
grep -q 'HEXCIRI_' "$FORK_OUT/bin/hexciri-battery-limit" || die "bin/hexciri-battery-limit lost its HEXCIRI_ env vars"

# --- 2. new system-sleep hook hexciri-sleep-stats ---
install_new_file "default/systemd/system-sleep/hexciri-sleep-stats" 755 <<'HEXCIRI_EOF_SLEEP_STATS'
#!/bin/bash

# Record battery energy and S0ix hardware sleep residency across suspend and
# hibernate so the power panel and hexciri-debug can show actual sleep drain.

set -u

action="${1:-}"
sleep_type="${2:-suspend}"

power_supply_path="${HEXCIRI_POWER_SUPPLY_PATH:-/sys/class/power_supply}"
run_dir="${HEXCIRI_SLEEP_RUN_DIR:-/run/hexciri}"
state_dir="${HEXCIRI_SLEEP_STATE_DIR:-/var/lib/hexciri}"
suspend_stats_path="${HEXCIRI_SUSPEND_STATS_PATH:-/sys/power/suspend_stats}"
cpuidle_path="${HEXCIRI_CPUIDLE_PATH:-/sys/devices/system/cpu/cpuidle}"
mem_sleep_path="${HEXCIRI_MEM_SLEEP_PATH:-/sys/power/mem_sleep}"
uptime_path="${HEXCIRI_UPTIME_PATH:-/proc/uptime}"
pmc_debug_path="${HEXCIRI_PMC_DEBUG_PATH:-/sys/kernel/debug/pmc_core}"
amd_pmc_debug_path="${HEXCIRI_AMD_PMC_DEBUG_PATH:-/sys/kernel/debug/amd_pmc}"

pre_file="$run_dir/sleep-pre"
last_file="$run_dir/last-sleep"
history_file="$state_dir/sleep-history.tsv"

read_int() {
  local value
  { value=$(<"$1"); } 2>/dev/null || return 1
  [[ $value =~ ^-?[0-9]+$ ]] || return 1
  printf '%s\n' "$value"
}

read_uptime_us() {
  local line first
  { read -r first _ <"$uptime_path"; } 2>/dev/null || return 1
  awk -v t="$first" 'BEGIN { if (t + 0 <= 0) exit 1; printf "%.0f\n", t * 1000000 }'
}

read_ac_online() {
  local supply online
  for supply in "$power_supply_path"/*; do
    [[ -r $supply/type && $(<"$supply/type") == "Mains" && -r $supply/online ]] || continue
    online=$(<"$supply/online")
    if [[ $online == "1" ]]; then
      printf '1\n'
      return 0
    fi
  done
  printf '0\n'
}

read_sleep_mode() {
  if [[ $sleep_type == "hibernate" || $sleep_type == "hybrid-sleep" ]]; then
    printf '%s\n' "$sleep_type"
    return 0
  fi
  if [[ -r $mem_sleep_path ]]; then
    local mode
    mode=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$mem_sleep_path")
    if [[ -n $mode ]]; then
      printf '%s\n' "$mode"
      return 0
    fi
  fi
  printf '%s\n' "$sleep_type"
}

# Aggregate present system batteries (excluding wireless peripherals with
# scope=Device). Prefer energy_now/energy_full (µWh); on charge-based batteries
# multiply µAh by voltage_min_design (µV) rather than instantaneous voltage_now
# because open-circuit voltage recovery during sleep would skew or invert drain.
read_battery_energy() {
  local supply now_uwh=0 full_uwh=0 count=0
  local e_now e_full c_now c_full v_design

  for supply in "$power_supply_path"/*; do
    [[ -r $supply/type && $(<"$supply/type") == "Battery" ]] || continue
    if [[ -r $supply/present && $(<"$supply/present") == "0" ]]; then
      continue
    fi
    if [[ -r $supply/scope && $(<"$supply/scope") == "Device" ]]; then
      continue
    fi

    if e_now=$(read_int "$supply/energy_now") && e_full=$(read_int "$supply/energy_full") && (( e_full > 0 )); then
      (( now_uwh += e_now ))
      (( full_uwh += e_full ))
      (( count++ ))
    elif c_now=$(read_int "$supply/charge_now") && c_full=$(read_int "$supply/charge_full") && (( c_full > 0 )); then
      v_design=$(read_int "$supply/voltage_min_design" || read_int "$supply/voltage_now" || true)
      if [[ -n ${v_design:-} ]] && (( v_design > 0 )); then
        (( now_uwh += (c_now * v_design) / 1000000 ))
        (( full_uwh += (c_full * v_design) / 1000000 ))
        (( count++ ))
      fi
    fi
  done

  (( count > 0 && full_uwh > 0 )) || return 1
  printf '%s\t%s\n' "$now_uwh" "$full_uwh"
}

read_lpi_us() {
  read_int "$cpuidle_path/low_power_idle_system_residency_us" 2>/dev/null || printf '\n'
}

read_pmc_slp_s0_us() {
  if [[ -r $pmc_debug_path/slp_s0_residency_usec ]]; then
    read_int "$pmc_debug_path/slp_s0_residency_usec" 2>/dev/null || printf '\n'
  elif [[ -r $amd_pmc_debug_path/s0ix_stats ]]; then
    awk '/Residency Time:/ { print $3; exit }' "$amd_pmc_debug_path/s0ix_stats" 2>/dev/null || printf '\n'
  else
    printf '\n'
  fi
}

atomic_write() {
  local target=$1
  local dir tmp
  dir=$(dirname "$target")
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.tmp.XXXXXX") || return 1
  cat >"$tmp"
  chmod 0644 "$tmp"
  mv -fT "$tmp" "$target"
}

if [[ $action == "pre" ]]; then
  energy=$(read_battery_energy) || exit 0
  IFS=$'\t' read -r now_uwh full_uwh <<<"$energy"
  uptime_us=$(read_uptime_us) || exit 0
  ac_online=$(read_ac_online)
  mode=$(read_sleep_mode)
  lpi_us=$(read_lpi_us)
  pmc_us=$(read_pmc_slp_s0_us)

  atomic_write "$pre_file" <<EOF
uptime_us	$uptime_us
now_uwh	$now_uwh
full_uwh	$full_uwh
ac_online	$ac_online
mode	$mode
lpi_us	$lpi_us
pmc_us	$pmc_us
EOF
  exit 0
fi

if [[ $action == "post" ]]; then
  [[ -r $pre_file ]] || exit 0

  pre_uptime_us="" pre_now_uwh="" pre_full_uwh="" pre_ac="0" pre_mode="" pre_lpi_us="" pre_pmc_us=""
  while IFS=$'\t' read -r key val; do
    case "$key" in
      uptime_us) pre_uptime_us=$val ;;
      now_uwh) pre_now_uwh=$val ;;
      full_uwh) pre_full_uwh=$val ;;
      ac_online) pre_ac=$val ;;
      mode) pre_mode=$val ;;
      lpi_us) pre_lpi_us=$val ;;
      pmc_us) pre_pmc_us=$val ;;
    esac
  done <"$pre_file"
  rm -f "$pre_file"

  [[ -n $pre_uptime_us && -n $pre_now_uwh && -n $pre_full_uwh ]] || exit 0
  energy=$(read_battery_energy) || exit 0
  IFS=$'\t' read -r post_now_uwh post_full_uwh <<<"$energy"
  post_uptime_us=$(read_uptime_us) || exit 0
  post_ac=$(read_ac_online)
  post_lpi_us=$(read_lpi_us)
  post_pmc_us=$(read_pmc_slp_s0_us)
  last_hw_sleep_us=$(read_int "$suspend_stats_path/last_hw_sleep" 2>/dev/null || true)

  wall_us=$(( post_uptime_us - pre_uptime_us ))
  (( wall_us > 0 )) || exit 0
  duration_s=$(( (wall_us + 500000) / 1000000 ))
  (( duration_s > 0 )) || exit 0

  delta_uwh=$(( pre_now_uwh - post_now_uwh ))
  ac_plugged=0
  if [[ $pre_ac == "1" || $post_ac == "1" ]] || (( delta_uwh < 0 )); then
    ac_plugged=1
  fi

  # Compute S0ix residency only for s2idle suspends, rejecting 32-bit PMC counter
  # wrap outliers where reported hardware sleep exceeds wall time by >5%.
  s0ix_pct=""
  if [[ $pre_mode == "s2idle" ]]; then
    hw_us=""
    for candidate in \
      "${last_hw_sleep_us:-}" \
      "$([[ -n $pre_pmc_us && -n $post_pmc_us ]] && printf '%s' "$(( post_pmc_us - pre_pmc_us ))")" \
      "$([[ -n $pre_lpi_us && -n $post_lpi_us ]] && printf '%s' "$(( post_lpi_us - pre_lpi_us ))")"; do
      [[ $candidate =~ ^[0-9]+$ ]] || continue
      if awk -v hw="$candidate" -v wall="$wall_us" 'BEGIN { exit !(hw >= 0 && hw <= wall * 1.05) }'; then
        hw_us=$candidate
        break
      fi
    done

    if [[ -n $hw_us ]]; then
      s0ix_pct=$(awk -v hw="$hw_us" -v wall="$wall_us" 'BEGIN {
        pct = (hw / wall) * 100
        if (pct < 0) pct = 0
        if (pct > 100) pct = 100
        printf "%.0f", pct
      }')
    fi
  fi

  read -r delta_pct delta_wh drain_pct_hr drain_w < <(awk \
    -v delta_uwh="$delta_uwh" -v full_uwh="$pre_full_uwh" \
    -v dur_s="$duration_s" -v ac="$ac_plugged" 'BEGIN {
      if (ac == 1 || delta_uwh < 0 || full_uwh <= 0) {
        print "0 0 - -"
        exit
      }
      dpct = (delta_uwh / full_uwh) * 100
      dwh = delta_uwh / 1000000
      if (dur_s >= 300) {
        hrs = dur_s / 3600
        printf "%.1f %.2f %.1f %.1f\n", dpct, dwh, dpct / hrs, dwh / hrs
      } else {
        printf "%.1f %.2f - -\n", dpct, dwh
      }
    }')

  [[ $drain_pct_hr == "-" ]] && drain_pct_hr=""
  [[ $drain_w == "-" ]] && drain_w=""

  timestamp=$(date +%s)

  atomic_write "$last_file" <<EOF
timestamp	$timestamp
mode	$pre_mode
duration_s	$duration_s
ac_plugged	$ac_plugged
delta_pct	$delta_pct
delta_wh	$delta_wh
drain_pct_hr	$drain_pct_hr
drain_w	$drain_w
s0ix_pct	$s0ix_pct
EOF

  mkdir -p "$state_dir"
  {
    [[ -r $history_file ]] && tail -n 49 "$history_file"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$timestamp" "$pre_mode" "$duration_s" "$ac_plugged" \
      "$delta_pct" "$delta_wh" "$drain_pct_hr" "$drain_w" "$s0ix_pct"
  } | atomic_write "$history_file"
fi
HEXCIRI_EOF_SLEEP_STATS

bash -n "$FORK_OUT/default/systemd/system-sleep/hexciri-sleep-stats" || die "bash -n failed on default/systemd/system-sleep/hexciri-sleep-stats"
grep -q 'HEXCIRI_' "$FORK_OUT/default/systemd/system-sleep/hexciri-sleep-stats" || die "default/systemd/system-sleep/hexciri-sleep-stats lost its HEXCIRI_ env vars"

# --- 3. battery-status edits (bin/hexciri-battery-status) ---
step "battery-status edits"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 55 bin/hexciri-battery-status edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/bin/hexciri-battery-status"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _apply(text, old, new, label):
    """Replace old (exactly once) with new; skip if already applied."""
    if new == "":
        if old not in text:
            print("%s: already present, skipping" % label)
            return text, 0
    elif new in text:
        print("%s: already present, skipping" % label)
        return text, 0
    if text.count(old) != 1:
        _die("%s: anchor occurs %d times, want exactly 1" % (label, text.count(old)))
    return text.replace(old, new, 1), 1


REPLACEMENTS = [
    ('\nshell_output=false\npower_supply_path="${HEXCIRI_POWER_SUPPLY_PATH:-/sys/class/power_supply}"\n\ncase "${1:-}" in\n  "")',
     '\nshell_output=false\npower_supply_path="${HEXCIRI_POWER_SUPPLY_PATH:-/sys/class/power_supply}"\nsleep_run_dir="${HEXCIRI_SLEEP_RUN_DIR:-/run/hexciri}"\nbattery_state_dir="${HEXCIRI_BATTERY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hexciri/battery}"\n\ncase "${1:-}" in\n  "")',
     'battery-status: sleep run/state dirs'),
    ('capacity=$(awk \'/energy-full:/ { printf "%d", $2; exit }\' <<<"$battery_info")\nenergy=$(awk \'/^ *energy:/ { print $2; exit }\' <<<"$battery_info")\nenergy_full=$(awk \'/energy-full:/ { print $2; exit }\' <<<"$battery_info")\nupower_hours=$(awk \'/time to (empty|full)/ { print ($5 ~ /^minute/ ? $4 / 60 : $4); exit }\' <<<"$battery_info")\npower_rate_raw=$(awk \'/energy-rate/ { print $2; exit }\' <<<"$battery_info")\nnative_path=$(awk \'/native-path/ { print $2; exit }\' <<<"$battery_info")',
     'capacity=$(awk \'/energy-full:/ { printf "%d", $2; exit }\' <<<"$battery_info")\nenergy=$(awk \'/^ *energy:/ { print $2; exit }\' <<<"$battery_info")\nenergy_full=$(awk \'/energy-full:/ { print $2; exit }\' <<<"$battery_info")\nenergy_full_design=$(awk \'/energy-full-design:/ { print $2; exit }\' <<<"$battery_info")\nupower_capacity=$(awk \'/^ *capacity:/ { gsub(/%/, "", $2); print $2; exit }\' <<<"$battery_info")\nupower_hours=$(awk \'/time to (empty|full)/ { print ($5 ~ /^minute/ ? $4 / 60 : $4); exit }\' <<<"$battery_info")\npower_rate_raw=$(awk \'/energy-rate/ { print $2; exit }\' <<<"$battery_info")\nnative_path=$(awk \'/native-path/ { print $2; exit }\' <<<"$battery_info")',
     'battery-status: design energy + UPower capacity'),
    ('  print rounded\n}\')\nstate=$(awk \'/state/ { print $2; exit }\' <<<"$battery_info")\nthreshold_start=$(awk \'/charge-start-threshold:/ { gsub(/%/, "", $2); print int($2); exit }\' <<<"$battery_info")\nthreshold_end=$(awk \'/charge-end-threshold:/ { gsub(/%/, "", $2); print int($2); exit }\' <<<"$battery_info")\n\n# Read the thresholds from the battery UPower resolved rather than a BAT* glob,\n# which misses every battery with another name.\n[[ -n $threshold_end || ! -r $battery_path/charge_control_end_threshold ]] || threshold_end=$(<"$battery_path/charge_control_end_threshold")\n[[ -n $threshold_start || ! -r $battery_path/charge_control_start_threshold ]] || threshold_start=$(<"$battery_path/charge_control_start_threshold")\n# The time to full counts to this battery\'s own limit, never another one\'s.\ncharge_limit=${threshold_end:-100}\n[[ -n $threshold_end ]] || threshold_end=$(cat "$power_supply_path"/BAT*/charge_control_end_threshold 2>/dev/null | head -1)\n[[ -n $threshold_start ]] || threshold_start=$(cat "$power_supply_path"/BAT*/charge_control_start_threshold 2>/dev/null | head -1)\n\n# Time left is the energy left over the draw shown beside it, so the two always\n# agree; charging counts up to the charge limit. UPower\'s own estimate averages',
     '  print rounded\n}\')\nstate=$(awk \'/state/ { print $2; exit }\' <<<"$battery_info")\nupower_threshold_start=$(awk \'/charge-start-threshold:/ { gsub(/%/, "", $2); print int($2); exit }\' <<<"$battery_info")\nupower_threshold_end=$(awk \'/charge-end-threshold:/ { gsub(/%/, "", $2); print int($2); exit }\' <<<"$battery_info")\nupower_threshold_enabled=$(awk \'/charge-threshold-enabled:/ { print tolower($2); exit }\' <<<"$battery_info")\nupower_threshold_supported=$(awk \'/charge-threshold-supported:/ { print tolower($2); exit }\' <<<"$battery_info")\n\nsysfs_threshold_end=$(read_sysfs_number "$battery_path/charge_control_end_threshold" || true)\nsysfs_threshold_start=$(read_sysfs_number "$battery_path/charge_control_start_threshold" || true)\n\n# Sysfs charge_control_end_threshold is the kernel\'s ground truth: UPower 1.91+\n# prints hwdb defaults (e.g. 75/80%) in `upower -i` even when ChargeThresholdEnabled\n# is false and sysfs is at 100%. Only fall back to UPower\'s thresholds when no\n# sysfs file exists (e.g. firmware-only conservation mode or test stubs).\nthreshold_start=""\nthreshold_end=""\nif [[ -n $sysfs_threshold_end ]]; then\n  if (( sysfs_threshold_end > 0 && sysfs_threshold_end < 100 )); then\n    threshold_end=$sysfs_threshold_end\n    if [[ -n $sysfs_threshold_start ]] && (( sysfs_threshold_start > 0 && sysfs_threshold_start < threshold_end )); then\n      threshold_start=$sysfs_threshold_start\n    fi\n  fi\nelif [[ $upower_threshold_enabled != "no" ]]; then\n  if [[ -n $upower_threshold_end ]] && (( upower_threshold_end > 0 && upower_threshold_end < 100 )); then\n    threshold_end=$upower_threshold_end\n    threshold_start=$upower_threshold_start\n  fi\nfi\n\n# The time to full counts to this battery\'s own limit, never another one\'s.\ncharge_limit=${threshold_end:-100}\nif [[ -z $sysfs_threshold_end && $upower_threshold_enabled != "no" ]]; then\n  if [[ -z $threshold_end ]]; then\n    fallback_end=$(cat "$power_supply_path"/BAT*/charge_control_end_threshold 2>/dev/null | head -1)\n    if [[ $fallback_end =~ ^[0-9]+$ ]] && (( fallback_end > 0 && fallback_end < 100 )); then\n      threshold_end=$fallback_end\n    fi\n  fi\n  if [[ -z $threshold_start && -n $threshold_end ]]; then\n    threshold_start=$(cat "$power_supply_path"/BAT*/charge_control_start_threshold 2>/dev/null | head -1)\n  fi\nfi\n\n# Time left is the energy left over the draw shown beside it, so the two always\n# agree; charging counts up to the charge limit. UPower\'s own estimate averages',
     'battery-status: sysfs-grounded thresholds (hwdb fix)'),
    ('  fi\nfi\n\nif [[ $shell_output == "true" ]]; then\n  printf \'percentage\\t%s\\n\' "${percentage}%"\n  if [[ $charge_holding == "true" ]]; then',
     '  fi\nfi\n\n# Battery health percentage (full vs design capacity, clamped to 1..100%).\ncompute_health() {\n  local full=$1 design=$2 cap=$3\n  awk -v full="$full" -v design="$design" -v cap="$cap" \'BEGIN {\n    pct = -1\n    if (full + 0 > 0 && design + 0 > 0) {\n      pct = (full / design) * 100\n    } else if (cap + 0 > 0) {\n      pct = cap + 0\n    }\n    if (pct <= 0) exit\n    if (pct > 100) pct = 100\n    printf "%d", int(pct + 0.5)\n  }\'\n}\n\nif [[ $shell_output == "true" ]]; then\n  printf \'percentage\\t%s\\n\' "${percentage}%"\n  if [[ $charge_holding == "true" ]]; then',
     'battery-status: compute_health helper'),
    ('  printf \'size\\t%s\\n\' "${capacity}Wh"\n  printf \'time\\t%s\\n\' "$time_remaining"\n\n  cycles=""\n  [[ ! -r $battery_path/cycle_count ]] || cycles=$(<"$battery_path/cycle_count")\n  [[ -n $cycles ]] || cycles=$(cat "$power_supply_path"/BAT*/cycle_count 2>/dev/null | head -1)',
     '  printf \'size\\t%s\\n\' "${capacity}Wh"\n  printf \'time\\t%s\\n\' "$time_remaining"\n\n  health=$(compute_health "$energy_full" "$energy_full_design" "$upower_capacity")\n  if [[ -z $health ]]; then\n    sysfs_full=$(read_sysfs_number "$battery_path/energy_full" || read_sysfs_number "$battery_path/charge_full" || true)\n    sysfs_design=$(read_sysfs_number "$battery_path/energy_full_design" || read_sysfs_number "$battery_path/charge_full_design" || true)\n    health=$(compute_health "$sysfs_full" "$sysfs_design" "")\n  fi\n  [[ -n $health ]] && printf \'health\\t%s\\n\' "${health}%"\n\n  cycles=""\n  [[ ! -r $battery_path/cycle_count ]] || cycles=$(<"$battery_path/cycle_count")\n  [[ -n $cycles ]] || cycles=$(cat "$power_supply_path"/BAT*/cycle_count 2>/dev/null | head -1)',
     'battery-status: health output'),
    ('    fi\n  fi\n\n  exit 0\nfi\n',
     '    fi\n  fi\n\n  # Charge limit control metadata for the power panel.\n  limit_supported=0\n  if [[ $upower_threshold_supported == "yes" || -r $battery_path/charge_control_end_threshold ]]; then\n    limit_supported=1\n  fi\n  printf \'limit_supported\\t%s\\n\' "$limit_supported"\n\n  if (( limit_supported == 1 )); then\n    limit_mode="threshold"\n    if [[ $upower_threshold_supported == "yes" && ! -r $battery_path/charge_control_end_threshold && -z $upower_threshold_end ]]; then\n      limit_mode="firmware"\n    fi\n\n    limit_state="off"\n    if [[ $upower_threshold_enabled == "yes" ]] || { [[ -n $threshold_end ]] && (( threshold_end < 100 )); }; then\n      limit_state="on"\n    elif [[ $limit_mode == "firmware" ]] && command -v busctl >/dev/null 2>&1; then\n      if [[ $(busctl get-property org.freedesktop.UPower "$battery" org.freedesktop.UPower.Device ChargeThresholdEnabled 2>/dev/null || true) == "b true" ]]; then\n        limit_state="on"\n      elif [[ -f $battery_state_dir/top-up-once ]]; then\n        limit_state="once"\n      fi\n    elif [[ -f $battery_state_dir/top-up-once ]]; then\n      limit_state="once"\n    fi\n\n    limit_end=$upower_threshold_end\n    [[ -n $limit_end ]] || limit_end=$threshold_end\n    if [[ -z $limit_end && $limit_mode == "threshold" ]]; then\n      limit_end=80\n    fi\n\n    printf \'limit_state\\t%s\\n\' "$limit_state"\n    printf \'limit_mode\\t%s\\n\' "$limit_mode"\n    [[ -n $limit_end ]] && printf \'limit_end\\t%s\\n\' "$limit_end"\n    [[ -n $upower_threshold_start ]] && printf \'limit_start\\t%s\\n\' "$upower_threshold_start"\n  fi\n\n  # Last sleep drain telemetry written by /usr/lib/systemd/system-sleep/hexciri-sleep-stats.\n  last_sleep_file="$sleep_run_dir/last-sleep"\n  if [[ -r $last_sleep_file ]]; then\n    s_mode="" s_dur="" s_ac="0" s_dpct="" s_pct_hr="" s_w="" s_s0ix=""\n    while IFS=$\'\\t\' read -r key val; do\n      case "$key" in\n        mode) s_mode=$val ;;\n        duration_s) s_dur=$val ;;\n        ac_plugged) s_ac=$val ;;\n        delta_pct) s_dpct=$val ;;\n        drain_pct_hr) s_pct_hr=$val ;;\n        drain_w) s_w=$val ;;\n        s0ix_pct) s_s0ix=$val ;;\n      esac\n    done <"$last_sleep_file"\n\n    if [[ $s_ac == "0" && $s_dur =~ ^[0-9]+$ ]] && (( s_dur >= 300 )); then\n      s_minutes=$(( (s_dur + 30) / 60 ))\n      s_formatted=$(format_duration "$s_minutes")\n      if [[ -n $s_formatted ]]; then\n        printf \'sleep_duration\\t%s\\n\' "$s_formatted"\n        [[ -n $s_dpct ]] && printf \'sleep_drain_pct\\t%s%%\\n\' "$s_dpct"\n        [[ -n $s_pct_hr ]] && printf \'sleep_drain_pct_hr\\t%s%%/h\\n\' "$s_pct_hr"\n        [[ -n $s_w ]] && printf \'sleep_drain_w\\t%sW\\n\' "$s_w"\n        [[ -n $s_s0ix ]] && printf \'sleep_s0ix\\t%s%%\\n\' "$s_s0ix"\n        [[ -n $s_mode ]] && printf \'sleep_mode\\t%s\\n\' "$s_mode"\n      fi\n    fi\n  fi\n\n  exit 0\nfi\n',
     'battery-status: limit metadata + sleep drain output'),
]

try:
    with open(target, encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

applied = 0
for _old, _new, _label in REPLACEMENTS:
    text, _n = _apply(text, _old, _new, _label)
    applied += _n
if 'compute_health' not in text:
    _die("marker missing after edit: compute_health")
if 'limit_supported' not in text:
    _die("marker missing after edit: limit_supported")
if 'sleep_drain_pct_hr' not in text:
    _die("marker missing after edit: sleep_drain_pct_hr")
if 'energy_full_design' not in text:
    _die("marker missing after edit: energy_full_design")

with open(target, "w", encoding="utf-8") as f:
    f.write(text)

if applied:
    print("patched: %s (%d edits)" % (target, applied))
else:
    print("no changes: %s already patched" % target)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# --- 4. battery service model edits (shell/plugins/services/battery/BatteryModel.js) ---
step "battery service model edits"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 55 shell/plugins/services/battery/BatteryModel.js edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/shell/plugins/services/battery/BatteryModel.js"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _apply(text, old, new, label):
    """Replace old (exactly once) with new; skip if already applied."""
    if new == "":
        if old not in text:
            print("%s: already present, skipping" % label)
            return text, 0
    elif new in text:
        print("%s: already present, skipping" % label)
        return text, 0
    if text.count(old) != 1:
        _die("%s: anchor occurs %d times, want exactly 1" % (label, text.count(old)))
    return text.replace(old, new, 1), 1


REPLACEMENTS = [
    ('  return signalsAtStart === signalsNow ? parseActiveProfile(replyText) : current\n}\n\nif (typeof module !== "undefined") {\n  module.exports = {\n    batteryPercentage: batteryPercentage,\n    isDischarging: isDischarging,\n    shouldWarnLowBattery: shouldWarnLowBattery,\n    parseActiveProfile: parseActiveProfile,\n    profileAfterRead: profileAfterRead\n  }\n}',
     '  return signalsAtStart === signalsNow ? parseActiveProfile(replyText) : current\n}\n\n// Re-arm the hardware charge limit after a one-time top-up to 100% once the\n// battery finishes charging or external power is unplugged.\nfunction shouldRearmChargeLimit(topUpOnce, device, onBattery, wasOnBattery, fullyChargedState) {\n  if (!topUpOnce) return false\n  if (wasOnBattery === false && onBattery === true) return true\n  if (onBattery || !device || !device.isPresent) return false\n  return device.state === fullyChargedState || batteryPercentage(device) >= 100\n}\n\nif (typeof module !== "undefined") {\n  module.exports = {\n    batteryPercentage: batteryPercentage,\n    isDischarging: isDischarging,\n    shouldWarnLowBattery: shouldWarnLowBattery,\n    parseActiveProfile: parseActiveProfile,\n    profileAfterRead: profileAfterRead,\n    shouldRearmChargeLimit: shouldRearmChargeLimit\n  }\n}',
     'BatteryModel: shouldRearmChargeLimit'),
]

try:
    with open(target, encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

applied = 0
for _old, _new, _label in REPLACEMENTS:
    text, _n = _apply(text, _old, _new, _label)
    applied += _n
if 'shouldRearmChargeLimit' not in text:
    _die("marker missing after edit: shouldRearmChargeLimit")

with open(target, "w", encoding="utf-8") as f:
    f.write(text)

if applied:
    print("patched: %s (%d edits)" % (target, applied))
else:
    print("no changes: %s already patched" % target)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

node --check "$FORK_OUT/shell/plugins/services/battery/BatteryModel.js" || die "node --check failed on shell/plugins/services/battery/BatteryModel.js"

# --- 5. battery service edits (shell/plugins/services/battery/Service.qml) ---
step "battery service edits"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 55 shell/plugins/services/battery/Service.qml edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/shell/plugins/services/battery/Service.qml"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _apply(text, old, new, label):
    """Replace old (exactly once) with new; skip if already applied."""
    if new == "":
        if old not in text:
            print("%s: already present, skipping" % label)
            return text, 0
    elif new in text:
        print("%s: already present, skipping" % label)
        return text, 0
    if text.count(old) != 1:
        _die("%s: anchor occurs %d times, want exactly 1" % (label, text.count(old)))
    return text.replace(old, new, 1), 1


REPLACEMENTS = [
    ('  property bool powerProfileReadPending: false\n  property int powerProfileSignals: 0\n  property int powerProfileReadSignals: 0\n\n  PersistentProperties {\n    id: persisted',
     '  property bool powerProfileReadPending: false\n  property int powerProfileSignals: 0\n  property int powerProfileReadSignals: 0\n  property int chargeLimitSignals: 0\n  property bool lastOnBattery: UPower.onBattery\n\n  readonly property string topUpOncePath: {\n    var stateHome = Quickshell.env("XDG_STATE_HOME")\n    if (!stateHome) stateHome = Quickshell.env("HOME") + "/.local/state"\n    return stateHome + "/hexciri/battery/top-up-once"\n  }\n  readonly property bool topUpOnce: topUpOnceFile.text.trim().length > 0\n  onTopUpOnceChanged: if (topUpOnce) checkTopUpOnceRearm()\n\n  PersistentProperties {\n    id: persisted',
     'battery service: charge-limit state + top-up-once file'),
    ('    property bool notifiedLowBattery: false\n  }\n\n  function batteryPercentage() {\n    return BatteryModel.batteryPercentage(UPower.displayDevice)\n  }',
     '    property bool notifiedLowBattery: false\n  }\n\n  WatchedFile {\n    id: topUpOnceFile\n    path: root.topUpOncePath\n  }\n\n  function batteryPercentage() {\n    return BatteryModel.batteryPercentage(UPower.displayDevice)\n  }',
     'battery service: watch top-up-once marker'),
    ('    powerProfileReadProcess.running = true\n  }\n\n  function profileName(profile) {\n    switch (profile) {\n      case PowerProfile.PowerSaver: return "power-saver"',
     '    powerProfileReadProcess.running = true\n  }\n\n  function refreshChargeLimit() {\n    topUpOnceFile.reread()\n    chargeLimitSignals++\n    checkTopUpOnceRearm()\n  }\n\n  function rearmChargeLimit() {\n    if (chargeLimitProcess.running) return\n    chargeLimitProcess.command = ["hexciri-battery-limit", "on"]\n    chargeLimitProcess.running = true\n  }\n\n  function checkTopUpOnceRearm() {\n    if (!topUpOnce) return\n    if (BatteryModel.shouldRearmChargeLimit(topUpOnce, UPower.displayDevice, UPower.onBattery, UPower.onBattery, UPowerDeviceState.FullyCharged))\n      rearmChargeLimit()\n  }\n\n  function profileName(profile) {\n    switch (profile) {\n      case PowerProfile.PowerSaver: return "power-saver"',
     'battery service: refresh/rearm/checkTopUpOnceRearm'),
    ('\n  Process { id: warningProcess }\n\n  Process {\n    id: powerProfileProcess\n    onExited: {',
     "\n  Process { id: warningProcess }\n\n  Process {\n    id: chargeLimitProcess\n    onExited: root.refreshChargeLimit()\n  }\n\n  // Wait briefly on unplug before re-arming a one-time top-up so USB-C PD\n  // power-role renegotiation glitches don't cancel a charge early.\n  Timer {\n    id: topUpRearmDebounce\n    interval: 2000\n    onTriggered: {\n      if (root.topUpOnce && UPower.onBattery) root.rearmChargeLimit()\n    }\n  }\n\n  Process {\n    id: powerProfileProcess\n    onExited: {",
     'battery service: charge-limit process + rearm debounce'),
    ('    target: "battery"\n\n    function refreshPowerProfile(): void { root.refreshPowerProfile() }\n  }\n\n  Timer {',
     '    target: "battery"\n\n    function refreshPowerProfile(): void { root.refreshPowerProfile() }\n    function refreshChargeLimit(): void { root.refreshChargeLimit() }\n  }\n\n  Timer {',
     'battery service: IPC refreshChargeLimit'),
    ('  Connections {\n    target: UPower\n    function onOnBatteryChanged() {\n      root.checkBattery()\n      root.applyPowerProfile()\n      root.refreshPowerProfile()\n    }\n  }\n\n  Component.onCompleted: root.refreshPowerProfile()\n}',
     '  Connections {\n    target: UPower\n    function onOnBatteryChanged() {\n      var wasOnBattery = root.lastOnBattery\n      root.lastOnBattery = UPower.onBattery\n      root.checkBattery()\n      root.applyPowerProfile()\n      root.refreshPowerProfile()\n      if (root.topUpOnce) {\n        if (!wasOnBattery && UPower.onBattery) topUpRearmDebounce.restart()\n        else if (!UPower.onBattery) {\n          topUpRearmDebounce.stop()\n          root.checkTopUpOnceRearm()\n        }\n      }\n    }\n  }\n\n  Connections {\n    target: UPower.displayDevice\n    function onStateChanged() { root.checkTopUpOnceRearm() }\n    function onPercentageChanged() { root.checkTopUpOnceRearm() }\n  }\n\n  Component.onCompleted: {\n    root.refreshPowerProfile()\n    root.checkTopUpOnceRearm()\n  }\n}',
     'battery service: rearm on unplug/state change'),
]

try:
    with open(target, encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

applied = 0
for _old, _new, _label in REPLACEMENTS:
    text, _n = _apply(text, _old, _new, _label)
    applied += _n
if 'topUpOnceFile' not in text:
    _die("marker missing after edit: topUpOnceFile")
if 'refreshChargeLimit' not in text:
    _die("marker missing after edit: refreshChargeLimit")
if 'chargeLimitProcess' not in text:
    _die("marker missing after edit: chargeLimitProcess")
if 'topUpRearmDebounce' not in text:
    _die("marker missing after edit: topUpRearmDebounce")

with open(target, "w", encoding="utf-8") as f:
    f.write(text)

if applied:
    print("patched: %s (%d edits)" % (target, applied))
else:
    print("no changes: %s already patched" % target)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# --- 6. power panel model edits (shell/plugins/panels/power/Model.js) ---
step "power panel model edits"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 55 shell/plugins/panels/power/Model.js edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/shell/plugins/panels/power/Model.js"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _apply(text, old, new, label):
    """Replace old (exactly once) with new; skip if already applied."""
    if new == "":
        if old not in text:
            print("%s: already present, skipping" % label)
            return text, 0
    elif new in text:
        print("%s: already present, skipping" % label)
        return text, 0
    if text.count(old) != 1:
        _die("%s: anchor occurs %d times, want exactly 1" % (label, text.count(old)))
    return text.replace(old, new, 1), 1


REPLACEMENTS = [
    ('// rateFresh is false while the charge rate still dates from before external\n// power arrived. A battery that reports its rate every half minute reads\n// "charging at 0 W" until then, which is not a threshold holding it.\nfunction chargeThresholdActive(device, onBattery, states, rateFresh) {\n  var d = device || {}\n  var s = states || {}\n  if (!(d && d.isPresent && !onBattery)) return false',
     '// rateFresh is false while the charge rate still dates from before external\n// power arrived. A battery that reports its rate every half minute reads\n// "charging at 0 W" until then, which is not a threshold holding it.\nfunction chargeThresholdActive(device, onBattery, states, rateFresh, limitState) {\n  var d = device || {}\n  var s = states || {}\n  if (!(d && d.isPresent && !onBattery)) return false',
     'power Model: chargeThresholdActive takes limitState'),
    ('  if (d.state === s.FullyCharged && fraction < 0.99) return true\n  if (d.state !== s.Charging || fraction >= 0.99) return false\n  if (rateFresh === false) return false\n\n  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60\n}\n\nfunction batteryIcon(device, onBattery, states, rateFresh) {\n  var d = device || {}\n  if (!d.isPresent) return ""\n\n  var chargingIcons = ["\U000f089c", "\U000f0086", "\U000f0087", "\U000f0088", "\U000f089d", "\U000f0089", "\U000f089e", "\U000f008a", "\U000f008b", "\U000f0085"]\n  var defaultIcons = ["\U000f007a", "\U000f007b", "\U000f007c", "\U000f007d", "\U000f007e", "\U000f007f", "\U000f0080", "\U000f0081", "\U000f0082", "\U000f0079"]\n  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))\n  var threshold = chargeThresholdActive(d, onBattery, states, rateFresh)\n\n  if (threshold) return defaultIcons[index]\n  if (d.state === states.FullyCharged) return "\U000f0085"',
     '  if (d.state === s.FullyCharged && fraction < 0.99) return true\n  if (d.state !== s.Charging || fraction >= 0.99) return false\n  if (rateFresh === false) return false\n  if (limitState === "off" || limitState === "once") return false\n\n  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60\n}\n\nfunction batteryIcon(device, onBattery, states, rateFresh, limitState) {\n  var d = device || {}\n  if (!d.isPresent) return ""\n\n  var chargingIcons = ["\U000f089c", "\U000f0086", "\U000f0087", "\U000f0088", "\U000f089d", "\U000f0089", "\U000f089e", "\U000f008a", "\U000f008b", "\U000f0085"]\n  var defaultIcons = ["\U000f007a", "\U000f007b", "\U000f007c", "\U000f007d", "\U000f007e", "\U000f007f", "\U000f0080", "\U000f0081", "\U000f0082", "\U000f0079"]\n  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))\n  var threshold = chargeThresholdActive(d, onBattery, states, rateFresh, limitState)\n\n  if (threshold) return defaultIcons[index]\n  if (d.state === states.FullyCharged) return "\U000f0085"',
     'power Model: limit off/once never flags threshold + batteryIcon limitState'),
    ('  return defaultIcons[index]\n}\n\nfunction modeLabel(device, onBattery, states, tr, rateFresh) {\n  var t = typeof tr === "function" ? tr : function(key, english) { return english }\n  var d = device || {}\n  if (!d.isPresent) return ""\n\n  var percentage = d.isPresent ? d.percentage : 0\n  if (chargeThresholdActive(d, onBattery, states, rateFresh)) return t("power.threshold", "Threshold")\n  if (onBattery) return t("power.onBattery", "On battery")\n  if (!onBattery && percentage >= 1) return t("power.fullyCharged", "Fully charged")\n  return t("power.charging", "Charging")',
     '  return defaultIcons[index]\n}\n\nfunction modeLabel(device, onBattery, states, tr, rateFresh, limitState) {\n  var t = typeof tr === "function" ? tr : function(key, english) { return english }\n  var d = device || {}\n  if (!d.isPresent) return ""\n\n  var percentage = d.isPresent ? d.percentage : 0\n  if (chargeThresholdActive(d, onBattery, states, rateFresh, limitState)) return t("power.threshold", "Threshold")\n  if (onBattery) return t("power.onBattery", "On battery")\n  if (!onBattery && percentage >= 1) return t("power.fullyCharged", "Fully charged")\n  return t("power.charging", "Charging")',
     'power Model: modeLabel limitState'),
    ('  return value.charAt(0).toUpperCase() + value.slice(1)\n}\n\nif (typeof module !== "undefined") {\n  module.exports = {\n    clampIndex: clampIndex,',
     '  return value.charAt(0).toUpperCase() + value.slice(1)\n}\n\nfunction chargeLimitFraction(batteryInfo) {\n  var info = batteryInfo || {}\n  if (info.limit_mode === "firmware") return 0\n  var n = parseFloat(info.limit_end || "")\n  if (isNaN(n) || n <= 0 || n >= 100) return 0\n  return n / 100\n}\n\nfunction chargeLimitHeader(batteryInfo, tr, fmt) {\n  var t = typeof tr === "function" ? tr : function(key, english) { return english }\n  var info = batteryInfo || {}\n  var title = t("power.chargeLimitSection", "CHARGE LIMIT")\n  if (info.limit_mode === "firmware" || !info.limit_end) return title\n  return title + " · " + localizeReading(info.limit_end + "%", fmt)\n}\n\nfunction formatSleepShort(batteryInfo, fmt) {\n  var info = batteryInfo || {}\n  if (!info.sleep_duration) return ""\n  if (info.sleep_drain_pct_hr) return localizeReading(info.sleep_drain_pct_hr, fmt)\n  if (info.sleep_drain_w) return localizeReading(info.sleep_drain_w, fmt)\n  return info.sleep_duration\n}\n\nfunction formatSleepTooltip(batteryInfo, fmt) {\n  var info = batteryInfo || {}\n  if (!info.sleep_duration) return ""\n  var parts = [info.sleep_duration]\n  if (info.sleep_drain_pct) parts.push("−" + localizeReading(info.sleep_drain_pct, fmt))\n  if (info.sleep_drain_pct_hr) parts.push(localizeReading(info.sleep_drain_pct_hr, fmt))\n  if (info.sleep_drain_w) parts.push(localizeReading(info.sleep_drain_w, fmt))\n  if (info.sleep_mode === "s2idle" && info.sleep_s0ix) parts.push("S0ix " + localizeReading(info.sleep_s0ix, fmt))\n  return parts.join(" · ")\n}\n\nfunction isLowS0ix(batteryInfo) {\n  var info = batteryInfo || {}\n  if (info.sleep_mode !== "s2idle" || !info.sleep_s0ix) return false\n  var n = parseFloat(String(info.sleep_s0ix).replace("%", ""))\n  return !isNaN(n) && n < 80\n}\n\nfunction moveFocus(focusRow, profileIndex, dx, dy, hasLimit, hasTopUp, profileCount) {\n  var rows = []\n  if (hasLimit) rows.push("limit")\n  if (hasLimit && hasTopUp) rows.push("topup")\n  rows.push("profile")\n\n  var rowIdx = rows.indexOf(focusRow)\n  if (rowIdx < 0) rowIdx = rows.length - 1\n  var pIdx = clampIndex(profileIndex, profileCount)\n\n  if (dy !== 0) {\n    if (rows.length > 1) {\n      rowIdx = clampIndex(rowIdx + (dy > 0 ? 1 : -1), rows.length)\n      return { focusRow: rows[rowIdx], profileIndex: pIdx }\n    }\n    return { focusRow: "profile", profileIndex: clampIndex(pIdx + dy, profileCount) }\n  }\n\n  if (dx !== 0 && rows[rowIdx] === "profile") {\n    pIdx = clampIndex(pIdx + dx, profileCount)\n  }\n  return { focusRow: rows[rowIdx], profileIndex: pIdx }\n}\n\nif (typeof module !== "undefined") {\n  module.exports = {\n    clampIndex: clampIndex,',
     'power Model: charge-limit + sleep + moveFocus helpers'),
    ('    batteryIcon: batteryIcon,\n    modeLabel: modeLabel,\n    profileLabel: profileLabel,\n    localizeReading: localizeReading\n  }\n}',
     '    batteryIcon: batteryIcon,\n    modeLabel: modeLabel,\n    profileLabel: profileLabel,\n    localizeReading: localizeReading,\n    chargeLimitFraction: chargeLimitFraction,\n    chargeLimitHeader: chargeLimitHeader,\n    formatSleepShort: formatSleepShort,\n    formatSleepTooltip: formatSleepTooltip,\n    isLowS0ix: isLowS0ix,\n    moveFocus: moveFocus\n  }\n}',
     'power Model: export new helpers'),
]

try:
    with open(target, encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

applied = 0
for _old, _new, _label in REPLACEMENTS:
    text, _n = _apply(text, _old, _new, _label)
    applied += _n
if 'chargeLimitFraction' not in text:
    _die("marker missing after edit: chargeLimitFraction")
if 'formatSleepTooltip' not in text:
    _die("marker missing after edit: formatSleepTooltip")
if 'isLowS0ix' not in text:
    _die("marker missing after edit: isLowS0ix")
if 'moveFocus' not in text:
    _die("marker missing after edit: moveFocus")

with open(target, "w", encoding="utf-8") as f:
    f.write(text)

if applied:
    print("patched: %s (%d edits)" % (target, applied))
else:
    print("no changes: %s already patched" % target)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

node --check "$FORK_OUT/shell/plugins/panels/power/Model.js" || die "node --check failed on shell/plugins/panels/power/Model.js"

# --- 7. power panel edits (shell/plugins/panels/power/Panel.qml) ---
step "power panel edits"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 55 shell/plugins/panels/power/Panel.qml edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/shell/plugins/panels/power/Panel.qml"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _apply(text, old, new, label):
    """Replace old (exactly once) with new; skip if already applied."""
    if new == "":
        if old not in text:
            print("%s: already present, skipping" % label)
            return text, 0
    elif new in text:
        print("%s: already present, skipping" % label)
        return text, 0
    if text.count(old) != 1:
        _die("%s: anchor occurs %d times, want exactly 1" % (label, text.count(old)))
    return text.replace(old, new, 1), 1


REPLACEMENTS = [
    ('  property int profileIndex: 0',
     '  property int profileIndex: 0\n  property string activeChargeLimit: ""\n  property string focusRow: "profile"\n  property string chargeLimitError: ""',
     'power panel: charge-limit state properties'),
    ('    var device = UPower.displayDevice\n    return !!(device && device.isPresent)\n  }\n\n  function upowerStates() {\n    return {',
     '    var device = UPower.displayDevice\n    return !!(device && device.isPresent)\n  }\n  readonly property bool chargeLimitSupported: root.batteryInfo.limit_supported === "1"\n  readonly property bool chargeLimitEnabled: root.activeChargeLimit === "on" || root.activeChargeLimit === "once"\n  readonly property real chargeLimitFraction: Model.chargeLimitFraction(root.batteryInfo)\n  readonly property string chargeLimitHeaderText: Model.chargeLimitHeader(root.batteryInfo, Commons.I18n.t, Commons.I18n.formatNumber)\n  readonly property bool showTopUpButton: root.chargeLimitSupported && root.chargeLimitEnabled\n  readonly property bool toppingUpOnce: root.chargeLimitSupported && root.activeChargeLimit === "once"\n  readonly property string sleepShort: Model.formatSleepShort(root.batteryInfo, Commons.I18n.formatNumber)\n  readonly property string sleepTooltip: Model.formatSleepTooltip(root.batteryInfo, Commons.I18n.formatNumber)\n  readonly property bool sleepLowS0ix: Model.isLowS0ix(root.batteryInfo)\n\n  function upowerStates() {\n    return {',
     'power panel: charge-limit/sleep derived properties'),
    ('    }\n  }\n\n  function selectProfileByDelta(delta) {\n    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)\n  }\n\n  function activateSelectedProfile() {\n    if (profileIndex < 0 || profileIndex >= profiles.length) return\n    setProfile(profiles[profileIndex])\n  }\n\n  function batteryIcon() {\n    var device = UPower.displayDevice\n    return Model.batteryIcon(device, root.discharging, upowerStates(), root.chargeRateFresh)\n  }\n\n  function modeLabel() {\n    var device = UPower.displayDevice\n    return Model.modeLabel(device, root.discharging, upowerStates(), Commons.I18n.t, root.chargeRateFresh)\n  }\n\n  function profileIcon(name) {',
     '    }\n  }\n\n  function moveCursor(dx, dy) {\n    var next = Model.moveFocus(\n      focusRow,\n      profileIndex,\n      dx,\n      dy,\n      chargeLimitSupported,\n      showTopUpButton,\n      profiles.length\n    )\n    focusRow = next.focusRow\n    profileIndex = next.profileIndex\n  }\n\n  function activateCursor() {\n    if (focusRow === "limit" && chargeLimitSupported) {\n      toggleChargeLimit()\n      return\n    }\n    if (focusRow === "topup" && showTopUpButton) {\n      toggleTopUpOnce()\n      return\n    }\n    if (profileIndex < 0 || profileIndex >= profiles.length) return\n    setProfile(profiles[profileIndex])\n  }\n\n  function batteryIcon() {\n    var device = UPower.displayDevice\n    return Model.batteryIcon(device, root.discharging, upowerStates(), root.chargeRateFresh, root.activeChargeLimit)\n  }\n\n  function modeLabel() {\n    var device = UPower.displayDevice\n    return Model.modeLabel(device, root.discharging, upowerStates(), Commons.I18n.t, root.chargeRateFresh, root.activeChargeLimit)\n  }\n\n  function profileIcon(name) {',
     'power panel: moveCursor/activateCursor replace profile-only cursor'),
    ('  }\n  readonly property bool chargeThresholdActive: {\n    var device = UPower.displayDevice\n    return Model.chargeThresholdActive(device, root.discharging, upowerStates(), root.chargeRateFresh)\n  }\n  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)\n  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive',
     '  }\n  readonly property bool chargeThresholdActive: {\n    var device = UPower.displayDevice\n    return Model.chargeThresholdActive(device, root.discharging, upowerStates(), root.chargeRateFresh, root.activeChargeLimit)\n  }\n  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)\n  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive',
     'power panel: chargeThresholdActive takes limitState'),
    ('  }\n\n  readonly property string heroStatusText: {\n    if (fullyCharged) return Commons.I18n.t("power.fullyCharged")\n    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]\n    return modeLabel()',
     '  }\n\n  readonly property string heroStatusText: {\n    if (chargeThresholdActive && batteryInfo.threshold)\n      return Commons.I18n.t("power.holdingAt").arg(root.reading(batteryInfo.threshold))\n    if (fullyCharged) return Commons.I18n.t("power.fullyCharged")\n    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]\n    return modeLabel()',
     'power panel: hero shows holding-at-limit'),
    ('    }\n  }\n\n  function refresh() {\n    if (!batteryPresent) return\n\n    if (!batteryProc.running) batteryProc.running = true\n    if (profiles.length === 0 && !profilesProc.running) profilesProc.running = true\n  }\n',
     '    }\n  }\n\n  property bool batteryRefreshPending: false\n\n  function refreshBatteryInfo() {\n    if (!batteryPresent) return\n    if (batteryProc.running) {\n      batteryRefreshPending = true\n      return\n    }\n    batteryRefreshPending = false\n    batteryProc.running = true\n  }\n\n  function refresh() {\n    if (!batteryPresent) return\n\n    refreshBatteryInfo()\n    if (profiles.length === 0 && !profilesProc.running) profilesProc.running = true\n  }\n',
     'power panel: refreshBatteryInfo + coalesced refresh'),
    ('    // around AC plug/unplug events. Avoids the section collapsing mid-transition.\n    if (Object.keys(next).length === 0) return\n    batteryInfo = next\n  }\n\n  function updateProfiles(raw) {',
     '    // around AC plug/unplug events. Avoids the section collapsing mid-transition.\n    if (Object.keys(next).length === 0) return\n    batteryInfo = next\n    if (!limitProc.running && next.limit_state) {\n      activeChargeLimit = next.limit_state\n    }\n    if (next.limit_supported !== "1" && focusRow !== "profile") {\n      focusRow = "profile"\n    } else if (focusRow === "topup" && !chargeLimitEnabled) {\n      focusRow = "limit"\n    }\n  }\n\n  function updateProfiles(raw) {',
     'power panel: track limit_state + focus rows on refresh'),
    ('    actionProc.running = true\n  }\n\n  function togglePercentage() {\n    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })\n    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)',
     '    actionProc.running = true\n  }\n\n  function setChargeLimit(mode) {\n    if (!mode || limitProc.running || !chargeLimitSupported) return\n    chargeLimitError = ""\n    activeChargeLimit = mode\n    if (mode === "off" && focusRow === "topup") focusRow = "limit"\n    limitProc.command = ["hexciri-battery-limit", mode]\n    limitProc.running = true\n  }\n\n  function toggleChargeLimit() {\n    setChargeLimit(chargeLimitEnabled ? "off" : "on")\n  }\n\n  function toggleTopUpOnce() {\n    setChargeLimit(toppingUpOnce ? "on" : "once")\n  }\n\n  function togglePercentage() {\n    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })\n    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)',
     'power panel: set/toggle charge limit + top-up once'),
    ('\n      if (batteryService && batteryService.activePowerProfile)\n        syncActiveProfile(batteryService.activePowerProfile)\n      refresh()\n      var idx = profiles.indexOf(activeProfile)\n      profileIndex = idx >= 0 ? idx : 0\n      cursorActive = false\n    }\n  }',
     '\n      if (batteryService && batteryService.activePowerProfile)\n        syncActiveProfile(batteryService.activePowerProfile)\n      chargeLimitError = ""\n      refresh()\n      var idx = profiles.indexOf(activeProfile)\n      profileIndex = idx >= 0 ? idx : 0\n      focusRow = "profile"\n      cursorActive = false\n    }\n  }',
     'power panel: reset limit error + focus on open'),
    ('    function onActivePowerProfileChanged() {\n      if (root.batteryService) root.syncActiveProfile(root.batteryService.activePowerProfile)\n    }\n  }\n\n  Process {\n    id: batteryProc\n    command: ["hexciri-battery-status", "--shell"]\n    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBatteryInfo(text) }\n  }\n\n  Process {',
     '    function onActivePowerProfileChanged() {\n      if (root.batteryService) root.syncActiveProfile(root.batteryService.activePowerProfile)\n    }\n    function onChargeLimitSignalsChanged() {\n      if (root.opened) root.refresh()\n      else root.refreshBatteryInfo()\n    }\n  }\n\n  Process {\n    id: batteryProc\n    command: ["hexciri-battery-status", "--shell"]\n    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBatteryInfo(text) }\n    onExited: {\n      if (root.batteryRefreshPending) Qt.callLater(root.refreshBatteryInfo)\n    }\n  }\n\n  Process {',
     'power panel: refresh on charge-limit signals'),
    ("    }\n  }\n\n  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }\n\n  // Rotate the status phrase while the panel is open and we're in a",
     '    }\n  }\n\n  Process {\n    id: limitProc\n    onExited: function(exitCode) {\n      if (exitCode !== 0) {\n        root.chargeLimitError = Commons.I18n.t("power.chargeLimitFailed")\n      } else {\n        root.chargeLimitError = ""\n      }\n      root.refreshBatteryInfo()\n    }\n  }\n\n  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }\n\n  // Rotate the status phrase while the panel is open and we\'re in a',
     'power panel: limit process + error text'),
    ('      implicitHeight: column.implicitHeight\n      onMoveRequested: function(dx, dy) {\n        if (!root.cursorActive) { root.cursorActive = true; return }\n        if (dx !== 0) root.selectProfileByDelta(dx)\n        else if (dy !== 0) root.selectProfileByDelta(dy)\n      }\n      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()\n      onCloseRequested: root.close()\n      onTabRequested: function(direction) { root.switchPanel(direction) }\n',
     '      implicitHeight: column.implicitHeight\n      onMoveRequested: function(dx, dy) {\n        if (!root.cursorActive) { root.cursorActive = true; return }\n        root.moveCursor(dx, dy)\n      }\n      onActivateRequested: if (root.cursorActive) root.activateCursor()\n      onCloseRequested: root.close()\n      onTabRequested: function(direction) { root.switchPanel(direction) }\n',
     'power panel: keyboard cursor moves across rows'),
    ('          }\n        }\n\n        // ---------- Battery progress bar ----------\n        Item {\n          width: parent.width\n          implicitHeight: Style.space(8)\n\n          Rectangle {\n            id: barTrack\n            anchors.fill: parent\n            radius: height / 2\n            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)\n          }',
     '          }\n        }\n\n        // ---------- Battery progress bar (+ optional charge limit tick) ----------\n        Item {\n          width: parent.width\n          implicitHeight: Style.space(12)\n\n          Rectangle {\n            id: barTrack\n            anchors.left: parent.left\n            anchors.right: parent.right\n            anchors.verticalCenter: parent.verticalCenter\n            height: Style.space(8)\n            radius: height / 2\n            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)\n          }',
     'power panel: charge-limit tick on progress bar'),
    ('              NumberAnimation { from: 0.55; to: 1.0; duration: Style.duration(950); easing.type: Easing.InOutSine }\n            }\n          }\n        }\n\n        // ---------- Stats ----------\n        // Visibility is intentionally only gated by "we\'ve ever loaded data" so\n        // the section never collapses mid-transition. fullyCharged is *not* part\n        // of the condition: UPower briefly reports FullyCharged on plug-in when\n        // the battery sits above the charge-control start threshold, and we\n        // refuse to flicker the whole panel for that ~1s window.\n        Row {\n          visible: root.batteryInfo.percentage !== undefined\n          width: parent.width\n          spacing: Style.space(20)\n\n          Column {\n            width: (parent.width - parent.spacing) / 2\n            spacing: Style.spacing.labelGap\n            InfoPair { label: Commons.I18n.t("power.batterySize"); value: root.reading(root.batteryInfo.size) }\n            InfoPair { label: Commons.I18n.t("power.chargeCycles"); value: root.reading(root.batteryInfo.cycles) || "—" }\n          }\n\n          Column {\n            width: (parent.width - parent.spacing) / 2\n            spacing: Style.spacing.labelGap\n            InfoPair {\n              label: root.chargeThresholdActive ? Commons.I18n.t("power.chargeLimit") : (root.discharging ? Commons.I18n.t("power.timeLeft") : Commons.I18n.t("power.timeToFull"))\n              value: root.chargeThresholdActive ? (root.reading(root.batteryInfo.threshold) || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))\n            }\n            InfoPair {\n              label: root.chargeThresholdActive ? Commons.I18n.t("power.batteryState") : (root.discharging ? Commons.I18n.t("power.discharging") : Commons.I18n.t("power.charging"))\n              value: root.chargeThresholdActive ? Commons.I18n.t("power.holding") : (root.batteryFull ? "-" : root.reading(root.batteryInfo.rate))\n            }\n          }\n        }\n',
     '              NumberAnimation { from: 0.55; to: 1.0; duration: Style.duration(950); easing.type: Easing.InOutSine }\n            }\n          }\n\n          // Mark the charge limit stop directly on the bar when actively enforcing it.\n          Rectangle {\n            visible: opacity > 0\n            width: Math.max(2, Style.space(2))\n            height: barTrack.height + Style.space(4)\n            radius: 1\n            x: Math.round(barTrack.width * (LayoutMirroring.enabled ? 1 - root.chargeLimitFraction : root.chargeLimitFraction)) - width / 2\n            anchors.verticalCenter: barTrack.verticalCenter\n            color: root.bar.foreground\n            opacity: root.chargeLimitFraction > 0 && root.activeChargeLimit === "on" ? 0.65 : 0\n\n            Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }\n          }\n        }\n\n        // ---------- Stats (balanced 3×3 + optional shallow-sleep warning) ----------\n        // Visibility is intentionally only gated by "we\'ve ever loaded data" so\n        // the section never collapses mid-transition. fullyCharged is *not* part\n        // of the condition: UPower briefly reports FullyCharged on plug-in when\n        // the battery sits above the charge-control start threshold, and we\n        // refuse to flicker the whole panel for that ~1s window.\n        Column {\n          visible: root.batteryInfo.percentage !== undefined\n          width: parent.width\n          spacing: Style.space(8)\n\n          Row {\n            width: parent.width\n            spacing: Style.space(20)\n\n            Column {\n              width: (parent.width - parent.spacing) / 2\n              spacing: Style.spacing.labelGap\n              InfoPair { label: Commons.I18n.t("power.batterySize"); value: root.reading(root.batteryInfo.size) }\n              InfoPair {\n                visible: !!root.batteryInfo.health\n                label: Commons.I18n.t("power.batteryHealth")\n                value: root.reading(root.batteryInfo.health)\n              }\n              InfoPair { label: Commons.I18n.t("power.chargeCycles"); value: root.reading(root.batteryInfo.cycles) || "—" }\n            }\n\n            Column {\n              width: (parent.width - parent.spacing) / 2\n              spacing: Style.spacing.labelGap\n              InfoPair {\n                label: root.chargeThresholdActive ? Commons.I18n.t("power.chargeLimit") : (root.discharging ? Commons.I18n.t("power.timeLeft") : Commons.I18n.t("power.timeToFull"))\n                value: root.chargeThresholdActive ? (root.reading(root.batteryInfo.threshold) || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))\n              }\n              InfoPair {\n                label: root.chargeThresholdActive ? Commons.I18n.t("power.batteryState") : (root.discharging ? Commons.I18n.t("power.discharging") : Commons.I18n.t("power.charging"))\n                value: root.chargeThresholdActive ? Commons.I18n.t("power.holding") : (root.batteryFull ? "-" : root.reading(root.batteryInfo.rate))\n              }\n              Item {\n                visible: root.sleepShort !== ""\n                width: parent.width\n                implicitHeight: sleepPair.implicitHeight\n\n                InfoPair {\n                  id: sleepPair\n                  label: Commons.I18n.t("power.lastSleep")\n                  value: root.sleepShort\n                  valueColor: root.sleepLowS0ix ? Commons.Color.warning : root.bar.foreground\n                }\n\n                MouseArea {\n                  id: sleepMouse\n                  anchors.fill: parent\n                  hoverEnabled: true\n                }\n\n                PanelToolTip {\n                  visible: root.sleepTooltip !== "" && sleepMouse.containsMouse\n                  text: root.sleepTooltip\n                  fontFamily: root.bar.fontFamily\n                }\n              }\n            }\n          }\n\n          Row {\n            visible: root.sleepLowS0ix\n            width: parent.width\n            spacing: Style.space(6)\n\n            Text {\n              id: s0ixWarnIcon\n              text: "\U000f0026"\n              textFormat: Text.PlainText\n              color: Commons.Color.warning\n              font.family: root.bar.fontFamily\n              font.pixelSize: Style.font.caption\n              anchors.verticalCenter: parent.verticalCenter\n            }\n\n            Text {\n              text: Commons.I18n.t("power.shallowSleep").arg(root.reading(root.batteryInfo.sleep_s0ix))\n              textFormat: Text.PlainText\n              color: Commons.Color.warning\n              font.family: root.bar.fontFamily\n              font.pixelSize: Style.font.caption\n              elide: Text.ElideRight\n              width: parent.width - s0ixWarnIcon.implicitWidth - parent.spacing\n              anchors.verticalCenter: parent.verticalCenter\n            }\n          }\n        }\n\n        // ---------- Charge limit toggle (+ contextual one-time top-up) ----------\n        PanelSeparator {\n          visible: root.chargeLimitSupported\n          foreground: root.bar.foreground\n        }\n\n        Column {\n          visible: root.chargeLimitSupported\n          width: parent.width\n          spacing: Style.space(10)\n\n          Item {\n            width: parent.width\n            implicitHeight: Math.max(limitHeader.implicitHeight, limitSwitch.implicitHeight)\n\n            PanelSectionHeader {\n              id: limitHeader\n              text: root.chargeLimitHeaderText\n              foreground: root.bar.foreground\n              fontFamily: root.bar.fontFamily\n              anchors.left: parent.left\n              anchors.right: limitSwitch.left\n              anchors.rightMargin: Style.space(8)\n              anchors.verticalCenter: parent.verticalCenter\n            }\n\n            // Sized off the header label and centered on its glyphs (same as\n            // the Wi-Fi band Automatic switch) so it reads as part of the header.\n            ToggleSwitch {\n              id: limitSwitch\n              checked: root.chargeLimitEnabled\n              busy: limitProc.running\n              trackHeight: Math.round(limitHeader.font.pixelSize * 1.2)\n              cursorPad: Style.space(3)\n              hasCursor: root.cursorActive && root.focusRow === "limit"\n              foreground: root.bar.foreground\n              anchors.right: parent.right\n              anchors.verticalCenter: limitHeader.verticalCenter\n              anchors.verticalCenterOffset: Math.round(limitHeader.topPadding / 2)\n              onHovered: function(h) {\n                if (h) {\n                  root.cursorActive = true\n                  root.focusRow = "limit"\n                }\n              }\n              onToggled: root.toggleChargeLimit()\n            }\n          }\n\n          // Collapsing container matching the Wi-Fi band pills so toggling the\n          // charge limit smoothly slides the section below instead of snapping.\n          // Mirrors the header switch row above so idle vs armed reads clearly\n          // as toggleable state with zero alignment shift.\n          Item {\n            id: topUpClip\n            width: parent.width\n            // Clip only while collapsing/expanding so topUpSwitch\'s outer cursor\n            // ring isn\'t trimmed along the right/vertical edges at rest.\n            clip: height < topUpRow.implicitHeight\n            visible: height > 0\n            height: root.showTopUpButton ? topUpRow.implicitHeight : 0\n            opacity: root.showTopUpButton ? 1 : 0\n\n            Behavior on height {\n              NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }\n            }\n            Behavior on opacity {\n              NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }\n            }\n\n            Item {\n              id: topUpRow\n              width: parent.width\n              implicitHeight: Math.max(topUpLabelRow.implicitHeight, topUpSwitch.implicitHeight)\n              readonly property color tone: root.toppingUpOnce\n                ? Style.selectedStateColor(root.bar.foreground, Commons.Color.accent)\n                : Qt.darker(root.bar.foreground, 1.25)\n\n              Row {\n                id: topUpLabelRow\n                anchors.left: parent.left\n                anchors.right: topUpSwitch.left\n                anchors.rightMargin: Style.space(8)\n                anchors.verticalCenter: parent.verticalCenter\n                spacing: Style.space(6)\n\n                Text {\n                  id: topUpIcon\n                  text: "\U000f0084"\n                  textFormat: Text.PlainText\n                  color: topUpRow.tone\n                  font.family: root.bar.fontFamily\n                  font.pixelSize: Math.round(Style.font.bodySmall * 1.2)\n                  anchors.verticalCenter: parent.verticalCenter\n\n                  Behavior on color { ColorAnimation { duration: Style.duration(120) } }\n                }\n\n                Text {\n                  text: !root.toppingUpOnce\n                    ? Commons.I18n.t("power.topUpOnce")\n                    : (root.discharging ? Commons.I18n.t("power.toppingUpNext") : Commons.I18n.t("power.toppingUpOnce"))\n                  textFormat: Text.PlainText\n                  color: topUpRow.tone\n                  font.family: root.bar.fontFamily\n                  font.pixelSize: Style.font.bodySmall\n                  font.bold: root.toppingUpOnce\n                  elide: Text.ElideRight\n                  width: parent.width - topUpIcon.implicitWidth - parent.spacing\n                  anchors.verticalCenter: parent.verticalCenter\n\n                  Behavior on color { ColorAnimation { duration: Style.duration(120) } }\n                }\n              }\n\n              ToggleSwitch {\n                id: topUpSwitch\n                checked: root.toppingUpOnce\n                busy: limitProc.running\n                interactive: false\n                cursorRing: true\n                trackHeight: Math.round(limitHeader.font.pixelSize * 1.2)\n                cursorPad: Style.space(3)\n                hasCursor: root.cursorActive && root.focusRow === "topup"\n                foreground: root.bar.foreground\n                anchors.right: parent.right\n                anchors.verticalCenter: parent.verticalCenter\n              }\n\n              MouseArea {\n                anchors.fill: parent\n                hoverEnabled: true\n                cursorShape: Qt.PointingHandCursor\n                onContainsMouseChanged: {\n                  if (containsMouse) {\n                    root.cursorActive = true\n                    root.focusRow = "topup"\n                  }\n                }\n                onClicked: root.toggleTopUpOnce()\n              }\n            }\n          }\n\n          Text {\n            visible: root.chargeLimitError !== ""\n            text: root.chargeLimitError\n            textFormat: Text.PlainText\n            color: Commons.Color.urgent\n            font.family: root.bar.fontFamily\n            font.pixelSize: Style.font.caption\n            elide: Text.ElideRight\n            width: parent.width\n          }\n        }\n',
     'power panel: stats 3x3 + sleep + charge-limit section'),
    ('                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)\n                bordered: true\n                active: root.activeProfile === modelData\n                hasCursor: root.cursorActive && root.profileIndex === index\n                onClicked: root.setProfile(modelData)\n                onHovered: function(h) {\n                  if (h) {\n                    root.cursorActive = true\n                    root.profileIndex = index\n                  }\n                }',
     '                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)\n                bordered: true\n                active: root.activeProfile === modelData\n                hasCursor: root.cursorActive && root.focusRow === "profile" && root.profileIndex === index\n                onClicked: root.setProfile(modelData)\n                onHovered: function(h) {\n                  if (h) {\n                    root.cursorActive = true\n                    root.focusRow = "profile"\n                    root.profileIndex = index\n                  }\n                }',
     'power panel: profile buttons need focusRow for cursor'),
    ('  component InfoPair: Row {\n    property string label: ""\n    property string value: ""\n\n    width: parent.width\n    spacing: Style.space(8)\n\n    InfoLabel { text: label }\n    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }\n    InfoValue { text: value }\n  }\n\n  component InfoLabel: Text {',
     '  component InfoPair: Row {\n    property string label: ""\n    property string value: ""\n    property color valueColor: root.bar.foreground\n\n    width: parent.width\n    spacing: Style.space(8)\n\n    InfoLabel { text: label }\n    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }\n    InfoValue { text: value; color: valueColor }\n  }\n\n  component InfoLabel: Text {',
     'power panel: InfoPair valueColor for sleep warning'),
]

try:
    with open(target, encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

applied = 0
for _old, _new, _label in REPLACEMENTS:
    text, _n = _apply(text, _old, _new, _label)
    applied += _n
if 'activeChargeLimit' not in text:
    _die("marker missing after edit: activeChargeLimit")
if 'chargeLimitSupported' not in text:
    _die("marker missing after edit: chargeLimitSupported")
if 'limitProc' not in text:
    _die("marker missing after edit: limitProc")
if 'showTopUpButton' not in text:
    _die("marker missing after edit: showTopUpButton")
if 'sleepShort' not in text:
    _die("marker missing after edit: sleepShort")
if 'moveCursor' not in text:
    _die("marker missing after edit: moveCursor")
if 'toggleTopUpOnce' not in text:
    _die("marker missing after edit: toggleTopUpOnce")

with open(target, "w", encoding="utf-8") as f:
    f.write(text)

if applied:
    print("patched: %s (%d edits)" % (target, applied))
else:
    print("no changes: %s already patched" % target)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# --- 8. ToggleSwitch edits (shell/Ui/ToggleSwitch.qml) ---
step "ToggleSwitch edits"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 55 shell/Ui/ToggleSwitch.qml edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/shell/Ui/ToggleSwitch.qml"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _apply(text, old, new, label):
    """Replace old (exactly once) with new; skip if already applied."""
    if new == "":
        if old not in text:
            print("%s: already present, skipping" % label)
            return text, 0
    elif new in text:
        print("%s: already present, skipping" % label)
        return text, 0
    if text.count(old) != 1:
        _die("%s: anchor occurs %d times, want exactly 1" % (label, text.count(old)))
    return text.replace(old, new, 1), 1


REPLACEMENTS = [
    ('  // already above its floor, so nothing about the normal switch changes.\n  property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))\n  property int trackWidth: Math.round(trackHeight * 1.9)\n  property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))\n  property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))\n\n  readonly property int _pad: cursorRing ? cursorPad : 0\n',
     '  // already above its floor, so nothing about the normal switch changes.\n  property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))\n  property int trackWidth: Math.round(trackHeight * 1.9)\n  // Derive knobSize from trackHeight - 2 * knobInset so top/bottom/left/right\n  // gaps are always exact integers and the knob never touches the track border\n  // at compact header sizes (e.g. 12–14px trackHeight).\n  property int knobInset: Math.max(\n    Math.ceil(Math.max(track.borderTop, 1)) + 1,\n    Math.round((trackHeight - Math.round(trackHeight * 0.72)) / 2)\n  )\n  property int knobSize: Math.max(4, trackHeight - knobInset * 2)\n\n  readonly property int _pad: cursorRing ? cursorPad : 0\n',
     'ToggleSwitch: exact-integer knob geometry'),
    ('      height: root.knobSize\n      radius: root.rounded ? height / 2 : 0\n      x: root.checked !== root.mirrored ? track.width - width - root.knobInset : root.knobInset\n      anchors.verticalCenter: parent.verticalCenter\n      color: root.checked ? Style.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)\n\n      Behavior on x { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }',
     '      height: root.knobSize\n      radius: root.rounded ? height / 2 : 0\n      x: root.checked !== root.mirrored ? track.width - width - root.knobInset : root.knobInset\n      y: root.knobInset\n      color: root.checked ? Style.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)\n\n      Behavior on x { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }',
     'ToggleSwitch: knob y follows inset, not centering'),
]

try:
    with open(target, encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

applied = 0
for _old, _new, _label in REPLACEMENTS:
    text, _n = _apply(text, _old, _new, _label)
    applied += _n
if 'knobSize: Math.max(4, trackHeight - knobInset * 2)' not in text:
    _die("marker missing after edit: knobSize: Math.max(4, trackHeight - knobInset * 2)")
if 'y: root.knobInset' not in text:
    _die("marker missing after edit: y: root.knobInset")

with open(target, "w", encoding="utf-8") as f:
    f.write(text)

if applied:
    print("patched: %s (%d edits)" % (target, applied))
else:
    print("no changes: %s already patched" % target)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# --- 9. i18n edits (default/i18n/en/shell.json) ---
step "i18n edits"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 55 default/i18n/en/shell.json edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/default/i18n/en/shell.json"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _apply(text, old, new, label):
    """Replace old (exactly once) with new; skip if already applied."""
    if new == "":
        if old not in text:
            print("%s: already present, skipping" % label)
            return text, 0
    elif new in text:
        print("%s: already present, skipping" % label)
        return text, 0
    if text.count(old) != 1:
        _die("%s: anchor occurs %d times, want exactly 1" % (label, text.count(old)))
    return text.replace(old, new, 1), 1


REPLACEMENTS = [
    ('  "power.battery": "Battery",',
     '  "power.battery": "Battery",\n  "power.batteryHealth": "Battery health",',
     'i18n: battery-health + charge-limit keys'),
    ('  "power.chargeLimit": "Charge limit",',
     '  "power.chargeLimit": "Charge limit",\n  "power.chargeLimitFailed": "Could not update charge limit",\n  "power.chargeLimitSection": "CHARGE LIMIT",',
     'i18n: battery-health + charge-limit keys'),
    ('  "power.dischargingPhrase9": "Munching reserves",\n  "power.fullyCharged": "Fully charged",\n  "power.holding": "Holding",\n  "power.onBattery": "On battery",\n  "power.powerProfile": "POWER PROFILE",\n  "power.profileBalanced": "Balanced",\n  "power.profilePerformance": "Performance",\n  "power.profilePowerSaver": "Power-saver",\n  "power.threshold": "Threshold",\n  "power.timeLeft": "Time left",\n  "power.timeToFull": "Time to full",\n  "reminders.invalidBody": "Enter the number of minutes",\n  "reminders.invalidTitle": "Invalid reminder",\n  "reminders.messagePrompt": "Reminder message...",',
     '  "power.dischargingPhrase9": "Munching reserves",\n  "power.fullyCharged": "Fully charged",\n  "power.holding": "Holding",\n  "power.holdingAt": "Holding at %1",\n  "power.lastSleep": "Last sleep",\n  "power.onBattery": "On battery",\n  "power.powerProfile": "POWER PROFILE",\n  "power.profileBalanced": "Balanced",\n  "power.profilePerformance": "Performance",\n  "power.profilePowerSaver": "Power-saver",\n  "power.shallowSleep": "Last sleep stayed shallow (S0ix %1)",\n  "power.threshold": "Threshold",\n  "power.timeLeft": "Time left",\n  "power.timeToFull": "Time to full",\n  "power.topUpOnce": "Top up to 100% once",\n  "power.toppingUpNext": "Next charge goes to 100%",\n  "power.toppingUpOnce": "Charging to 100% once",\n  "reminders.invalidBody": "Enter the number of minutes",\n  "reminders.invalidTitle": "Invalid reminder",\n  "reminders.messagePrompt": "Reminder message...",',
     'i18n: holding/last-sleep/shallow-sleep/top-up keys'),
]

try:
    with open(target, encoding="utf-8") as f:
        text = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

applied = 0
for _old, _new, _label in REPLACEMENTS:
    text, _n = _apply(text, _old, _new, _label)
    applied += _n
if 'power.batteryHealth' not in text:
    _die("marker missing after edit: power.batteryHealth")
if 'power.topUpOnce' not in text:
    _die("marker missing after edit: power.topUpOnce")
if 'power.shallowSleep' not in text:
    _die("marker missing after edit: power.shallowSleep")

with open(target, "w", encoding="utf-8") as f:
    f.write(text)

if applied:
    print("patched: %s (%d edits)" % (target, applied))
else:
    print("no changes: %s already patched" % target)
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

python3 -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$FORK_OUT/default/i18n/en/shell.json" || die "JSON invalid after edit: default/i18n/en/shell.json"

printf 'power panel patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 55: power panel — sleep drain, battery health, 80% charge limit"
