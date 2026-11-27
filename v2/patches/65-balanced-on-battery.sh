#!/usr/bin/env bash
# Hexciri fork patch 65: keep the balanced profile on balance_performance
# when on battery (upstream omarchy PR #20384, verified against its .diff
# 2026-11-27).
#
# power-profiles-daemon's battery_aware downgrade drops the balanced profile
# from balance_performance to balance_power the moment the machine is
# unplugged. Hexciri manages AC and battery profiles explicitly (performance
# on AC, balanced on battery), so the daemon must not second-guess it.
# Upstream seeds battery_aware=false with a tmpfiles.d drop-in:
#   d /var/lib/power-profiles-daemon 0755 root root -
#   f /var/lib/power-profiles-daemon/state.ini 0644 root root - [State]\nbattery_aware=false\n
# The `f` line only creates state.ini when it does not exist; it never
# overwrites an existing file.
#
# Fork adaptations (vs upstream verbatim):
#   * Renamed to etc/tmpfiles.d/hexciri-power-profiles.conf, matching the
#     fork's etc/ naming (hexciri-nopasswd-sudo.conf). The first comment line
#     reads "Hexciri manages ..." (what the install.sh rename map would have
#     produced from "Omarchy manages ...").
#   * SKIPPED, default/settings-runtime-profile: that file is omarchy-settings
#     data, not copied to FORK_OUT (no install.sh step copies it).
#   * SKIPPED, migrations/1795770783.sh: the fork has no migrations/ dir and
#     no migrations runner; the exit-75-pending pattern has no landing
#     (patch 39 precedent). The migration's live effect was: stop
#     power-profiles-daemon, create state.ini via tmpfiles if missing, or
#     flip an existing battery_aware= line to false (sed), or append
#     battery_aware=false under [State], then restart the daemon.
#   * NEEDS THE PLACEMENT STEP: the fork never installs FORK_OUT/etc/ to the
#     live system, so this file is staged in FORK_OUT only until install.sh
#     gains a placement step:
#       sudo install -Dm644 "$FORK_OUT/etc/tmpfiles.d/hexciri-power-profiles.conf" \
#         /etc/tmpfiles.d/hexciri-power-profiles.conf
#       sudo systemd-tmpfiles --create /etc/tmpfiles.d/hexciri-power-profiles.conf
#     Until that lands, nothing changes. Note the placement alone only helps
#     fresh installs: an existing /var/lib/power-profiles-daemon/state.ini
#     with battery_aware=true is left untouched by tmpfiles `f`, so a machine
#     that already has one still needs the migration's live fix once:
#       sudo systemctl stop power-profiles-daemon.service
#       sudo sed -i 's/^battery_aware=.*/battery_aware=false/' /var/lib/power-profiles-daemon/state.ini
#       sudo systemctl start power-profiles-daemon.service
#
# Standalone: bash v2/patches/65-balanced-on-battery.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "65-balanced-on-battery.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "65-balanced-on-battery.sh: $1" >&2; exit 1; }
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

# --- 1. power-profiles-daemon tmpfiles drop-in, omarchy PR #20384 ---
step "Staging power-profiles battery_aware=false tmpfiles drop-in (needs the install.sh placement step)"
install_new_file "etc/tmpfiles.d/hexciri-power-profiles.conf" 644 <<'HEXCIRI_EOF_POWER_PROFILES'
# Hexciri manages AC and battery power profiles explicitly (performance on AC,
# balanced on battery). Disable power-profiles-daemon's battery_aware downgrade
# so balanced stays on balance_performance instead of dropping to balance_power
# when unplugged. Using f seeds new installs before power-profiles-daemon starts
# without overwriting existing state.ini files.
d /var/lib/power-profiles-daemon 0755 root root -
f /var/lib/power-profiles-daemon/state.ini 0644 root root - [State]\nbattery_aware=false\n
HEXCIRI_EOF_POWER_PROFILES

# Shape check: exactly one d line and one f line, seeding battery_aware=false.
grep -qx -- 'd /var/lib/power-profiles-daemon 0755 root root -' "$FORK_OUT/etc/tmpfiles.d/hexciri-power-profiles.conf" || die "tmpfiles drop-in lost its d line"
grep -qx -- 'f /var/lib/power-profiles-daemon/state.ini 0644 root root - \[State\]\\nbattery_aware=false\\n' "$FORK_OUT/etc/tmpfiles.d/hexciri-power-profiles.conf" || die "tmpfiles drop-in lost its f line (battery_aware=false seed)"
[ "$(grep -c '^[df] ' "$FORK_OUT/etc/tmpfiles.d/hexciri-power-profiles.conf")" = "2" ] || die "tmpfiles drop-in does not have exactly one d and one f line"

printf 'balanced-on-battery patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 65: power-profiles battery_aware=false drop-in staged (needs the install.sh placement step)"
