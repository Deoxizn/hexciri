#!/usr/bin/env bash
# Hexciri fork patch 70: LibreOffice Qt6 VCL backend (upstream PR #20391, Devi 2026-11-27).
# Upstream: https://github.com/omacom/omarchy/pull/20391
# Verified against the PR's actual .diff (2026-11-27): a 3-line insert in
# default/hypr/envs.lua, nothing else.
#
# SAL_USE_VCLPLUGIN=qt6 makes LibreOffice use its Qt6 backend instead of
# gtk3, so it follows qtengine theming and starts ~25-30% faster. The
# fork already ships libreoffice-fresh (v2/install.sh line 813, verified
# live on nyx HEAD f64bcb59) and already sets QT_QPA_PLATFORMTHEME=qtengine
# in this same file, so the backend has its theming to follow.
#
# Standalone: bash v2/patches/70-libreoffice-qt6.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "70-libreoffice-qt6.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "70-libreoffice-qt6.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. SAL_USE_VCLPLUGIN=qt6 in default/hypr/envs.lua ---
# Anchor: the XDG_SESSION_TYPE line, which must occur exactly once and be
# followed by a blank line and the screen-sharing comment (the upstream
# diff inserts between them). The fork's envs.lua matches upstream here
# (verified against the post-51 sim tree; no patch 52-54 touches it).
step "Setting LibreOffice to its Qt6 VCL backend"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 70 envs edit failed"; }
import sys

fork = sys.argv[1]
target = fork + "/default/hypr/envs.lua"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


ANCHOR = 'hl.env("XDG_SESSION_TYPE", "wayland")'
NEXT = "-- Allow better support for screen sharing (Google Meet, Discord, etc)."
BLOCK = [
    "",
    "-- Use LibreOffice's Qt6 VCL backend so it follows qtengine theming and starts ~25-30% faster than gtk3.",
    'hl.env("SAL_USE_VCLPLUGIN", "qt6")',
]
MARKER = 'hl.env("SAL_USE_VCLPLUGIN", "qt6")'

try:
    with open(target, encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    _die("%s not found in fork output" % target)

if MARKER in lines:
    if lines.count(MARKER) != 1:
        _die("SAL_USE_VCLPLUGIN line occurs %d times, want exactly 1" % lines.count(MARKER))
    print("envs: LibreOffice Qt6 backend already present, skipping")
else:
    hits = [i for i, l in enumerate(lines) if l == ANCHOR]
    if len(hits) != 1:
        _die('anchor "%s" occurs %d times, want exactly 1' % (ANCHOR, len(hits)))
    i = hits[0]
    # The line after the anchor must be blank and the one after that the
    # screen-sharing comment; anything else means the live file drifted.
    if i + 2 >= len(lines) or lines[i + 1] != "" or lines[i + 2] != NEXT:
        _die("lines after the XDG_SESSION_TYPE anchor are not blank + screen-sharing comment, live file drifted")
    lines[i + 1:i + 1] = BLOCK
    print("patched: LibreOffice Qt6 VCL backend in default/hypr/envs.lua")

with open(target, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

# --- validation: the env line exactly once, anchor still once.
with open(target, encoding="utf-8") as f:
    raw = f.read()
if raw.count(MARKER) != 1:
    _die("SAL_USE_VCLPLUGIN line occurs %d times after edit" % raw.count(MARKER))
if raw.count(ANCHOR) != 1:
    _die("XDG_SESSION_TYPE anchor occurs %d times after edit" % raw.count(ANCHOR))
print("envs validates (%d lines)" % len(raw.splitlines()))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

printf 'libreoffice qt6 patch: %d envs edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 70: LibreOffice uses the Qt6 VCL backend (upstream #20391)"
