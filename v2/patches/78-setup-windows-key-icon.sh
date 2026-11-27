#!/usr/bin/env bash
# Hexciri fork patch 78: give the Setup > Windows product key row the
# Windows VM entry's icon (Devi 2026-11-27).
# The row (setup.windows-key, moved there by patch 76) has icon:"".
# This patch sets its icon to the install.windows row's glyph.
#
# How the glyph gets here, and why this cannot abort an update the
# way patch 75's icon edit did: patch 75 copied the icon from the
# upstream source tree next to FORK_OUT, which does not exist in
# update mode, so the edit died and aborted the whole update. This
# patch does NO lookup at all. The glyph value was measured from the
# live upstream menu file (omacom/omarchy quattro,
# default/omarchy/omarchy-menu.jsonc, install.windows row) on
# 2026-11-27: exactly one character, codepoint U+F0372. The patch
# writes it from the codepoint (chr(0xF0372)) -- never retyped from
# memory, never pasted as a literal PUA char -- and the sim verifies
# the resulting byte is identical to the upstream file's glyph.
#
# Scope: the icon field of the setup.windows-key row ONLY. Label,
# action, and placement are untouched. No install.sh companion edit,
# no other menu change.
#
# Standalone: bash v2/patches/78-setup-windows-key-icon.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   a tree whose row already has the glyph prints "already set,
#   skipping" and changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "78-setup-windows-key-icon.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "78-setup-windows-key-icon.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. Set the setup.windows-key row's icon to U+F0372 ---
# The python block prints one "patched: ..." line (or an "already
# set, skipping" line); output goes through a temp file, not
# straight to $_patch_log, so a trailing info line cannot clobber it
# (patch 50's pattern).
step "Giving Setup > Windows product key the Windows VM entry icon"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 78 menu icon edit failed"; }
import json
import re
import sys

fork = sys.argv[1]
menu = fork + "/default/hexciri/hexciri-menu.jsonc"

# Measured 2026-11-27 from the live upstream menu (omacom/omarchy
# quattro, install.windows row): one char, U+F0372. Written from the
# codepoint, never retyped as a literal.
ICON = chr(0xF0372)


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


TARGET_KEY = "setup.windows-key"
TARGET_ACTION = "hexciri-launch-floating-terminal-with-presentation hexciri-windows-key"

try:
    with open(menu) as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output, patch 02 must be applied first" % menu)


def key_index(key):
    """Index of the line carrying dotted key `key`, or None. Dies if the
    key occurs more than once: the anchor must be unambiguous."""
    hits = [i for i, l in enumerate(lines) if ('"%s":' % key) in l]
    if len(hits) > 1:
        _die('menu key "%s" occurs %d times, refusing to guess' % (key, len(hits)))
    return hits[0] if hits else None


tgt = key_index(TARGET_KEY)
if tgt is None:
    _die('target row "setup.windows-key" not found in menu jsonc, patch 76 must be applied first')
tgt_line = lines[tgt]
if '"label":"Windows product key"' not in tgt_line and '"label": "Windows product key"' not in tgt_line:
    _die('target row is not the Windows product key row: %r' % tgt_line)
if TARGET_ACTION not in tgt_line:
    _die('target row action changed: %r' % tgt_line)
tm = re.search(r'"icon"\s*:\s*"([^"]*)"', tgt_line)
if not tm:
    _die('target row has no icon field to set: %r' % tgt_line)
if tm.group(1) == ICON:
    print("menu: Windows product key icon already set, skipping")
elif tm.group(1) != "":
    _die('target row already has a different non-empty icon %r, refusing to overwrite' % tm.group(1))
else:
    lines[tgt] = tgt_line[:tm.start(1)] + ICON + tgt_line[tm.end(1):]
    with open(menu, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("patched: Windows product key row icon set to U+F0372")

# --- validation: the jsonc must still parse exactly like the shell parses
# it (patch 02's check). One bad row empties the whole Super+Alt+Space menu.
with open(menu) as f:
    raw = f.read()
stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
stripped = re.sub(r',(\s*[\}\]])', r'\1', stripped)
try:
    parsed = json.loads(stripped)
except Exception as e:  # noqa: BLE001 - any parse failure is fatal here
    _die("menu jsonc does not parse, shell would show an empty menu: %s" % e)
for r in ("apps", "appearance", "trigger", "setup", "install", "remove",
          "update", "learn", "system"):
    if r not in parsed:
        _die("menu jsonc missing root entry %s, shell would show an empty menu" % r)
row = parsed.get(TARGET_KEY)
if row is None:
    _die("menu jsonc missing row %s" % TARGET_KEY)
if row.get("label") != "Windows product key":
    _die("windows-key row label is %r, want 'Windows product key'" % row.get("label"))
if row.get("action") != TARGET_ACTION:
    _die("windows-key row action is %r, want %r" % (row.get("action"), TARGET_ACTION))
if row.get("icon") != ICON:
    _die("windows-key row icon is %r, want U+F0372" % row.get("icon"))
if raw.count('"%s":' % TARGET_KEY) != 1:
    _die('menu key "%s" occurs %d times in the file'
         % (TARGET_KEY, raw.count('"%s":' % TARGET_KEY)))
print("menu jsonc parses (%d entries, 9 root entries, setup.windows-key icon U+F0372)"
      % len(parsed))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'windows-key icon patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 78: Setup > Windows product key row icon set to U+F0372 (measured from the upstream install.windows row)"
