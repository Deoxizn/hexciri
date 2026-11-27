#!/usr/bin/env bash
# Hexciri fork patch 50: imv/mpv defaults + calculator floats (Devi 2026-11-27).
# Hexciri-original (no upstream PR).
#
# Change 1 — video defaults, and the mime table actually reaching the box.
# bin/hexciri-mime-defaults had no video type at all: no VIDEO_MIMES, no
# video pick, no heal_video/apply video, so videos fell through to the
# browser because nothing owned the slot. The repo file carries the table
# now (VIDEO_MIMES + video_desktop + heal_video + apply video, mpv as the
# pick); this patch installs it into FORK_OUT/bin/ so the placed tree has
# it. That install step is the actual fix, not just the table: on v2 the
# heal was dead. hexciri-update's sync_mime calls $REPO/bin/hexciri-mime-
# defaults with REPO=/usr/share/hexciri (HEXCIRI_PATH is exported), but
# that file was never installed there — FORK_OUT/bin/ is built from
# upstream bin/* only, no patch ever installed the repo's bin/ script,
# and no install step copies repo bin/ into the live bin dir. The
# [ -x ... ] guard failed silently, so heal never ran and images stayed
# browser-owned even though heal_images already knows how to pin imv.
# Installs like patch 08 installs the custom Lua: copy the repo file in,
# guarded by a VIDEO_MIMES fingerprint (a repo file without it dies
# rather than shipping the old table). install.sh's patch_fingerprint
# list gains the file, so a later edit to it re-forks.
#
# Images need no table change: heal_images already pins the stored pick
# (imv, the default) once imv.desktop exists, and deploys the imv
# override that undoes NoDisplay so imv shows in Strata's Open With.
# Devi installed imv 2026-11-27, so the next update's heal pins images.
# Packages need no change either: imv, mpv and gnome-calculator are
# already in APP_PKGS in v2/install.sh (the default-apps step).
#
# Change 2 — calculator floats. Super+Shift+C (gnome-calculator) tiled;
# a calculator is a popup tool. Appends one rule to
# default/hypr/apps/hexciri.lua (installed by patch 08 from
# v2/hexciri-custom-apps.lua): class org.gnome.Calculator (short
# gnome-calculator accepted too), float + center. The rule is on the
# class, so the calculator floats from every trigger, not just the bind.
#
# Standalone: bash v2/patches/50-imv-mpv-calc-float.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.
#
# Syntax check note: the copied mime-defaults is bash -n checked, and
# the edited Lua is luac -p checked when luac is present (patch 08's
# conditional pattern); neither file is executed by this patch.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "50-imv-mpv-calc-float.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
CHANGED=0

# --- 1. Install bin/hexciri-mime-defaults into the fork ---
# The repo file is the source (it carries the video table); the fork copy
# is what lands in /usr/share/hexciri/bin/ and what the update's heal
# actually executes. Guarded by the VIDEO_MIMES fingerprint: a repo file
# without it is the pre-patch-50 table and must not ship.
MIME_SRC="$HEXCIRI_REPO_ROOT/bin/hexciri-mime-defaults"
MIME_DST="$FORK_OUT/bin/hexciri-mime-defaults"
if [ ! -f "$MIME_SRC" ]; then
  die "bin/hexciri-mime-defaults not in the installer tree ($MIME_SRC), video defaults cannot be installed"
fi
if ! grep -qF 'VIDEO_MIMES=(video/mp4' "$MIME_SRC"; then
  die "bin/hexciri-mime-defaults has no VIDEO_MIMES table, refusing to install the pre-patch-50 version"
fi
mkdir -p "$FORK_OUT/bin"
if [ -f "$MIME_DST" ] && cmp -s "$MIME_SRC" "$MIME_DST"; then
  printf 'bin/hexciri-mime-defaults: already present, skipping\n' >>"$_patch_log"
else
  cp -a "$MIME_SRC" "$MIME_DST"
  chmod 755 "$MIME_DST"
  CHANGED=$((CHANGED + 1))
  printf 'patched: installed bin/hexciri-mime-defaults\n' >>"$_patch_log"
fi
bash -n "$MIME_DST" || die "bash -n failed on installed hexciri-mime-defaults"

# --- 2. Calculator float rule (patch 08's Lua, appended) ---
# The python block prints one "patched: ..." line per applied edit (or an
# "already present, skipping" line); output goes through a temp file, not
# straight to $_patch_log, so a trailing info line cannot clobber it.
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 50 lua edit failed"; }
import sys
fork = sys.argv[1]
path = fork + "/default/hypr/apps/hexciri.lua"
MARKER = "org\\\\.gnome\\\\.Calculator|gnome-calculator"  # literal file text: Lua source escapes the dots (\\.)
ANCHOR = (
    "-- Image viewer: opaque, always: 1.0 override, Devi 2026-11-11.\n"
    "o.window({ class = \"^(imv)$\" }, { opacity = \"1.0 override 1.0 override\" })\n"
)
RULE = (
    "\n"
    "-- Calculator (Super+Shift+C, gnome-calculator): float, centered. A\n"
    "-- calculator is a popup tool, not a tile. Devi 2026-11-27. Class is the\n"
    "-- Wayland app-id org.gnome.Calculator (gnome-calculator accepted too).\n"
    "o.window({ class = \"^(org\\\\.gnome\\\\.Calculator|gnome-calculator)$\" }, { float = true, center = true })\n"
)
try:
    with open(path) as f:
        text = f.read()
except FileNotFoundError:
    print("ERROR: %s not found in fork output, patch 08 must be applied first" % path, file=sys.stderr)
    sys.exit(1)
if MARKER in text:
    print("default/hypr/apps/hexciri.lua: already present, skipping")
    sys.exit(0)
assert text.count(ANCHOR) == 1, "calculator anchor not unique in %s (count %d)" % (path, text.count(ANCHOR))
with open(path, "w") as f:
    f.write(text.replace(ANCHOR, ANCHOR + RULE, 1))
print("patched: calculator float rule in default/hypr/apps/hexciri.lua")
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# Syntax-check the edited Lua when luac is present (patch 08's conditional
# pattern); no luac on a box just warns, the install-time check covers it.
LUA_FILE="$FORK_OUT/default/hypr/apps/hexciri.lua"
if command -v luac5.1 >/dev/null 2>&1; then luac5.1 -p "$LUA_FILE" || die "Lua syntax check failed on default/hypr/apps/hexciri.lua";
elif command -v luac >/dev/null 2>&1; then luac -p "$LUA_FILE" || die "Lua syntax check failed on default/hypr/apps/hexciri.lua";
else warn "luac not found, skipping Lua syntax check on default/hypr/apps/hexciri.lua"; fi

printf 'imv/mpv defaults + calculator float patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 50: video defaults in the mime table (installed into the fork so the update heal runs), calculator floats"
