#!/usr/bin/env bash
# Hexciri fork patch 64: disable the NMI hardlockup watchdog to save power
# (upstream omarchy PR #20392, verified against its .diff 2026-11-27).
#
# Upstream adds etc/sysctl.d/99-omarchy-nmi-watchdog.conf:
#   -kernel.nmi_watchdog = 0
# The NMI watchdog fires periodic NMI interrupts (and holds a hardware PMU
# counter on perf-based hardlockup detectors); the soft-lockup watchdog stays
# enabled, only hard-lockup detection is turned off. The leading "-" makes
# systemd-sysctl ignore the line cleanly on kernels without
# CONFIG_HARDLOCKUP_DETECTOR, so the same drop-in is safe on both machines
# (desktop 9800X3D, laptop Ryzen 5 7640U).
#
# Fork adaptations (vs upstream verbatim):
#   * Renamed to etc/sysctl.d/99-hexciri-nmi-watchdog.conf, matching the
#     fork's etc/ naming (hexciri-nopasswd-sudo.conf, hexciri-theme-browser).
#     The file content carries no omarchy references.
#   * SKIPPED, default/settings-runtime-profile: that file is omarchy-settings
#     data, not copied to FORK_OUT (no install.sh step copies it).
#   * SKIPPED, migrations/1795775300.sh: the fork has no migrations/ dir and
#     no migrations runner; the exit-75-pending pattern has no landing
#     (patch 39 precedent). The migration's live effect was: if
#     /proc/sys/kernel/nmi_watchdog is readable and not already 0, run
#     `sudo /usr/lib/systemd/systemd-sysctl <dropin>`.
#   * NEEDS THE PLACEMENT STEP: the fork never installs FORK_OUT/etc/ to the
#     live system, so this file is staged in FORK_OUT only until install.sh
#     gains a placement step:
#       sudo install -Dm644 "$FORK_OUT/etc/sysctl.d/99-hexciri-nmi-watchdog.conf" \
#         /etc/sysctl.d/99-hexciri-nmi-watchdog.conf
#       sudo /usr/lib/systemd/systemd-sysctl /etc/sysctl.d/99-hexciri-nmi-watchdog.conf
#     Until that lands, the watchdog stays on; nothing else in this patch
#     changes live behavior.
#
# Standalone: bash v2/patches/64-disable-nmi-watchdog.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "64-disable-nmi-watchdog.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "64-disable-nmi-watchdog.sh: $1" >&2; exit 1; }
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

# --- 1. NMI watchdog sysctl drop-in, omarchy PR #20392 ---
step "Staging NMI watchdog sysctl drop-in (needs the install.sh placement step)"
install_new_file "etc/sysctl.d/99-hexciri-nmi-watchdog.conf" 644 <<'HEXCIRI_EOF_NMI_WATCHDOG'
# Disable the NMI hardlockup watchdog to eliminate periodic NMI interrupts
# (and free a hardware PMU counter on perf-based hardlockup detectors). The
# soft-lockup watchdog stays enabled; only hard-lockup detection is turned off.
# The leading "-" makes systemd-sysctl ignore this cleanly on kernels without
# CONFIG_HARDLOCKUP_DETECTOR.

-kernel.nmi_watchdog = 0
HEXCIRI_EOF_NMI_WATCHDOG

# Shape check: exactly one assignment, leading dash, watchdog off.
grep -qx -- '-kernel.nmi_watchdog = 0' "$FORK_OUT/etc/sysctl.d/99-hexciri-nmi-watchdog.conf" || die "sysctl drop-in lost its -kernel.nmi_watchdog = 0 line"
[ "$(grep -c '^[^#[:space:]]' "$FORK_OUT/etc/sysctl.d/99-hexciri-nmi-watchdog.conf")" = "1" ] || die "sysctl drop-in has more than one non-comment line"
grep -q 'CONFIG_HARDLOCKUP_DETECTOR' "$FORK_OUT/etc/sysctl.d/99-hexciri-nmi-watchdog.conf" || die "sysctl drop-in lost its detector comment"

printf 'NMI watchdog patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 64: NMI watchdog sysctl drop-in staged (needs the install.sh placement step)"
