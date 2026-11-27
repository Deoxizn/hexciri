#!/usr/bin/env bash
# Hexciri fork patch 51: search-provider picker + Setup > Config rows + Update sync rows (Devi 2026-11-27).
# Hexciri-original (no upstream PR): V2 has Super+Shift+S search but no way
# to change the provider, like V1 had (bin/hexciri-search-provider, fuzzel).
#
# Change 1 -- the picker itself (repo file, not a fork file).
# bin/hexciri-search-provider is rewritten for v2: same state file
# (~/.local/state/hexciri/search-provider), same NAME-argument path, same
# notify-send, but the provider table now comes from v2/hexciri-web-search
# (`providers` subcommand) instead of hexciri-fuzzel, and the no-arg picker
# is gum choose in a terminal (gum is in hexciri-base.packages) instead of
# fuzzel --dmenu. This patch only bash -n checks the script; the updater's
# git sync + ~/.local/bin symlink refresh deploys repo bin/ scripts, so no
# install step is needed here.
#
# Change 2 -- Setup > Config rows (default/hexciri/hexciri-menu.jsonc).
# After setup.config.xcompose, the last Config child: a "Search provider"
# submenu header, one child row per provider from the live
# hexciri-web-search table (label from the table, checked expression reads
# the state file with a google fallback, action hexciri-search-provider
# <name>), then a "Themes list" row that opens ~/.config/hexciri/themes.list
# in the editor, following the sibling rows' hexciri-launch-editor
# convention. The picker rows follow the Setup > Defaults choose-one-of-N
# pattern (per-option checked + plain setter action); the QS menu is the
# V2-native picker, no Settings tab, no fuzzel. The child rows are
# GENERATED from the provider table at apply time, not baked in, so a later
# table change regenerates them on the next update instead of drifting.
# New rows use icon:"" deliberately: a missing icon renders cleanly (the
# submenu headers already do this), a wrong Nerd Font codepoint would render
# a tofu box, and the sim cannot verify glyph rendering.
#
# Change 3 -- Update sync rows (same jsonc).
# After update.themes ("Extra Themes"): "Sync Themes List", which runs
# `hexciri theme sync` (reads ~/.config/hexciri/themes.list, the static
# extra-themes file) in a floating terminal. After update.icons
# ("Extra Icons"): "Sync Theme Icons", which runs `hexciri icons sync`
# (the patch-48 icon theming sync). These RUN the syncs; the Setup >
# Config "Themes list" row only OPENS the file for editing. Neither new row
# takes a `when` guard, so both always show: the Extra Themes row's guard
# (hexciri-theme-extras, exit 1 bare) would hide them if copied. The
# existing update.themes / update.icons rows are NOT repointed: they update
# theme/icon-set extras, a different mechanism from the themes.list sync.
#
# Anchoring note (patch 36/40 lesson): the three anchor rows carry raw
# Nerd Font PUA icon glyphs that must not be retyped, so this patch locates
# anchors by their unique dotted key (e.g. "setup.config.xcompose":) and
# asserts the key occurs exactly once, instead of matching the full line.
# The inserted lines themselves contain no glyphs, so they are matched
# exactly on re-run.
#
# Standalone: bash v2/patches/51-search-provider.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "51-search-provider.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "51-search-provider.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. Companion files must exist in the installer tree ---
# v2/hexciri-web-search carries the provider table this patch generates
# rows from; bin/hexciri-search-provider is the picker the new rows call.
# Both are repo files (patch 08's pattern: die rather than ship stale).
WS="$HEXCIRI_REPO_ROOT/v2/hexciri-web-search"
[ -f "$WS" ] || die "v2/hexciri-web-search not in the installer tree ($WS), search provider rows cannot be generated"
PICKER="$HEXCIRI_REPO_ROOT/bin/hexciri-search-provider"
[ -f "$PICKER" ] || die "bin/hexciri-search-provider not in the installer tree ($PICKER), the menu rows would call a missing script"
bash -n "$WS" || die "bash -n failed on v2/hexciri-web-search"
bash -n "$PICKER" || die "bash -n failed on bin/hexciri-search-provider"

# --- 2. Menu rows (Setup > Config + Update) ---
# The python block prints one "patched: ..." line per applied row block
# (or an "already present, skipping" line); output goes through a temp
# file, not straight to $_patch_log, so a trailing info line cannot
# clobber it (patch 50's pattern).
step "Patching search provider picker rows + theme sync rows into the menu"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" "$WS" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 51 menu edit failed"; }
import json
import re
import subprocess
import sys

fork = sys.argv[1]
ws = sys.argv[2]
menu = fork + "/default/hexciri/hexciri-menu.jsonc"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


# Providers: run the live table, never a baked copy. One line per provider,
# name<TAB>label<TAB>url, LC_ALL=C sorted by the script itself.
try:
    proc = subprocess.run(["bash", ws, "providers"],
                          capture_output=True, text=True, timeout=30)
except Exception as e:  # noqa: BLE001 - any launch failure is fatal here
    _die("could not run hexciri-web-search providers: %s" % e)
if proc.returncode != 0:
    _die("hexciri-web-search providers failed (exit %d): %s"
         % (proc.returncode, proc.stderr.strip()))
providers = []
seen = set()
for line in proc.stdout.splitlines():
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        _die("hexciri-web-search providers line has %d fields, want 3: %r"
             % (len(parts), line))
    name, label, _url = parts
    if not re.fullmatch(r"[a-z0-9]+", name):
        _die("provider name is not [a-z0-9]+: %r" % name)
    if not label or '"' in label or "\\" in label:
        _die("provider label is empty or needs JSON escaping: %r" % label)
    if name in seen:
        _die("duplicate provider name: %r" % name)
    seen.add(name)
    providers.append((name, label))
if not providers:
    _die("hexciri-web-search providers listed no providers")

# Checked expression, same shape as the Setup > Defaults browser rows:
# [[ "$(...)" == "<name>" ]]. Reads the state file, google when missing.
# Built with json.dumps so the file text is escaped correctly and the
# parsed value compares equal to this plain string.
def checked_value(name):
    return ('[[ "$(cat $HOME/.local/state/hexciri/search-provider '
            '2>/dev/null || echo google)" == "%s" ]]' % name)

block_a = ['  "setup.config.search-provider": {"icon":"","label":"Search provider"},']
for name, label in providers:
    block_a.append(
        '  "setup.config.search-provider.%s": {"icon":"","label":"%s",'
        '"checked":%s,"action":"hexciri-search-provider %s"},'
        % (name, label, json.dumps(checked_value(name)), name))
block_a.append(
    '  "setup.config.themes-list": {"icon":"","label":"Themes list",'
    '"action":"hexciri-launch-editor \\"$HOME/.config/hexciri/themes.list\\""},')
block_b = ('  "update.themes-sync": {"icon":"","label":"Sync Themes List",'
           '"action":"hexciri-launch-floating-terminal-with-presentation '
           '\'hexciri theme sync\'"},')
block_c = ('  "update.icons-sync": {"icon":"","label":"Sync Theme Icons",'
           '"action":"hexciri-launch-floating-terminal-with-presentation '
           '\'hexciri icons sync\'"},')

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


changed = []

# Block A: replace-or-insert. If the header + themes-list rows are already
# there, the block between them must match the freshly generated one (run 2
# is a no-op; a provider-table change regenerates the rows in place).
# Otherwise insert the whole block after setup.config.xcompose.
h = key_index("setup.config.search-provider")
t = key_index("setup.config.themes-list")
if h is not None or t is not None:
    if h is None or t is None or t <= h:
        _die("search provider block is half-present (header=%s themes-list=%s), refusing to guess" % (h, t))
    if lines[h:t + 1] == block_a:
        print("menu: search provider + themes list rows already present, skipping")
    else:
        lines[h:t + 1] = block_a
        changed.append("search provider + themes list rows (regenerated from provider table)")
        print("patched: search provider + themes list rows in Setup > Config (regenerated from provider table)")
else:
    x = key_index("setup.config.xcompose")
    if x is None:
        _die('anchor "setup.config.xcompose" not found in menu jsonc')
    lines[x + 1:x + 1] = block_a
    changed.append("search provider + themes list rows")
    print("patched: search provider + themes list rows in Setup > Config")


def insert_after(anchor_key, new_line, label):
    if new_line in lines:
        print("menu: %s already present, skipping" % label)
        return False
    a = key_index(anchor_key)
    if a is None:
        _die('anchor "%s" not found in menu jsonc' % anchor_key)
    lines[a + 1:a + 1] = [new_line]
    changed.append(label)
    print("patched: %s" % label)
    return True


# Blocks B/C: one line each, after their sibling row. The key check
# ("update.themes":) cannot match the new "update.themes-sync": row, the
# closing quote + colon disambiguates.
insert_after("update.themes", block_b, "Sync Themes List row in Update")
insert_after("update.icons", block_c, "Sync Theme Icons row in Update")

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
        _die("menu jsonc missing new row %s" % key)
    return row


if set(_row("setup.config.search-provider").keys()) != {"icon", "label"}:
    _die("setup.config.search-provider header has unexpected keys")
for name, label in providers:
    row = _row("setup.config.search-provider." + name)
    if set(row.keys()) != {"icon", "label", "checked", "action"}:
        _die("search provider row %s has unexpected keys %s"
             % (name, sorted(row.keys())))
    if row["label"] != label:
        _die("search provider row %s label is %r, want %r"
             % (name, row["label"], label))
    if row["checked"] != checked_value(name):
        _die("search provider row %s checked expression is wrong" % name)
    if row["action"] != "hexciri-search-provider " + name:
        _die("search provider row %s action is wrong" % name)
themes_row = _row("setup.config.themes-list")
if themes_row.get("action") != 'hexciri-launch-editor "$HOME/.config/hexciri/themes.list"':
    _die("themes list row action is wrong: %r" % themes_row.get("action"))
sync_row = _row("update.themes-sync")
if "hexciri theme sync" not in sync_row.get("action", ""):
    _die("themes sync row does not call hexciri theme sync")
icons_row = _row("update.icons-sync")
if "hexciri icons sync" not in icons_row.get("action", ""):
    _die("icons sync row does not call hexciri icons sync")
# No duplicate keys: json.loads keeps the last, so count in the raw text.
for key in (["setup.config.search-provider", "setup.config.themes-list",
            "update.themes-sync", "update.icons-sync"]
           + ["setup.config.search-provider." + n for n, _l in providers]):
    if raw.count('"%s":' % key) != 1:
        _die('menu key "%s" occurs %d times in the file'
             % (key, raw.count('"%s":' % key)))
print("menu jsonc parses (%d entries, 9 root entries, %d search providers)"
      % (len(parsed), len(providers)))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'search provider patch: %d menu row blocks applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 51: search provider picker rows in Setup > Config, themes list row, theme/icon sync rows in Update"
