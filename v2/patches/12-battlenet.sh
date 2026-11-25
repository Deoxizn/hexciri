#!/usr/bin/env bash
# Hexciri fork patch 12: install-gaming-battlenet also installs its icon.
# (2026-11-24, Devi: Battle.net installed and launched, but the
# installer failed at the last step on the missing desktop entry, and
# the manual desktop entry he added gave the launcher no icon.)
# The desktop entry says Icon=battle-net, which only resolves from the
# hicolor theme. This patch edits bin/hexciri-install-gaming-battlenet
# in the fork output so it installs the upstream icon to
# ~/.local/share/icons/hicolor/256x256/apps/battle-net.png (same pattern
# as tui/webapp-install) and refreshes the icon cache, right after it
# installs the desktop entry. The icon source itself is copied by the
# fork step in v2/install.sh (applications/icons/Battle.net.png, the
# only file taken from upstream applications/icons/).
# Standalone: bash v2/patches/12-battlenet.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "12-battlenet.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}

# --- install-gaming-battlenet installs the Battle.net icon ---
BATTLENET_BIN="$FORK_OUT/bin/hexciri-install-gaming-battlenet"
BATTLENET_ICON="$FORK_OUT/applications/icons/Battle.net.png"
if [ ! -f "$BATTLENET_BIN" ]; then
  warn "hexciri-install-gaming-battlenet not in fork, skipping Battle.net icon patch"
  exit 0
fi
if [ ! -f "$BATTLENET_ICON" ]; then
  warn "applications/icons/Battle.net.png not in fork, install-gaming-battlenet installs without its icon"
  exit 0
fi
python3 - "$BATTLENET_BIN" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()
marker = "# Battle.net icon (2026-11-24)"
if marker in s:
    print("already present, skipping")
    sys.exit(0)
anchor = 'update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true\n'
if anchor not in s:
    print("ERROR: 12-battlenet.sh: anchor not found in hexciri-install-gaming-battlenet, upstream script changed shape", file=sys.stderr)
    sys.exit(1)
block = anchor + '''
# Battle.net icon (2026-11-24): the desktop entry says Icon=battle-net,
# which only resolves from the hicolor theme. Same pattern as
# tui/webapp-install: install the upstream icon there and refresh the
# cache, so the launcher shows the Battle.net icon, not a generic one.
if [ -f "$HEXCIRI_PATH/applications/icons/Battle.net.png" ]; then
  mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
  install -m 644 "$HEXCIRI_PATH/applications/icons/Battle.net.png" \\
    "$HOME/.local/share/icons/hicolor/256x256/apps/battle-net.png"
  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi
'''
s = s.replace(anchor, block, 1)
with open(path, "w") as f:
    f.write(s)
print("patched hexciri-install-gaming-battlenet: installs Battle.net icon to hicolor")
PY
