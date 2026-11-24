#!/usr/bin/env bash
# Hexciri fork patch 07: theme-set-gnome writes GTK settings.ini.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/07-theme-set-gnome.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "07-theme-set-gnome.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Fork-time patch: theme-set-gnome writes GTK settings.ini (2026-11-24) ---
# Upstream theme-set-gnome only sets gsettings and exits before doing
# anything when there is no DBus session, so it never wrote settings.ini
# and, from a tty3 install, never set dconf at all. It also set the theme
# name to Adwaita-dark, which is not a theme name (see the GTK step above).
# Every theme switch must rewrite both settings.ini files with theme name
# Adwaita + prefer-dark, and set dconf (through dbus-run-session when there
# is no live bus), or the file picker goes light again on the next switch.
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import os
import sys

root = sys.argv[1]
gn = root + "/bin/hexciri-theme-set-gnome"
with open(gn) as f:
    _g = f.read()
_g_lines = [
    '#!/bin/bash',
    '',
    '# omarchy:summary=Apply the current theme to GNOME color mode and icon settings',
    '# omarchy:hidden=true',
    '# Hexciri (2026-11-24): also writes ~/.config/gtk-3.0/gtk-4.0/settings.ini.',
    '# Upstream only set gsettings and exited before doing anything with no DBus',
    '# session, so the GTK file picker (xdg-desktop-portal, GTK4) stayed light:',
    '# on Wayland GTK reads the theme from dconf, not settings.ini, and the',
    '# installer runs from tty3 with no bus, so dconf was never set. And the theme',
    '# name it set, Adwaita-dark, is not a theme name: Adwaita dark form is a',
    '# variant selected by prefer-dark-theme / color-scheme, naming Adwaita-dark',
    '# falls back to light Adwaita while prefer-dark flips the foreground light,',
    '# white-on-white. Theme name is Adwaita in both files and in dconf; dark',
    '# comes from prefer-dark.',
    'THEME_DIR=$HOME/.local/state/hexciri/current/theme',
    'COLORS_FILE="$THEME_DIR/colors.toml"',
    'mode=$(hexciri-theme-color --file "$COLORS_FILE" mode)',
    'if [[ $mode == "light" ]]; then',
    '  _dark=false; _scheme=prefer-light',
    'else',
    '  _dark=true; _scheme=prefer-dark',
    'fi',
    'for _ver in 3.0 4.0; do',
    '  mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-$_ver"',
    '  cat > "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-$_ver/settings.ini" <<GTK_EOF',
    '[Settings]',
    'gtk-theme-name=Adwaita',
    'gtk-icon-theme-name=Adwaita',
    'gtk-application-prefer-dark-theme=$_dark',
    'gtk-font-name=Noto Sans 11',
    'GTK_EOF',
    'done',
    'unset _ver',
    '_set_gtk() {',
    '  if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then',
    '    gsettings set org.gnome.desktop.interface color-scheme "$_scheme"',
    '    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"',
    '    gsettings set org.gnome.desktop.interface icon-theme "Adwaita"',
    '  elif command -v dbus-run-session >/dev/null 2>&1; then',
    '    dbus-run-session -- gsettings set org.gnome.desktop.interface color-scheme "$_scheme"',
    '    dbus-run-session -- gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"',
    '    dbus-run-session -- gsettings set org.gnome.desktop.interface icon-theme "Adwaita"',
    '  fi',
    '}',
    '_set_gtk',
]
_g_new = chr(10).join(_g_lines) + chr(10)
if _g != _g_new:
    with open(gn, "w") as f:
        f.write(_g_new)
    print("  fork patch: theme-set-gnome writes gtk-3.0/gtk-4.0 settings.ini + dconf (Adwaita, prefer-dark)")
else:
    print("theme-set-gnome already patched, skipping")
PY
