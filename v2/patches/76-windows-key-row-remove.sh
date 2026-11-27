#!/usr/bin/env bash
# Hexciri fork patch 76: remove the System > Windows product key row (Devi 2026-11-27).
# Patch 74 added the row (System menu, after system.lock) so the key
# could be retrieved from the menu. Devi: it does not belong in the
# Super+Esc (System) menu -- remove it. One edit: delete the
# "system.windows-key" row from default/hexciri/hexciri-menu.jsonc.
#
# Scope: the ROW only. bin/hexciri-windows-key stays (patch 74 bin +
# patch 75 wider sweep), the windows-key allowlist entry stays, and
# the retrieval still works from a terminal:
#   hexciri-windows-key
# No install.sh companion edit, no other menu change.
#
# The row's icon value does not matter to this patch: patch 75 copied
# the Windows VM entry's glyph onto it, but the delete anchors on the
# dotted key "system.windows-key" only, so it removes the row whether
# the icon is the copied glyph, "" (patch 74 as shipped), or anything
# else. The row must occur exactly once; zero occurrences means an
# already-removed tree and the patch skips (idempotent), more than one
# dies loudly. The row is a middle entry (system.lock before it,
# system.suspend after it), so deleting its line leaves valid JSONC --
# the validation parse below proves it.
#
# Standalone: bash v2/patches/76-windows-key-row-remove.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   a tree without the row prints "already removed, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "76-windows-key-row-remove.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "76-windows-key-row-remove.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. Delete the system.windows-key row from the menu ---
# The python block prints one "patched: ..." line (or an "already
# removed, skipping" line); output goes through a temp file, not
# straight to $_patch_log, so a trailing info line cannot clobber it
# (patch 50's pattern).
step "Removing System > Windows product key menu row"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 76 menu edit failed"; }
import json
import re
import sys

fork = sys.argv[1]
menu = fork + "/default/hexciri/hexciri-menu.jsonc"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


TARGET_KEY = "system.windows-key"
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
    print("menu: Windows product key row already removed, skipping")
else:
    tgt_line = lines[tgt]
    if '"label":"Windows product key"' not in tgt_line and '"label": "Windows product key"' not in tgt_line:
        _die('target row is not the Windows product key row: %r' % tgt_line)
    if TARGET_ACTION not in tgt_line:
        _die('target row action changed: %r' % tgt_line)
    del lines[tgt]
    with open(menu, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("patched: Windows product key row removed from System menu")

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
if TARGET_KEY in parsed:
    _die("menu jsonc still contains row %s after the delete" % TARGET_KEY)
if raw.count('"%s":' % TARGET_KEY) != 0:
    _die('menu key "%s" still occurs %d times in the file'
         % (TARGET_KEY, raw.count('"%s":' % TARGET_KEY)))
# The neighbours must still be there, in order: the row sat between
# system.lock and system.suspend.
lock = key_index("system.lock")
susp = key_index("system.suspend")
if lock is None or susp is None:
    _die("neighbour rows system.lock / system.suspend missing after the delete")
if susp != lock + 1:
    _die("system.suspend is not directly after system.lock after the delete "
         "(lock=%d suspend=%d): the delete removed the wrong line" % (lock, susp))
print("menu jsonc parses (%d entries, 9 root entries, system.windows-key gone, "
      "system.lock directly followed by system.suspend)" % len(parsed))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'windows-key row removal patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 76: System > Windows product key row removed (bin/hexciri-windows-key still works from a terminal)"
