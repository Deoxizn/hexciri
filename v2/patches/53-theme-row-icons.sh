#!/usr/bin/env bash
# Hexciri fork patch 53: icons for the theme menu rows (Devi 2026-11-27).
# Hexciri-original (no upstream PR).
#
# Patch 51 added three theme-related menu rows with icon:"" deliberately
# empty (a wrong Nerd Font codepoint renders a tofu box, and the sim cannot
# verify glyph rendering). Devi wants the little palette icon on them,
# matching all the current theme list entries:
#   update.themes-sync ("Sync Themes List")  <- update.themes ("Extra Themes")
#   update.icons-sync  ("Sync Theme Icons")  <- update.icons  ("Extra Icons")
#   setup.config.themes-list ("Themes list") <- update.themes (palette icon)
#
# The icons are NOT baked into this patch. The patch reads the sibling row's
# icon value from the live menu file at apply time and writes that exact
# value onto the target row, so the new rows always match their siblings
# even if a theme or upstream change alters the sibling icon later.
#
# NEVER retype a PUA icon glyph: the anchor rows carry raw Nerd Font PUA
# glyphs that must not be retyped (patch 36/40 lesson), so this patch
# locates rows by their unique dotted key (e.g. "update.themes":) and
# asserts the key occurs exactly once, instead of matching the full line.
# The icon itself is copied programmatically and written with
# json.dumps(ensure_ascii=False), so the file keeps its raw-glyph style.
#
# Standalone: bash v2/patches/53-theme-row-icons.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "53-theme-row-icons.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "53-theme-row-icons.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. Menu icons (default/hexciri/hexciri-menu.jsonc) ---
# The python block prints one "patched: ..." line per icon it sets (or an
# "already present, skipping" line); output goes through a temp file, not
# straight to $_patch_log, so a trailing info line cannot clobber it
# (patch 50's pattern).
step "Setting theme-row icons in the menu (copied from sibling rows)"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 53 menu edit failed"; }
import json
import re
import sys

fork = sys.argv[1]
menu = fork + "/default/hexciri/hexciri-menu.jsonc"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


# (target row, sibling row to copy the icon from, expected label).
# Sync Themes List and Themes list take the Extra Themes palette icon;
# Sync Theme Icons takes the Extra Icons icon.
PAIRS = [
    ("update.themes-sync", "update.themes", "Sync Themes List"),
    ("update.icons-sync", "update.icons", "Sync Theme Icons"),
    ("setup.config.themes-list", "update.themes", "Themes list"),
]

try:
    with open(menu, encoding="utf-8") as f:
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


def parse_menu(raw):
    stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
    stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
    try:
        return json.loads(stripped)
    except Exception as e:  # noqa: BLE001 - any parse failure is fatal here
        _die("menu jsonc does not parse, shell would show an empty menu: %s" % e)


parsed = parse_menu("\n".join(lines) + "\n")

changed = []
for target, sibling, label in PAIRS:
    sib = parsed.get(sibling)
    if sib is None:
        _die('menu jsonc missing sibling row %s' % sibling)
    icon = sib.get("icon")
    if not icon:
        _die('sibling row %s has no icon to copy' % sibling)
    tgt = parsed.get(target)
    if tgt is None:
        _die('menu jsonc missing target row %s (patch 51 must be applied first)' % target)
    if tgt.get("label") != label:
        _die('target row %s label is %r, want %r' % (target, tgt.get("label"), label))
    want = '"icon":' + json.dumps(icon, ensure_ascii=False)
    i = key_index(target)
    if i is None:
        _die('menu key "%s" not found in menu jsonc' % target)
    if want in lines[i]:
        print("menu: icon for %s already present, skipping" % target)
    elif '"icon":""' in lines[i]:
        lines[i] = lines[i].replace('"icon":""', want, 1)
        changed.append(target)
        print("patched: icon for %s (copied from %s)" % (target, sibling))
    else:
        _die('target row %s has an unexpected icon value, refusing to clobber: %s'
             % (target, lines[i].strip()))

with open(menu, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

# --- validation: the jsonc must still parse exactly like the shell parses
# it (patch 02's check). One bad row empties the whole Super+Alt+Space menu.
with open(menu, encoding="utf-8") as f:
    raw = f.read()
parsed = parse_menu(raw)
for r in ("apps", "appearance", "trigger", "setup", "install", "remove",
          "update", "learn", "system"):
    if r not in parsed:
        _die("menu jsonc missing root entry %s, shell would show an empty menu" % r)
for target, sibling, label in PAIRS:
    row = parsed.get(target)
    if row is None:
        _die("menu jsonc missing row %s after edit" % target)
    if row.get("icon") != parsed[sibling].get("icon"):
        _die("row %s icon %r does not match sibling %s icon %r"
             % (target, row.get("icon"), sibling, parsed[sibling].get("icon")))
    if row.get("label") != label:
        _die("row %s label changed to %r, want %r" % (target, row.get("label"), label))
    if raw.count('"%s":' % target) != 1:
        _die('menu key "%s" occurs %d times in the file'
             % (target, raw.count('"%s":' % target)))
print("menu jsonc parses (%d entries, 9 root entries, 3 theme-row icons set)"
      % len(parsed))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'theme-row icons patch: %d menu row icons applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 53: theme menu rows get their sibling icons (palette / Extra Icons)"
