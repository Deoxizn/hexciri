#!/usr/bin/env bash

# Hexciri fork patch 62: protect session.slice file cache with MemoryLow
# 768M and tighten systemd-oomd to 60% over 10s.
# Forward-port of omarchy PR #20426 ("Protect session.slice file cache
# with MemoryLow 768M and tighten oomd to 60%/10s", rework).
#
# What it does (PR behavior, unchanged): the desktop session keeps 768M of
# soft reclaim protection (MemoryLow) so the compositor, shell, audio daemon
# and session helpers stay resident under app.slice memory pressure, and
# systemd-oomd kills one runaway app sooner (60% PSI stall held for 10s
# instead of 50% held for 20s) so incompressible spike freezes end roughly
# twice as fast. MemoryLow is soft protection: it never reserves unused RAM
# and never causes a cgroup OOM. session.slice never hits MemoryMax
# (infinity); app.slice absorbs all swap and stays the sole oomd kill
# candidate. Relevant on both machines (32 GiB each) whenever a browser,
# build, or local model leans on app.slice: without this, MGLRU swaps out
# hundreds of megabytes of compositor/shell pages and the desktop stalls
# on menu, bar, and workspace switches.
#
# Fork adaptations:
# - None of these files exist in FORK_OUT at the pin: copy_subsets never
#   copies etc/systemd/ into the fork tree, so every file here is created
#   whole with its post-PR content instead of edited in place. The oomd
#   file was verified line by line against the pin file (lines 1-11 are
#   byte-identical to the pin; only the 60%/10s hunk changes) and the
#   session.slice file against upstream HEAD (it does not exist at the
#   pin at all; upstream added it between the pin and this PR).
# - Names follow the installer's rename map (omarchy -> hexciri, applied
#   before patches run): 10-omarchy.conf becomes 10-hexciri.conf,
#   10-omarchy-memory.conf becomes 10-hexciri-memory.conf,
#   20-omarchy-memory.conf becomes 20-hexciri-memory.conf. The two
#   self-referencing comments are updated to the hexciri paths for the
#   same reason.
# - The user.slice -> user-.slice -> user@.service chain delegates the
#   768M budget down to session.slice: effective memory.low is bounded by
#   the minimum across all ancestor cgroups, so all four MemoryLow=768M
#   files must land together.
#
# Placement gap (NOT fixed by this patch, needs an install.sh step): the
# fork stages etc/ files under FORK_OUT but only ever installs two of them
# to the live system (etc/sudoers.d/hexciri-theme-browser and
# etc/tmpfiles.d/hexciri-nopasswd-sudo.conf, each with its own one-off
# step). The placement copy (install.sh, "sudo cp -a" of shell/default/
# themes/bin/install/icons/config/applications) omits etc/ entirely.
# These five drop-ins do NOTHING until install.sh gains:
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/oomd.conf.d/10-hexciri.conf" \
#     /etc/systemd/oomd.conf.d/10-hexciri.conf
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/system/user.slice.d/10-hexciri-memory.conf" \
#     /etc/systemd/system/user.slice.d/10-hexciri-memory.conf
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/system/user-.slice.d/10-hexciri-memory.conf" \
#     /etc/systemd/system/user-.slice.d/10-hexciri-memory.conf
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/system/user@.service.d/20-hexciri-memory.conf" \
#     /etc/systemd/system/user@.service.d/20-hexciri-memory.conf
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/user/session.slice.d/10-hexciri.conf" \
#     /etc/systemd/user/session.slice.d/10-hexciri.conf
#   sudo systemctl daemon-reload
#   sudo systemctl restart systemd-oomd.service
#   systemctl --user daemon-reload
# The system-slice drop-ins only take effect for new logins (a running
# user.slice keeps its old cgroup properties until re-login); the
# session.slice drop-in takes effect at the next user daemon-reload.
# Existing installs also need the files installed by hand (or a re-run
# after that step lands) for the protection to apply.
#
# Skipped from the PR: migrations/1795790700.sh (the fork has no
# migrations/ dir and no migrations runner; the exit-75-pending pattern
# has no landing).
#
# Standalone: bash v2/patches/62-session-memorylow-oomd.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A present file with different content dies rather
#   than clobbering it.
#
# Syntax check note: the drop-ins are systemd unit fragments, not code;
# they are validated by grep for their section headers and keys (a
# systemd-analyze verify here would need the live slice units to
# resolve). bash -n applies to this script itself.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "62-session-memorylow-oomd.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "62-session-memorylow-oomd.sh: $1" >&2; exit 1; }
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

# --- 1. systemd-oomd pressure limits, omarchy PR #20426 ---
step "Tightening systemd-oomd pressure response (60% over 10s)"
install_new_file "etc/systemd/oomd.conf.d/10-hexciri.conf" 644 <<'HEXCIRI_EOF_OOMD_CONF'
# Without an OOM daemon there is nothing between "memory is tight" and
# "processes start dying at random". The kernel OOM killer only fires once an
# allocation has already failed outright, which is far too late for the
# desktop: the machine thrashes in reclaim until something fails somewhere
# fatal. Seen in practice as Hyprland taking SIGBUS mid-memcpy from a Wayland
# client's shm pool, because the client was being torn down by the same memory
# pressure. One app misbehaving should not cost the whole session.
#
# systemd-oomd keys on PSI stall time rather than on free pages, so it acts
# while the machine is still thrashing instead of after an allocation failed.
# Deliberately not earlyoom: that fires only when free RAM *and* free swap are
# both under threshold, so a large, mostly-unused swapfile keeps it asleep
# through exactly this failure.
#
# 60% means 60% of a ten-second window was spent stalled on memory reclaim.
# Held for 10s straight, the desktop is already thrashing and losing one app is
# the cheaper outcome; raising the threshold from 50% to 60% while cutting the
# hold from 20s to 10s cuts incompressible spike freezes roughly in half while
# letting the 10s PSI EWMA (avg10) decay below threshold faster after a kill.
# Which cgroups are eligible is set separately, in
# /usr/lib/systemd/user/app.slice.d/10-oomd.conf.
[OOM]
DefaultMemoryPressureLimit=60%
DefaultMemoryPressureDurationSec=10s
HEXCIRI_EOF_OOMD_CONF

# --- 2. MemoryLow delegation chain, omarchy PR #20426 ---
step "Delegating MemoryLow 768M down to session.slice"
install_new_file "etc/systemd/system/user.slice.d/10-hexciri-memory.conf" 644 <<'HEXCIRI_EOF_USER_SLICE'
# Delegate cgroup v2 memory.low down to session.slice; effective memory.low
# is bounded by the minimum across all ancestor cgroups. Under cgroup v2
# memory_recursiveprot, protection above session.slice's actual usage is
# shared across siblings, and multiple logged-in users share this budget.
[Slice]
MemoryLow=768M
HEXCIRI_EOF_USER_SLICE
install_new_file "etc/systemd/system/user-.slice.d/10-hexciri-memory.conf" 644 <<'HEXCIRI_EOF_USER_DASH_SLICE'
# Delegate cgroup v2 memory.low down to session.slice; see
# /etc/systemd/system/user.slice.d/10-hexciri-memory.conf.
[Slice]
MemoryLow=768M
HEXCIRI_EOF_USER_DASH_SLICE
install_new_file "etc/systemd/system/user@.service.d/20-hexciri-memory.conf" 644 <<'HEXCIRI_EOF_USER_AT_SERVICE'
# Delegate cgroup v2 memory.low down to session.slice; see
# /etc/systemd/system/user.slice.d/10-hexciri-memory.conf.
[Service]
MemoryLow=768M
HEXCIRI_EOF_USER_AT_SERVICE

# --- 3. session.slice protection, omarchy PR #20426 ---
step "Protecting session.slice file cache with MemoryLow 768M"
install_new_file "etc/systemd/user/session.slice.d/10-hexciri.conf" 644 <<'HEXCIRI_EOF_SESSION_SLICE'
# Keep the compositor, shell, audio daemon, and session helpers resident in RAM
# (both anonymous and file-backed executable/library pages) and responsive under
# heavy app.slice memory or CPU load.
#
# Hyprland, Quickshell, PipeWire, and desktop portals run in session.slice,
# while browsers, builds, and local AI models run in app.slice. MemorySwapMax=0
# keeps anonymous pages out of swap, and MemoryLow=768M (delegated down from
# user.slice -> user-.slice -> user@.service) gives session.slice soft reclaim
# protection so clean file-backed code and shader pages aren't stripped out
# before app.slice is reclaimed. MemoryLow is soft protection: it never
# reserves unused RAM and never causes a cgroup OOM. MemoryMax stays infinity;
# app.slice absorbs all swap and remains the sole systemd-oomd kill candidate.
[Slice]
MemorySwapMax=0
MemoryLow=768M
CPUWeight=500
HEXCIRI_EOF_SESSION_SLICE

# --- validation: every drop-in must carry its section and keys ---
grep -q '^\[OOM\]$' "$FORK_OUT/etc/systemd/oomd.conf.d/10-hexciri.conf" || die "oomd drop-in lost its [OOM] section"
grep -q '^DefaultMemoryPressureLimit=60%$' "$FORK_OUT/etc/systemd/oomd.conf.d/10-hexciri.conf" || die "oomd drop-in lost DefaultMemoryPressureLimit=60%"
grep -q '^DefaultMemoryPressureDurationSec=10s$' "$FORK_OUT/etc/systemd/oomd.conf.d/10-hexciri.conf" || die "oomd drop-in lost DefaultMemoryPressureDurationSec=10s"
for _mem in "$FORK_OUT/etc/systemd/system/user.slice.d/10-hexciri-memory.conf" \
  "$FORK_OUT/etc/systemd/system/user-.slice.d/10-hexciri-memory.conf" \
  "$FORK_OUT/etc/systemd/system/user@.service.d/20-hexciri-memory.conf" \
  "$FORK_OUT/etc/systemd/user/session.slice.d/10-hexciri.conf"; do
  grep -q '^MemoryLow=768M$' "$_mem" || die "$_mem lost MemoryLow=768M"
done
grep -q '^\[Slice\]$' "$FORK_OUT/etc/systemd/user/session.slice.d/10-hexciri.conf" || die "session.slice drop-in lost its [Slice] section"
grep -q '^MemorySwapMax=0$' "$FORK_OUT/etc/systemd/user/session.slice.d/10-hexciri.conf" || die "session.slice drop-in lost MemorySwapMax=0"
grep -q '^CPUWeight=500$' "$FORK_OUT/etc/systemd/user/session.slice.d/10-hexciri.conf" || die "session.slice drop-in lost CPUWeight=500"
# No upstream-named files or references may survive the rename: a stray
# 10-omarchy.conf would load alongside the hexciri one and confuse which
# drop-in owns the keys.
if grep -r 'omarchy' "$FORK_OUT/etc/systemd/oomd.conf.d" "$FORK_OUT/etc/systemd/system/user.slice.d" "$FORK_OUT/etc/systemd/system/user-.slice.d" "$FORK_OUT/etc/systemd/system/user@.service.d" "$FORK_OUT/etc/systemd/user/session.slice.d" 2>/dev/null; then
  die "upstream 'omarchy' reference survived in the staged memory drop-ins"
fi
printf 'session memorylow/oomd patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 62: session.slice MemoryLow 768M + oomd 60%/10s (PR #20426; drop-ins staged, installer placement + reloads still needed)"
