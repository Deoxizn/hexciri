#!/usr/bin/env bash
# Hexciri fork patch 10: hexciri-plugin-update pulls the checked-out branch.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/10-plugin-update.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "10-plugin-update.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- hexciri-plugin-update pulls the checked-out branch (2026-11-24, Nyxiri nyx step) ---
# Upstream update_one() runs `git fetch origin HEAD`, i.e. the remote
# DEFAULT branch (main), then merges FETCH_HEAD. A plugin installed
# from nyx would merge main into its nyx checkout, or fail to
# fast-forward once they diverge, and never pull nyx. `git remote
# set-head origin nyx` does NOT fix it: fetch resolves HEAD on the
# REMOTE side, the local origin/HEAD symref is ignored (verified in a
# local bare-repo sim: after set-head, fetch origin HEAD still landed
# the main tip). So patch the fetch to the checked-out branch; detached
# HEAD falls back to origin HEAD. This is what makes
# `hexciri plugin update pizza.dirty.nyxiri` pull nyx after the Nyxiri
# step installs it, and it also fixes the Settings plugin (master) the
# same way. Idempotent: anchor is the single upstream fetch line.
PLUGIN_UPDATE_BIN="$FORK_OUT/bin/hexciri-plugin-update"
if [ -f "$PLUGIN_UPDATE_BIN" ]; then
  python3 - "$PLUGIN_UPDATE_BIN" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()
old = '  if ! git -C "$dir" fetch --quiet origin HEAD; then'
new = """  # Hexciri: fetch the CHECKED-OUT branch, not origin HEAD. Upstream
  # fetches origin HEAD (the remote DEFAULT branch, main), so a plugin
  # installed from nyx would merge main into its nyx checkout, or fail
  # to fast-forward once they diverge, and never pull nyx. Detached
  # HEAD falls back to origin HEAD. (2026-11-24, Nyxiri nyx step.)
  _upd_branch="$(git -C "$dir" branch --show-current 2>/dev/null || echo "")"
  if [ -n "$_upd_branch" ]; then _upd_fetch="$_upd_branch"; else _upd_fetch="HEAD"; fi
  if ! git -C "$dir" fetch --quiet origin "$_upd_fetch"; then"""
if 'fetch --quiet origin "$_upd_fetch"' in s:
    print("plugin-update: checked-out-branch fetch already present, skipping")
else:
    assert s.count(old) == 1, "plugin-update fetch anchor not found exactly once"
    s = s.replace(old, new, 1)
    with open(path, "w") as f:
        f.write(s)
    print("plugin-update: fetch origin HEAD -> fetch checked-out branch (nyx-safe)")
PY
  bash -n "$PLUGIN_UPDATE_BIN" || die "bash -n failed on patched $PLUGIN_UPDATE_BIN"
  info "  plugin-update: pulls the checked-out branch, not origin HEAD (Nyxiri nyx plugins update from nyx)"
else
  warn "  plugin-update: bin/hexciri-plugin-update not in fork output, Nyxiri plugins will update from main until it is patched"
fi
