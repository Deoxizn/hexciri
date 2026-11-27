#!/usr/bin/env bash
# Hexciri fork patch 39: don't suspend a closed laptop on external power.
# Forward-port of omarchy PR #20325 (commit 9dfce75c0, "Don't suspend a
# closed laptop on external power"). One logind drop-in, CLEAN vs the pin.
#
# What it does (PR behavior, unchanged): HandleLidSwitchExternalPower=ignore.
# logind only treats a closed lid as docked while an external connector has
# an active output, and that drops out whenever the display re-enumerates
# (Thunderbolt displays do this on wake and at random) or Hyprland
# reconfigures outputs. Each gap suspends the machine mid-use, and after
# every wake logind rechecks the lid 30 seconds later, so a display slow to
# return puts it straight back to sleep. On power the lid is left to the
# shell; on battery, closing the lid suspends as before. This is the docked
# Framework 13 suspending mid-use on display re-enumeration.
#
# The "still locks" half is VERIFIED in the fork, not assumed: the scope
# doc's caveat ("fork has no omarchy-system-lid-close equivalent") is wrong.
# The fork ships hexciri-system-lid-close in the installed tree (it matches
# the installer's bin allowlist, system-*), and default/hypr/bindings/
# utilities.lua binds Lid Switch (plus Apple SMC and cros_ec_buttons) to
# hexciri-system-lid-close, which locks only when the lid is shut AND no
# external monitor is attached. So with this drop-in, a closed lid on power
# with no external display still locks, exactly as upstream describes.
# No key conflict: upstream's sibling drop-ins in the same directory set
# different keys (HandlePowerKey in 10-ignore-power-button.conf,
# InhibitDelayMaxSec in 20-inhibit-delay.conf); this file is the only one
# setting HandleLidSwitchExternalPower, so load order cannot change its
# meaning. (Those siblings are not copied into the fork tree by the
# installer, which is also why this drop-in needs the placement step below.)
#
# Placement gap (NOT fixed by this patch, needs an install.sh step): same
# as patch 38. The fork stages etc/ files under FORK_OUT but only installs
# etc/sudoers.d/hexciri-theme-browser and etc/tmpfiles.d/hexciri-nopasswd-
# sudo.conf to the live system; the placement copy omits etc/ entirely.
# This patch stages the drop-in at
# FORK_OUT/etc/systemd/logind.conf.d/30-lid-external-power.conf and it does
# NOTHING until install.sh gains:
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/logind.conf.d/30-lid-external-power.conf" \
#     /etc/systemd/logind.conf.d/30-lid-external-power.conf
#   sudo systemctl reload systemd-logind
# (Reload, not restart: restarting logind tears down the session. A reload
# that leaves the old lid handling in place only takes effect on reboot;
# upstream's migration checks HandleLidSwitchExternalPower over busctl and
# sets reboot-required when it is not yet "ignore".)
#
# Skipped from the PR: migrations/1795719018.sh (the fork has no migrations/
# dir and no migrations runner; the exit-75-pending pattern has no landing)
# and manual/33-monitors.md (manual/ is not in FORK_OUT).
#
# Standalone: bash v2/patches/39-lid-external-power.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A present file with different content dies rather
#   than clobbering it.
#
# Syntax check note: the drop-in is a logind config fragment, not code;
# it is validated by grep for its [Login] section and the
# HandleLidSwitchExternalPower line. bash -n does not apply.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "39-lid-external-power.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}
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
# --- Lid-on-external-power drop-in, omarchy PR #20325 ---
install_new_file "etc/systemd/logind.conf.d/30-lid-external-power.conf" 644 <<'HEXCIRI_EOF_LID_DROPIN'
# A closed lid on external power is almost always a laptop docked to a display.
# logind only treats it as docked while an external connector has an active
# output, and that drops out whenever the display re-enumerates (Thunderbolt
# displays like the Pro Display XDR do this on wake and at random) or Hyprland
# reconfigures outputs. Each gap suspends the machine mid-use, and after every
# wake logind rechecks the lid 30 seconds later, so a display slow to return
# puts it straight back to sleep.
#
# On power, leave the lid to Hexciri: hexciri-system-lid-close still locks when
# no external display is attached. On battery, closing the lid suspends as before.
[Login]
HandleLidSwitchExternalPower=ignore
HEXCIRI_EOF_LID_DROPIN

# Shape check: the drop-in must carry the [Login] section and the ignore.
grep -q '^\[Login\]$' "$FORK_OUT/etc/systemd/logind.conf.d/30-lid-external-power.conf" || die "lid drop-in lost its [Login] section"
grep -q '^HandleLidSwitchExternalPower=ignore$' "$FORK_OUT/etc/systemd/logind.conf.d/30-lid-external-power.conf" || die "lid drop-in lost HandleLidSwitchExternalPower=ignore"
printf 'lid-external-power patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  lid-external-power: closed laptop on external power no longer suspends (PR #20325; drop-in staged, installer placement + logind reload still needed)"
