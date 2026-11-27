#!/usr/bin/env bash

# Hexciri fork patch 63: transparent huge pages to madvise and cap the
# systemd journal at 100M.
# Forward-port of omarchy PR #20414 ("Set transparent huge pages to
# madvise and cap systemd journal size", rework).
#
# What it does (PR behavior, unchanged): THP defaults to madvise instead
# of always, so sparse heap allocations across the shell, compositor, and
# small daemons stop inflating into 2 MiB pages (and stop adding split
# overhead under zram swap); processes that opt in with MADV_HUGEPAGE
# still receive hugepages. The journal is bounded at 100M persistent /
# 32M volatile so long-running journalctl watchers (such as
# hexciri-crash-watch) do not map hundreds of megabytes of journal files
# into RAM on 8 GiB machines. Both machines here have 32 GiB, so the
# journal cap is headroom hygiene, not a rescue; the THP change is the
# half that matters day to day.
#
# Fork adaptations:
# - Neither file exists in FORK_OUT at the pin: copy_subsets never copies
#   etc/systemd/ or etc/tmpfiles.d/ (except the nopasswd-sudo one-off)
#   into the fork tree, so both files are created whole with their
#   post-PR content instead of edited in place.
# - Names follow the installer's rename map (omarchy -> hexciri, applied
#   before patches run): 10-omarchy.conf becomes 10-hexciri.conf,
#   omarchy-thp.conf becomes hexciri-thp.conf.
# - The PR's default/settings-runtime-profile doc edit is SKIPPED: that
#   file is not copied into FORK_OUT (default/ subset copies are only
#   hypr, i18n, themed, plus named files), and its anchor does not exist
#   at the pin anyway (the pin file is 24 lines and ends with the
#   modprobe block; the PR's power-profiles context was added upstream
#   after the pin). The comment index has no landing in the fork; the
#   two functional files below are the whole port.
#
# Placement gap (NOT fixed by this patch, needs an install.sh step): the
# fork stages etc/ files under FORK_OUT but only ever installs two of them
# to the live system (etc/sudoers.d/hexciri-theme-browser and
# etc/tmpfiles.d/hexciri-nopasswd-sudo.conf, each with its own one-off
# step). The placement copy (install.sh, "sudo cp -a" of shell/default/
# themes/bin/install/icons/config/applications) omits etc/ entirely.
# These two files do NOTHING until install.sh gains:
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/journald.conf.d/10-hexciri.conf" \
#     /etc/systemd/journald.conf.d/10-hexciri.conf
#   sudo install -Dm644 "$FORK_OUT/etc/tmpfiles.d/hexciri-thp.conf" \
#     /etc/tmpfiles.d/hexciri-thp.conf
#   sudo systemctl restart systemd-journald.service
#   sudo journalctl --vacuum-size=100M
#   sudo /usr/bin/systemd-tmpfiles --create --boot /etc/tmpfiles.d/hexciri-thp.conf
# The journald restart + vacuum is a one-time shrink (the upstream
# migration does exactly this, stamped so later users on the same machine
# do not restart journald again); the tmpfiles --create applies the THP
# mode immediately when /sys/kernel/mm/transparent_hugepage/enabled
# exists, and systemd-tmpfiles ignores the file cleanly on kernels built
# without THP. Existing installs also need the files installed by hand
# (or a re-run after that step lands) for either setting to apply.
#
# Skipped from the PR: migrations/1795784791.sh (the fork has no
# migrations/ dir and no migrations runner; the exit-75-pending pattern
# has no landing).
#
# Standalone: bash v2/patches/63-thp-journal-cap.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A present file with different content dies rather
#   than clobbering it.
#
# Syntax check note: the drop-ins are a journald fragment and a tmpfiles
# fragment, not code; they are validated by grep for their section headers
# and keys (a systemd-analyze verify here would need the live journald
# unit to resolve). bash -n applies to this script itself.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "63-thp-journal-cap.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "63-thp-journal-cap.sh: $1" >&2; exit 1; }
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

# --- 1. Journal size cap, omarchy PR #20414 ---
step "Capping the systemd journal at 100M"
install_new_file "etc/systemd/journald.conf.d/10-hexciri.conf" 644 <<'HEXCIRI_EOF_JOURNALD_CONF'
# Bound persistent and volatile journal size so long-running journalctl
# watchers (such as hexciri-crash-watch) do not map hundreds of megabytes of
# journal files into RAM on 8 GiB machines.
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=32M
HEXCIRI_EOF_JOURNALD_CONF

# --- 2. Transparent huge pages to madvise, omarchy PR #20414 ---
step "Setting transparent huge pages to madvise"
install_new_file "etc/tmpfiles.d/hexciri-thp.conf" 644 <<'HEXCIRI_EOF_THP_CONF'
# Prevent transparent_hugepage=always from inflating sparse heap allocations
# across the desktop shell, compositor, and small daemons into 2 MiB pages (and
# adding split overhead under zram swap). Processes that opt in with
# MADV_HUGEPAGE still receive hugepages.
w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
HEXCIRI_EOF_THP_CONF

# --- validation: both fragments must carry their section and keys ---
grep -q '^\[Journal\]$' "$FORK_OUT/etc/systemd/journald.conf.d/10-hexciri.conf" || die "journald drop-in lost its [Journal] section"
grep -q '^SystemMaxUse=100M$' "$FORK_OUT/etc/systemd/journald.conf.d/10-hexciri.conf" || die "journald drop-in lost SystemMaxUse=100M"
grep -q '^RuntimeMaxUse=32M$' "$FORK_OUT/etc/systemd/journald.conf.d/10-hexciri.conf" || die "journald drop-in lost RuntimeMaxUse=32M"
grep -q '^w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise$' "$FORK_OUT/etc/tmpfiles.d/hexciri-thp.conf" || die "THP tmpfiles conf lost its w! line (madvise)"
# No upstream-named files or references may survive the rename.
if grep -r 'omarchy' "$FORK_OUT/etc/systemd/journald.conf.d" "$FORK_OUT/etc/tmpfiles.d/hexciri-thp.conf" 2>/dev/null; then
  die "upstream 'omarchy' reference survived in the staged THP/journal files"
fi
printf 'thp/journal-cap patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 63: THP madvise + journal cap 100M (PR #20414; files staged, installer placement + journald restart still needed)"
