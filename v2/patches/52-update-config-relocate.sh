#!/usr/bin/env bash
# Hexciri fork patch 52: relocate Update > Config to Setup > Config as
# "Factory Reset", plus an All-configs row (Devi 2026-11-27).
# Hexciri-original (no upstream PR).
#
# The Update menu carried an upstream "Config" submenu ("Reset to
# default") with per-component refresh rows: Hyprland, Hyprsunset, Tmux,
# Shell. Config does not belong in Update, but the rows are useful: each
# refresh command resets that component's config to the shipped default,
# so the submenu moves to Setup > Config relabeled "Factory Reset", which
# says what it does. The four rows move byte-identical except for the
# dotted key (the parent's label changes Config -> Factory Reset, its
# "Reset to default" title carries over); the refresh bins themselves are
# untouched. A fifth row is added under the new header: "All configs",
# running hexciri-reinstall-configs, which resets ALL user configs and
# shipped defaults in $HOME (destructive, replays /etc/skel, then
# refresh-limine/plymouth). That command has no internal confirmation
# prompt and the menu has no gum-confirm convention on rows, so it runs
# directly in a floating terminal like its siblings; the label and the
# submenu header make the scope clear before it is picked.
#
# Anchoring note (patch 36/40 lesson): the moved rows carry raw Nerd Font
# PUA icon glyphs that must not be retyped, so this patch locates them by
# their unique dotted key (e.g. "update.config":) and rewrites only the
# key prefix in the line text, never the rest of the line. A missing or
# duplicated key dies loudly, as does a half-moved state.
#
# Standalone: bash v2/patches/52-update-config-relocate.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-relocated tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "52-update-config-relocate.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "52-update-config-relocate.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. The reinstall-configs bin must ship in the fork ---
# The new "All configs" row calls hexciri-reinstall-configs; it only
# exists in FORK_OUT/bin when install.sh's allowlist carries it.
grep -q 'reinstall-configs' "$HEXCIRI_REPO_ROOT/v2/install.sh" 2>/dev/null || die "v2/install.sh does not list reinstall-configs in the bin allowlist, the All configs row would call a missing command"

# --- 2. Relocate the Config subtree in the menu jsonc ---
# The python block prints one "patched: ..." line (or an "already present,
# skipping" line); output goes through a temp file, not straight to
# $_patch_log, so a trailing info line cannot clobber it (patch 50's
# pattern).
step "Relocating Update > Config to Setup > Config as Factory Reset"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 52 menu edit failed"; }
import json
import re
import sys

fork = sys.argv[1]
menu = fork + "/default/hexciri/hexciri-menu.jsonc"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


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


OLD_KEYS = ["update.config", "update.config.hyprland", "update.config.hyprsunset",
            "update.config.tmux", "update.config.shell"]
NEW_PARENT = "setup.config.factory-reset"
NEW_KEYS = [NEW_PARENT, NEW_PARENT + ".hyprland", NEW_PARENT + ".hyprsunset",
            NEW_PARENT + ".tmux", NEW_PARENT + ".shell", NEW_PARENT + ".all"]
# Expected actions of the four moved rows, unchanged by the move.
EXPECTED_ACTIONS = {
    NEW_PARENT + ".hyprland": "hexciri-launch-floating-terminal-with-presentation hexciri-refresh-hyprland",
    NEW_PARENT + ".hyprsunset": "hexciri-launch-floating-terminal-with-presentation hexciri-refresh-hyprsunset",
    NEW_PARENT + ".tmux": "hexciri-launch-floating-terminal-with-presentation hexciri-refresh-tmux",
    NEW_PARENT + ".shell": "hexciri-launch-floating-terminal-with-presentation hexciri-refresh-shell",
}
ALL_ROW = ('  "setup.config.factory-reset.all": {"icon":"","label":"All configs",'
           '"action":"hexciri-launch-floating-terminal-with-presentation hexciri-reinstall-configs"},')

old_idx = {k: key_index(k) for k in OLD_KEYS}
new_idx = {k: key_index(k) for k in NEW_KEYS}
changed = []

if all(v is None for v in old_idx.values()) and all(v is not None for v in new_idx.values()):
    print("menu: Factory Reset rows already present, Config rows already gone, skipping")
else:
    if any(v is None for v in old_idx.values()):
        _die("update.config subtree is half-present (missing %s), refusing to guess"
             % [k for k, v in old_idx.items() if v is None])
    if any(v is not None for v in new_idx.values()):
        _die("factory-reset rows already present while update.config still exists, refusing to guess")
    # Build the new block from the old lines: only the dotted key prefix
    # changes (plus the parent label), icons and actions stay byte-exact.
    new_lines = []
    for k in OLD_KEYS:
        line = lines[old_idx[k]]
        new_line = re.sub(r'^(\s*)"update\.config((?:\.[a-z]+)?)":',
                          r'\1"setup.config.factory-reset\2":', line, count=1)
        if new_line == line:
            _die('could not rewrite key on line for "%s": %r' % (k, line))
        if k == "update.config":
            new_line = new_line.replace('"label":"Config"', '"label":"Factory Reset"', 1)
            if '"label":"Factory Reset"' not in new_line:
                _die('parent row label is not "Config": %r' % line)
        new_lines.append(new_line)
    new_lines.append(ALL_ROW)
    anchor = key_index("setup.config.themes-list")
    if anchor is None:
        _die('anchor "setup.config.themes-list" not found in menu jsonc')
    for i in sorted(old_idx.values(), reverse=True):
        del lines[i]
    anchor = key_index("setup.config.themes-list")
    lines[anchor + 1:anchor + 1] = new_lines
    changed.append("Factory Reset rows in Setup > Config")
    print("patched: Config subtree moved from Update to Setup > Config as Factory Reset (4 refresh rows + All configs)")

with open(menu, "w") as f:
    f.write("\n".join(lines) + "\n")

# --- validation: the jsonc must still parse exactly like the shell parses
# it (patch 02's check). One bad row empties the whole Super+Alt+Space menu.
with open(menu) as f:
    raw = f.read()
stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
try:
    parsed = json.loads(stripped)
except Exception as e:  # noqa: BLE001 - any parse failure is fatal here
    _die("menu jsonc does not parse, shell would show an empty menu: %s" % e)
for r in ("apps", "appearance", "trigger", "setup", "install", "remove",
          "update", "learn", "system"):
    if r not in parsed:
        _die("menu jsonc missing root entry %s, shell would show an empty menu" % r)


def _row(key):
    row = parsed.get(key)
    if row is None:
        _die("menu jsonc missing row %s" % key)
    return row


# The old subtree must be gone entirely.
for key in OLD_KEYS:
    if parsed.get(key) is not None:
        _die("menu jsonc still has old row %s" % key)
    if raw.count('"%s":' % key) != 0:
        _die('menu key "%s" still occurs in the file' % key)
# The new subtree must be present with the moved actions intact.
parent = _row(NEW_PARENT)
if parent.get("label") != "Factory Reset":
    _die("factory-reset parent label is %r, want 'Factory Reset'" % parent.get("label"))
if parent.get("title") != "Reset to default":
    _die("factory-reset parent title is %r, want 'Reset to default'" % parent.get("title"))
for key, action in EXPECTED_ACTIONS.items():
    row = _row(key)
    if row.get("action") != action:
        _die("moved row %s action changed: %r" % (key, row.get("action")))
all_row = _row(NEW_PARENT + ".all")
if all_row.get("label") != "All configs":
    _die("all-configs row label is %r, want 'All configs'" % all_row.get("label"))
if "hexciri-reinstall-configs" not in all_row.get("action", ""):
    _die("all-configs row does not call hexciri-reinstall-configs")
# Patch 51's rows must be untouched by this move.
for key in ("setup.config.search-provider", "setup.config.themes-list",
            "update.themes-sync", "update.icons-sync"):
    if parsed.get(key) is None:
        _die("menu jsonc lost patch 51 row %s" % key)
# No duplicate keys: json.loads keeps the last, so count in the raw text.
for key in NEW_KEYS:
    if raw.count('"%s":' % key) != 1:
        _die('menu key "%s" occurs %d times in the file'
             % (key, raw.count('"%s":' % key)))
print("menu jsonc parses (%d entries, 9 root entries, no update.config rows)"
      % len(parsed))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'update config relocate patch: %d menu row blocks applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 52: Config subtree moved from Update to Setup > Config as Factory Reset, All configs row added"
