#!/usr/bin/env bash
# Hexciri fork patch 09: opencode out of the box, no account.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/09-opencode.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "09-opencode.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- opencode out of the box, no account (2026-11-24, Devi) ---
# v1 installed opencode with pacman and hexciri-agent just exec'd it:
# install and start using, no setup. v2 left it a lazy mise tool and
# the agents panel treated OpenCode as a subscription to sign in to,
# running `opencode auth login opencode --method device` (make an
# OpenCode Console account, enter the code). The free models need no
# account at all: opencode 1.19.6 and 2.4.1 both open straight into
# the TUI on Big Pickle with no auth.json, and v2.4.0 did a task on
# Big Pickle with no account in 12.6s (2026-11-23 test). So:
#   * default-agent counts a system /usr/bin binary as present, or
#     it would mise-install over the pacman one every time;
#   * the panel's plain OpenCode tile makes opencode the default and
#     opens it instead of the Console device login. OpenCode Go keeps
#     the device login: Go is a paid subscription, an account IS
#     required there, and its tile signs in as opencode.
DA_FILE="$FORK_OUT/bin/hexciri-default-agent"
if [ -f "$DA_FILE" ]; then
  python3 - "$DA_FILE" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()
old = """  agent_present() { user_install || mise where "$agent_tool" &>/dev/null; }"""
new = """  # A system install counts too: v1 installed opencode with pacman, and
  # a /usr/bin binary is a real install, not a mise shim. Only mise's own
  # shims and command wrappers are skipped, as in
  # hexciri-agent-account-add's cli_missing().
  system_install() {
    local mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}
    local dir path=""
    local IFS=:
    for dir in $PATH; do
      if [[ $dir != "$mise_data/command-wrappers/bin" && $dir != "$mise_data/shims" ]]; then
        path+="${path:+:}$dir"
      fi
    done
    PATH=$path type -P "$agent" >/dev/null
  }
  agent_present() { user_install || system_install || mise where "$agent_tool" &>/dev/null; }"""
assert 'agent_present() { user_install || system_install || mise where' in s or s.count(old) == 1, "default-agent agent_present anchor not found exactly once"
s = s.replace(old, new, 1)
# agent_install runs even when agent_present is true (it is the step
# after the present check, for --select and for the menu path), so a
# system install must skip the mise install too, or `mise use -g
# opencode` would download a mise copy over the pacman one.
old_install = """  agent_install() {
    user_install && return"""
new_install = """  agent_install() {
    # A system install is a real install too (pacman opencode, v1): do
    # not mise-install over it just because it is not in ~/.local/bin.
    user_install || system_install && return"""
assert "user_install || system_install && return" in s or s.count(old_install) == 1, "default-agent agent_install anchor not found exactly once"
s = s.replace(old_install, new_install, 1)
with open(path, "w") as f:
    f.write(s)
print("default-agent: system binary counts as present (pacman opencode, v1 behaviour)")
PY
  bash -n "$DA_FILE" || die "bash -n failed on patched $DA_FILE"
  info "  opencode: default-agent accepts a system install (no mise re-install over pacman opencode)"
else
  warn "  opencode: hexciri-default-agent not in fork output, system-install patch skipped"
fi

PANEL_QML="$FORK_OUT/shell/plugins/agents/Panel.qml"
if [ -f "$PANEL_QML" ]; then
  python3 - "$PANEL_QML" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()
old = """    if (id === otherInOpenCode) {
      openOpenCodeLogin()
      return
    }"""
new = """    if (id === otherInOpenCode) {
      openOpenCodeLogin()
      return
    }
    if (id === "opencode") {
      // OpenCode's free models need no account (v1 behaviour: install
      // and start using). Make it the default and open it instead of
      // the Console device login, which is for paid Go only. The Go
      // tile signs in as opencode and still reaches account-add below.
      var opencodeTile = signInProviders.find(function(p) { return p.providerId === "opencode" })
      makeDefault(opencodeTile, null)
      runLine(opencodeTile)
      return
    }"""
assert "OpenCode's free models need no account" in s or s.count(old) == 1, "Panel.qml chooseAddProvider anchor not found exactly once"
s = s.replace(old, new, 1) if "OpenCode's free models need no account" not in s else s
with open(path, "w") as f:
    f.write(s)
print("agents panel: plain OpenCode tile opens opencode with no sign-in (Go tile unchanged)")
PY
  info "  opencode: agents panel OpenCode tile opens opencode with no account (Go keeps device login)"
else
  warn "  opencode: agents Panel.qml not in fork output, panel patch skipped"
fi
