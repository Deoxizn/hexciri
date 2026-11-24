#!/usr/bin/env bash
# Hexciri fork patch 05: background install to Strata file manager.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/05-background-strata.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "05-background-strata.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  # Re-run quiet (2026-11-24, Devi: a plain `hexciri update` printed
  # ~500 lines of installer re-run spam, most of them "Kept: ... (already
  # current)" / "already present" / "already correct"). On a re-run those
  # go to the detail log only; changed / failed steps still print, and
  # the one-line "already up to date" status lines (run_pacman) stay on
  # screen, they are the per-step result.
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
# Fork-integrity helpers, verbatim from install.sh (00-compat-alias.sh
# calls bootstrap_ok; hyprlua_ok is here for any patch that needs it).
bootstrap_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 500 ] || return 1
  grep -q 'package.path' "$_f" 2>/dev/null || return 1
  grep -q 'HEXCIRI_PATH' "$_f" 2>/dev/null || return 1
  return 0
}
hyprlua_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 1000 ] || return 1
  grep -q 'require("default.hypr.helpers")' "$_f" 2>/dev/null || return 1
  return 0
}

# --- Patch background install to Strata (2026-11-24, Devi: Install > Style > Background loads nothing) ---
# Upstream bin/omarchy-theme-bg-install (menu row install.style.background,
# action hexciri-theme-bg-install) ends with bare `folio "$THEME_USER_BACKGROUNDS"`.
# Folio is not installed in Hexciri v2 (Devi: file manager is Strata via GitHub,
# not Folio; no nautilus either), so the command fails silently and nothing
# opens. The fork rename only mapped folio -> strata for the uwsm-app
# invocation in launch-files; the bare `folio <dir>` call here was never
# touched. Fix: open the folder with hexciri-launch-files (the v2
# file-manager launcher, strata via uwsm-app). That launcher dropped its
# arguments, so it is patched here too to forward "$@" to strata (zero
# args expands to nothing, so Super+Shift+F is unchanged). Strata accepts
# a path argument: hexciri-launch-files-cwd already passes
# strata "$(hexciri-cmd-terminal-cwd)". No Folio/nautilus install.
step "Patching background install to Strata file manager"
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
root = sys.argv[1]
# 1. Background install: folio -> Strata launcher, with the folder path.
path = root + "/bin/hexciri-theme-bg-install"
with open(path) as f:
    s = f.read()
orig = s
old = 'folio "$THEME_USER_BACKGROUNDS"'
assert 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' in s or s.count(old) == 1, "theme-bg-install folio anchor not found"
s = s.replace(old, 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"', 1)
if s != orig:
    with open(path, "w") as f:
        f.write(s)
    print("theme-bg-install: opens backgrounds folder with hexciri-launch-files (Strata), not folio")
else:
    print("theme-bg-install: Strata launcher already applied, skipping")
# 2. File-manager launcher: forward its arguments to strata.
path = root + "/bin/hexciri-launch-files"
with open(path) as f:
    s = f.read()
orig = s
old = "exec setsid uwsm-app -- strata"
assert 'exec setsid uwsm-app -- strata "$@"' in s or s.count(old) == 1, "launch-files strata anchor not found"
s = s.replace(old, 'exec setsid uwsm-app -- strata "$@"', 1) if 'exec setsid uwsm-app -- strata "$@"' not in s else s
if s != orig:
    with open(path, "w") as f:
        f.write(s)
    print("launch-files: forwards \"$@\" to strata (folder opens at the requested path)")
else:
    print("launch-files: \"$@\" forwarding already applied, skipping")
PY
