#!/usr/bin/env bash
# Hexciri fork patch runner: applies v2/patches/* in MANIFEST order to $FORK_OUT.
# Called by v2/install.sh (thin orchestrator) and runnable standalone:
#   bash v2/patches/apply.sh [FORK_OUT]
# FORK_OUT may also come from the environment. Each patch is a standalone
# script; it gets FORK_OUT as $1 plus HEXCIRI_PATH, HEXCIRI_REPO_ROOT,
# INSTALLER_DIR, FORK_LOG and _patch_log from the environment. A patch
# failure dies here with the patch name and exit code, so the installer
# never continues onto a half-patched fork.
set -euo pipefail
PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MANIFEST="$PATCHES_DIR/MANIFEST"
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "apply.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
[ -d "$FORK_OUT" ] || { printf 'ERROR: %s\n' "apply.sh: FORK_OUT is not a directory: $FORK_OUT" >&2; exit 1; }
[ -f "$MANIFEST" ] || { printf 'ERROR: %s\n' "apply.sh: MANIFEST missing: $MANIFEST" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
export FORK_OUT HEXCIRI_PATH HEXCIRI_REPO_ROOT INSTALLER_DIR FORK_LOG _patch_log
_n=0
while IFS= read -r _patch || [ -n "$_patch" ]; do
  case "$_patch" in ''|'#'*) continue ;; esac
  _n=$((_n + 1))
  if [ ! -f "$PATCHES_DIR/$_patch" ]; then
    printf 'ERROR: [hexciri] fork patch %s is listed in MANIFEST but missing from %s\n' "$_patch" "$PATCHES_DIR" >&2
    exit 1
  fi
  bash "$PATCHES_DIR/$_patch" "$FORK_OUT" || {
    _rc=$?
    printf 'ERROR: [hexciri] fork patch %s failed (exit %s), aborting\n' "$_patch" "$_rc" >&2
    exit 1
  }
done < "$MANIFEST"
[ "$_n" -gt 0 ] || { printf 'ERROR: %s\n' "apply.sh: MANIFEST lists no patches: $MANIFEST" >&2; exit 1; }
