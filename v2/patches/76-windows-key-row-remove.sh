#!/usr/bin/env bash
# Hexciri fork patch 76: move the Windows product key row to Setup (Devi 2026-11-27).
# REVISED 2026-11-27: the first version of this patch DELETED the row.
# Devi then said to move it to Setup instead of removing it, so this
# version moves it: the "system.windows-key" row leaves the System
# (Super+Esc) menu and becomes "setup.windows-key", the last row of
# the Setup block. Label and action are unchanged, icon stays "".
#
# Why the move, and why here: patch 74 put the row in System, Devi
# does not want it there. Setup is where system-ish utilities live.
#
# Scope: the ROW only. bin/hexciri-windows-key stays (patch 74 bin +
# patch 75 wider sweep), the windows-key allowlist entry stays, and
# the retrieval still works from a terminal:
#   hexciri-windows-key
# No install.sh companion edit, no other menu change.
#
# The row's icon value does not matter to this patch: patch 75's
# icon edit (copy the Windows VM entry's glyph) was REMOVED from
# patch 75 after it aborted a live update -- the upstream source tree
# it looked the glyph up in does not exist next to FORK_OUT in update
# mode. The live row therefore has icon:"" (patch 74 as shipped).
# The move anchors on the dotted keys and the label/action only, so
# it works whatever the icon holds.
#
# Placement: the new row goes directly after the LAST "setup."-prefixed
# line in the file, i.e. the end of the Setup block (a blank line and
# the // Install comment follow it in the current menu). The patch
# dies loudly if the Setup block cannot be found unambiguously.
#
# Standalone: bash v2/patches/76-windows-key-row-remove.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   a tree where the row already sits in Setup prints "already moved,
#   skipping" and changes nothing.

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

# --- 1. Move system.windows-key to setup.windows-key ---
# The python block prints one "patched: ..." line (or an "already
# moved, skipping" line); output goes through a temp file, not
# straight to $_patch_log, so a trailing info line cannot clobber it
# (patch 50's pattern).
step "Moving Windows product key row from System to Setup"
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


OLD_KEY = "system.windows-key"
NEW_KEY = "setup.windows-key"
NEW_ROW = ('  "setup.windows-key": {"icon":"","label":"Windows product key",'
           '"action":"hexciri-launch-floating-terminal-with-presentation hexciri-windows-key"},')
TARGET_ACTION = "hexciri-launch-floating-terminal-with-presentation hexciri-windows-key"

try:
    with open(menu) as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output, patch 02 must be applied first" % menu)


def key_indices(key):
    """All indices of lines carrying dotted key `key`."""
    return [i for i, l in enumerate(lines) if ('"%s":' % key) in l]


old_hits = key_indices(OLD_KEY)
new_hits = key_indices(NEW_KEY)
if len(old_hits) > 1:
    _die('menu key "%s" occurs %d times, refusing to guess' % (OLD_KEY, len(old_hits)))
if len(new_hits) > 1:
    _die('menu key "%s" occurs %d times, refusing to guess' % (NEW_KEY, len(new_hits)))
if old_hits and new_hits:
    _die('both "%s" and "%s" exist: the move already happened halfway, refusing to guess'
         % (OLD_KEY, NEW_KEY))
if not old_hits and not new_hits:
    _die('neither "%s" nor "%s" exists: patch 74 must be applied first' % (OLD_KEY, NEW_KEY))
if not old_hits:
    print("menu: Windows product key row already moved to Setup, skipping")
else:
    old_line = lines[old_hits[0]]
    if '"label":"Windows product key"' not in old_line and '"label": "Windows product key"' not in old_line:
        _die('old row is not the Windows product key row: %r' % old_line)
    if TARGET_ACTION not in old_line:
        _die('old row action changed: %r' % old_line)
    # Last "setup."-prefixed line = end of the Setup block. The new row
    # goes directly after it.
    setup_hits = [i for i, l in enumerate(lines)
                  if re.search(r'"setup\.[^"]*":', l)]
    if not setup_hits:
        _die('no "setup." rows in the menu: cannot place the moved row')
    last_setup = setup_hits[-1]
    del lines[old_hits[0]]
    # Deleting a line above the insert point shifts it down by one.
    if old_hits[0] < last_setup:
        last_setup -= 1
    lines[last_setup + 1:last_setup + 1] = [NEW_ROW]
    with open(menu, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("patched: Windows product key row moved from System to Setup")

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
if OLD_KEY in parsed:
    _die("menu jsonc still contains row %s after the move" % OLD_KEY)
if raw.count('"%s":' % OLD_KEY) != 0:
    _die('menu key "%s" still occurs %d times in the file'
         % (OLD_KEY, raw.count('"%s":' % OLD_KEY)))
row = parsed.get(NEW_KEY)
if row is None:
    _die("menu jsonc missing row %s after the move" % NEW_KEY)
if row.get("label") != "Windows product key":
    _die("moved row label is %r, want 'Windows product key'" % row.get("label"))
if row.get("action") != TARGET_ACTION:
    _die("moved row action is %r, want %r" % (row.get("action"), TARGET_ACTION))
if raw.count('"%s":' % NEW_KEY) != 1:
    _die('menu key "%s" occurs %d times in the file'
         % (NEW_KEY, raw.count('"%s":' % NEW_KEY)))
# The moved row must be the LAST setup.* row, and the System neighbours
# must be adjacent again (the old row sat between them).
lines = raw.splitlines()
setup_idx = [i for i, l in enumerate(lines) if re.search(r'"setup\.[^"]*":', l)]
new_idx = [i for i, l in enumerate(lines) if ('"%s":' % NEW_KEY) in l]
if new_idx != [setup_idx[-1]]:
    _die("moved row is not the last setup.* row (setup rows end at line %d, "
         "moved row at line %d)" % (setup_idx[-1], new_idx[0] if new_idx else -1))
lock = [i for i, l in enumerate(lines) if '"system.lock":' in l]
susp = [i for i, l in enumerate(lines) if '"system.suspend":' in l]
if len(lock) != 1 or len(susp) != 1:
    _die("neighbour rows system.lock / system.suspend not found exactly once")
if susp[0] != lock[0] + 1:
    _die("system.suspend is not directly after system.lock after the move "
         "(lock=%d suspend=%d): the delete removed the wrong line" % (lock[0], susp[0]))
print("menu jsonc parses (%d entries, 9 root entries, system.windows-key gone, "
      "setup.windows-key last in Setup, system.lock directly followed by "
      "system.suspend)" % len(parsed))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'windows-key row move patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 76: Windows product key row moved from System to Setup (bin/hexciri-windows-key still works from a terminal)"
