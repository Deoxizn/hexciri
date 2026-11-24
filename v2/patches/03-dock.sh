#!/usr/bin/env bash
# Hexciri fork patch 03: dock pinned list: Strata, Spotify, Brave Origin, Zed, Kitty.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/03-dock.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.
# NOTE: in install.sh this patch's header comment sat at the dock
# position (old line 3246) but its code physically sat after the
# background-Strata patch (old lines 3360-3378). This file reunites
# them. It now runs before WidgetButton / background-Strata instead
# of after them; the three touch disjoint files (config/shell.json
# vs WidgetButton.qml vs theme-bg-install), and sim7 proves the
# fork-out tree is byte-identical either way.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "03-dock.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Patch dock pinned list (Devi 2026-11-23 20:59 / 21:00 MST) ---
# Upstream config/omarchy/shell.json pins folio, omarchy-browser,
# omarchy-terminal, omacalc, omawrite, hype, monologue, cliamp. After the
# rename only the two wrappers resolve (hexciri-browser, hexciri-terminal);
# the other six are dead Omarchy app names and the dock filters them out,
# so the dock showed two pins and six empty slots. Devi picked the pins:
# Strata, Spotify, Brave Origin, Zed, and Kitty.
# Desktop-entry ids, verified, not guessed:
#   Strata: io.github.lgse.Strata.desktop (Strata step installs it to
#     ~/.local/share/applications/io.github.lgse.Strata.desktop)
#   Spotify: spotify.desktop (AUR spotify, /usr/bin/spotify + spotify.desktop)
#   Brave Origin: brave-origin.desktop (AUR brave-origin-bin)
#   Zed: dev.zed.Zed.desktop (Arch extra zed, Exec=zeditor)
#   Kitty: kitty.desktop (Arch extra kitty, also the xdg-terminals.list pick)
# hexciri-browser and hexciri-terminal are deliberately NOT pinned: the
# browser wrapper launches the default browser (Brave Origin) and the
# terminal wrapper launches the default terminal (Kitty), so pinning them
# as well would show two Browser icons and two Terminal icons. DockModel
# stand-ins only claim a window when its own app is not pinned, and both
# Brave Origin and Kitty are pinned directly here, so their windows claim
# themselves. Idempotent: the patch rewrites dock.pinned to exactly this
# list, whatever the forked file held before.
step "Patching dock pinned list: Strata, Spotify, Brave Origin, Zed, Kitty"
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import json
import sys

root = sys.argv[1]
pins = ['io.github.lgse.Strata', 'spotify', 'brave-origin', 'dev.zed.Zed', 'kitty']
path = root + '/config/shell.json'
with open(path) as f:
    cfg = json.load(f)
if cfg.get('dock', {}).get('pinned') == pins:
    print('dock pinned list already set, skipping')
else:
    cfg.setdefault('dock', {})['pinned'] = pins
    with open(path, 'w') as f:
        json.dump(cfg, f, indent=2)
        f.write('\n')
    print('dock pinned list set: ' + ', '.join(pins))
PY
