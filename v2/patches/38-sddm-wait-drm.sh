#!/usr/bin/env bash
# Hexciri fork patch 38: wait for the DRM handoff before SDDM starts.
# Forward-port of omarchy PR #20059 (commit cc5ea151c, "Wait for DRM handoff
# from simpledrm before starting SDDM"). New files only, CLEAN vs the pin.
#
# What it does (PR behavior, unchanged): SDDM waits for the real GPU driver
# to replace simpledrm before starting. Without early KMS the simpledrm ->
# real-driver handoff bounces seat0 CanGraphical (true -> false -> true),
# which makes SDDM SIGTERM its one-shot autologin helper and fall back to
# the greeter. The helper waits for simpledrm unbind (5s each), then for a
# /dev/dri/card* to exist and finish udev init (10s). Relevant on the
# dual-GPU desktop (RTX 4080 Super + AMD 610M iGPU).
#
# Fork adaptations:
# - Renamed: bin/hexciri-system-sddm-wait-drm, drop-in
#   etc/systemd/system/sddm.service.d/10-hexciri-wait-drm.conf.
# - ExecStartPre path is /usr/share/hexciri/bin/hexciri-system-sddm-wait-drm,
#   NOT /usr/bin/... as upstream: the installer has no fixed-path rule for
#   this helper, and fork bins live in /usr/share/hexciri/bin. A /usr/bin
#   path here would fail silently (ExecStartPre has the '-' prefix) and
#   the wait would never happen.
# - The helper reaches /usr/share/hexciri/bin through the normal flow: it
#   matches the installer's bin allowlist (system-*) as a patch-created
#   file, and placement copies FORK_OUT/bin wholesale.
#
# Placement gap (NOT fixed by this patch, needs an install.sh step): the
# fork stages etc/ files under FORK_OUT but only ever installs two of them
# to the live system (etc/sudoers.d/hexciri-theme-browser and
# etc/tmpfiles.d/hexciri-nopasswd-sudo.conf, each with its own one-off step).
# The placement copy (install.sh, "sudo cp -a" of shell/default/themes/bin/
# install/icons/config/applications) omits etc/ entirely, and the fork repo
# has no etc/ tree. So this patch stages the drop-in at
# FORK_OUT/etc/systemd/system/sddm.service.d/10-hexciri-wait-drm.conf and it
# does NOTHING until install.sh gains:
#   sudo install -Dm644 "$FORK_OUT/etc/systemd/system/sddm.service.d/10-hexciri-wait-drm.conf" \
#     /etc/systemd/system/sddm.service.d/10-hexciri-wait-drm.conf
#   sudo systemctl daemon-reload
# Upstream ships the same drop-in via the omarchy-settings package; the fork
# has no equivalent package, which is why this is an installer follow-up
# and not part of the patch. Existing installs also need the drop-in
# installed by hand (or a re-run after that step lands) for the wait to run.
#
# Skipped from the PR: test/shell.d/systemd-test.sh (test/ is not in
# FORK_OUT; no existing patch touches tests). Sim replays the upstream
# test's early-KMS case against the staged helper with a mocked udevadm
# instead; see the README section.
#
# Standalone: bash v2/patches/38-sddm-wait-drm.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A present file with different content dies rather
#   than clobbering it.
#
# Syntax check note: the helper is bash, so the end-of-patch check is
# bash -n on it. The drop-in is a systemd unit fragment; it is validated
# by grep for its [Service] section and ExecStartPre line (no
# systemd-analyze verify here: it needs the live sddm unit to resolve).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "38-sddm-wait-drm.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
# --- SDDM wait-for-DRM helper + drop-in, omarchy PR #20059 ---
install_new_file "bin/hexciri-system-sddm-wait-drm" 755 <<'HEXCIRI_EOF_SDDM_WAIT_DRM'
#!/bin/bash

# omarchy:summary=Wait for the DRM device to settle before starting SDDM
# omarchy:group=system
# omarchy:hidden=true

set -euo pipefail
shopt -s nullglob

SIMPLEFB_DIR=/sys/bus/platform/drivers/simple-framebuffer
DRI_DIR=/dev/dri

# If simpledrm is still holding the framebuffer, wait for the real GPU driver
# to unbind it (bounded for nomodeset/simpledrm-only systems).
for fb in "$SIMPLEFB_DIR"/simple-framebuffer.*; do
  udevadm wait --timeout=5 --removed "$fb" || true
done

# Wait for the DRM card to exist and finish udev initialization (instant on
# normal early-KMS boots; waits out mid-handoff probing otherwise).
cards=("$DRI_DIR"/card[0-9]*)
if (( ${#cards[@]} == 0 )); then
  exec {drm_events}< <(exec timeout 10 udevadm monitor --udev --subsystem-match=drm)
  monitor_pid=$!
  while IFS= read -r -u "$drm_events" event; do
    # The UDEV header follows subscription setup; rescan then and on events.
    [[ $event == UDEV* ]] || continue
    cards=("$DRI_DIR"/card[0-9]*)
    (( ${#cards[@]} > 0 )) && break
  done
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  exec {drm_events}<&-
fi
if (( ${#cards[@]} > 0 )); then
  udevadm wait --timeout=10 --initialized=true "${cards[@]}" || true
fi
HEXCIRI_EOF_SDDM_WAIT_DRM
install_new_file "etc/systemd/system/sddm.service.d/10-hexciri-wait-drm.conf" 644 <<'HEXCIRI_EOF_SDDM_DROPIN'
[Service]
# Wait for the real DRM driver to replace simpledrm before SDDM starts.
# Without early KMS (e.g., prebuilt UKI first boot or hardware that keeps its
# GPU driver out of the initramfs), the simpledrm -> real driver handoff bounces
# seat0 CanGraphical (true -> false -> true), causing SDDM to SIGTERM its
# one-shot autologin helper and fall back to the greeter.
ExecStartPre=-/usr/share/hexciri/bin/hexciri-system-sddm-wait-drm
HEXCIRI_EOF_SDDM_DROPIN

# Syntax + shape checks: the helper is bash, the drop-in is a unit fragment.
bash -n "$FORK_OUT/bin/hexciri-system-sddm-wait-drm" || die "bash -n failed on patched hexciri-system-sddm-wait-drm"
grep -q '^\[Service\]$' "$FORK_OUT/etc/systemd/system/sddm.service.d/10-hexciri-wait-drm.conf" || die "sddm drop-in lost its [Service] section"
grep -q '^ExecStartPre=-/usr/share/hexciri/bin/hexciri-system-sddm-wait-drm$' "$FORK_OUT/etc/systemd/system/sddm.service.d/10-hexciri-wait-drm.conf" || die "sddm drop-in ExecStartPre does not point at /usr/share/hexciri/bin/hexciri-system-sddm-wait-drm"
printf 'sddm-wait-drm patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  sddm-wait-drm: SDDM now waits for the DRM handoff before starting (PR #20059; drop-in staged, installer placement step still needed)"
