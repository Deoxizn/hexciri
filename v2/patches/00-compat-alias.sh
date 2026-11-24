#!/usr/bin/env bash
# Hexciri fork patch 00: wire the compat alias in, before placement.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/00-compat-alias.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "00-compat-alias.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Wire the compat alias in, before placement ---
# This was the missing step in Phase 1. Wiring happens on the fork output
# (user-owned temp dir), so placement then copies wired files to their targets.

step "Wiring hexciri-compat into launch-shell, env-bootstrap, and Hyprland Lua"

LAUNCH_SHELL="$FORK_OUT/bin/hexciri-launch-shell"
ENV_BOOTSTRAP="$FORK_OUT/default/bash/env-bootstrap"
HEXCIRI_LUA="$FORK_OUT/default/hypr/hexciri.lua"

if [ -f "$LAUNCH_SHELL" ]; then
  if head -1 "$LAUNCH_SHELL" | grep -q 'bash'; then
    python3 - "$LAUNCH_SHELL" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
line = 'source "$(dirname "$0")/hexciri-compat.sh" 2>/dev/null || source "/usr/share/hexciri/bin/hexciri-compat.sh" 2>/dev/null || true'
with open(path) as f:
    lines = f.read().splitlines()
if any("hexciri-compat.sh" in l for l in lines):
    print("launch-shell: compat source already present, skipping")
else:
    lines.insert(1, line)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("launch-shell: inserted compat source after shebang")
PY
    bash -n "$LAUNCH_SHELL" || die "bash -n failed on wired $LAUNCH_SHELL"
    info "Wired: hexciri-compat.sh sourced from hexciri-launch-shell"
  else
    warn "hexciri-launch-shell is not a bash script, skipping compat source insertion. Check its shebang manually."
  fi
else
  warn "hexciri-launch-shell not found in fork output, skipping compat wiring for it."
fi

if [ -f "$ENV_BOOTSTRAP" ]; then
  if ! grep -q 'hexciri-compat.sh' "$ENV_BOOTSTRAP"; then
    {
      echo ""
      echo "# Hexiri compat alias: OMARCHY_PATH is a runtime alias for HEXCIRI_PATH."
      echo 'source "/usr/share/hexciri/bin/hexciri-compat.sh" 2>/dev/null || true'
    } >> "$ENV_BOOTSTRAP"
    info "Wired: hexciri-compat.sh sourced from default/bash/env-bootstrap"
  else
    info "env-bootstrap: compat source already present, skipping"
  fi
elif [ -e "$ENV_BOOTSTRAP" ]; then
  warn "default/bash/env-bootstrap is not a regular file, skipping compat wiring for it."
else
  warn "default/bash/env-bootstrap not found in fork output, skipping compat wiring for it."
fi

if [ -f "$HEXCIRI_LUA" ]; then
  python3 - "$HEXCIRI_LUA" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
line = 'pcall(require, "default.hypr.hexciri-compat")'
with open(path) as f:
    content = f.read()
if "hexciri-compat" in content:
    print("hexciri.lua: compat require already present, skipping")
else:
    with open(path, "w") as f:
        f.write(line + "\n" + content)
    print("hexciri.lua: inserted compat require as first line")
# Hexciri custom binds (2026-11-24, Devi: Super+Ctrl+S bind never
# registered): default/hypr/bindings/hexciri.lua is placed but nothing
# in upstream's load chain requires default.hypr.bindings (the
# require_all loader), so the file never executed and none of its binds
# (Settings, web search, calculator, monocle, Brave incognito,
# Messenger, screen record) registered. Require it explicitly here,
# after the applications require. Do NOT require the whole
# bindings.lua loader: it would double-register every bindings file
# hexciri.lua already requires individually.
_anchor = 'require_optional.module("default.hypr.bindings.applications")'
_bindline = 'require("default.hypr.bindings.hexciri")  -- Hexciri custom binds: Super+Ctrl+S Settings, Super+Shift+S web search, Super+Shift+C calculator, monocle cycle, Brave incognito, Messenger, screen record'
with open(path) as f:
    _c = f.read()
if "default.hypr.bindings.hexciri" in _c:
    print("hexciri.lua: custom binds require already present, skipping")
elif _c.count(_anchor) == 1:
    with open(path, "w") as f:
        f.write(_c.replace(_anchor, _anchor + "\n" + _bindline, 1))
    print("hexciri.lua: custom binds require inserted after applications require")
else:
    print("WARN: applications require anchor not unique in hexciri.lua (count %d), custom binds NOT wired" % _c.count(_anchor))
PY
  # Syntax-only check: parse the file, never execute it. luac -p is the
  # correct tool for that. The old check used
  #   lua5.1 -e 'assert(loadfile(arg[1]))' file
  # which is a false failure: with -e, lua sets global arg to nil, so
  # arg[1] errors with "attempt to index global 'arg' (a nil value)"
  # on every file, even a syntactically valid one. It also made the
  # luac branch unreachable, since lua5.1 is installed whenever luac is.
  if command -v luac5.1 >/dev/null 2>&1; then
    luac5.1 -p "$HEXCIRI_LUA" || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (luac5.1 syntax OK)"
  elif command -v luac >/dev/null 2>&1; then
    luac -p "$HEXCIRI_LUA" || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (luac syntax OK)"
  elif command -v lua5.1 >/dev/null 2>&1; then
    # No luac: loadfile() parses without executing. Pass the path via an
    # env var, not arg[1], because arg is nil under lua -e.
    HEXCIRI_LUA_CHECK="$HEXCIRI_LUA" lua5.1 -e 'assert(loadfile(os.getenv("HEXCIRI_LUA_CHECK")))' || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (lua5.1 syntax OK)"
  else
    warn "No luac5.1/luac/lua5.1 binary found, skipping Lua syntax check on wired hexciri.lua."
  fi
else
  die "default/hypr/hexciri.lua not found in fork output, cannot wire compat require."
fi

# Defence in depth for the emergency-mode bug: bootstrap.lua is dofile'd by
# config/hypr/hyprland.lua BEFORE it requires default.hypr.omarchy, so a
# package.preload alias there catches any require of the old module name
# that the rewrite above missed, e.g. in a user config or a third-party
# module, and resolves it to default.hypr.hexciri. No file named omarchy
# is created. This runs from tty with no GUI, like the rest of the installer.
BOOTSTRAP_LUA="$FORK_OUT/default/hypr/bootstrap.lua"
if [ -f "$BOOTSTRAP_LUA" ]; then
  python3 - "$BOOTSTRAP_LUA" <<'PY' >>"$_patch_log"
import os, sys
path = sys.argv[1]
alias = (
    '\n-- Hexiri compat: legacy module name default.hypr.omarchy resolves to\n'
    '-- default.hypr.hexciri. This is the defence in depth for the Hyprland\n'
    '-- emergency mode on the first live boot, when hyprland.lua still\n'
    '-- required the old name after the file had been renamed.\n'
    'package.preload["default.hypr.omarchy"] = function() return require("default.hypr.hexciri") end\n'
    'package.preload["omarchy.current.theme.hyprland"] = function() return require("hexciri.current.theme.hyprland") end\n'
)
with open(path) as f:
    content = f.read()
if 'package.preload["default.hypr.omarchy"]' in content:
    print("bootstrap.lua: legacy module preload alias already present, skipping")
else:
    # Atomic write (2026-11-24, second breakage): a plain open(path, "w")
    # truncates the file first, so any failure mid-write leaves a
    # 0-byte bootstrap.lua that passes every -f check and bricks the
    # next boot. Write to a temp file and rename into place instead.
    tmp = path + ".hexciri-tmp"
    with open(tmp, "w") as f:
        f.write(content.rstrip("\n") + "\n" + alias)
    os.replace(tmp, path)
    print("bootstrap.lua: added legacy module preload alias for default.hypr.omarchy")
PY
  # Verify the wired file, don't trust the write: a corrupt bootstrap.lua
  # here ships straight into the installed tree and bricks the next boot.
  if ! bootstrap_ok "$BOOTSTRAP_LUA" || ! grep -q 'package.preload\["default.hypr.omarchy"\]' "$BOOTSTRAP_LUA"; then
    die "wired bootstrap.lua is missing, empty or truncated after the preload alias patch, refusing to continue with a broken fork."
  fi
  if command -v luac5.1 >/dev/null 2>&1; then
    luac5.1 -p "$BOOTSTRAP_LUA" && info "bootstrap.lua preload alias added (luac5.1 syntax OK)" || die "luac5.1 syntax check failed on wired bootstrap.lua, refusing to ship a broken Hyprland config."
  elif command -v luac >/dev/null 2>&1; then
    luac -p "$BOOTSTRAP_LUA" && info "bootstrap.lua preload alias added (luac syntax OK)" || die "luac syntax check failed on wired bootstrap.lua, refusing to ship a broken Hyprland config."
  else
    info "bootstrap.lua preload alias added, no luac binary to syntax-check it with."
  fi
else
  die "default/hypr/bootstrap.lua not found in fork output, cannot wire the legacy module preload alias. Refusing to continue with a broken fork."
fi
