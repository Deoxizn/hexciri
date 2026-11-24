#!/usr/bin/env bash
# Hexciri fork patch 01: Hexciri binds and substitute Omarchy-repo-only apps.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/01-binds.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "01-binds.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Patch Hexciri binds and substitute Omarchy-repo-only apps ---
# Two things, both on the fork output (user-owned temp dir), before placement:
# 1. Super+Shift+M = Spotify, Devi's own bind. Upstream has no such bind.
# 0. Super+Space = apps, Super+Alt+Space = menu, Devi 2026-11-23.
#    Upstream has them reversed (Super+Space = menu root,
#    Super+Alt+Space = dock apps); swap the two chords in
#    utilities.lua, keeping each bind's target with its line.
# 2. Omarchy-repo-only apps: omacalc -> gnome-calculator (Arch extra).
#    cliamp, omawrite and Obsidian binds are REMOVED, not substituted:
#    Devi 2026-11-23 does not want ncspot, ghostwriter or obsidian, so
#    there is no substitute to point those binds at. Herdr bind removed
#    (AI agent, out of v2 scope; tmux is on Super+Alt+Return), omasnap ->
#    grim + slurp in the capture script.
# This is a small dead-bind fix, not the Phase 2 Hexciri Lua merge: no
# windowrules, workspaces, or opacity edits live here.
# Idempotent: every replacement checks it is not already applied, so a
# rerun does not double-insert the Spotify bind.
step "Patching Hexciri binds: Super+Shift+M Spotify, Arch substitutes for Omarchy-only apps"
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
apps = root + "/default/hypr/bindings/applications.lua"
changed = []

with open(apps) as f:
    s = f.read()
orig = s

# 1. Spotify bind, after the Obsidian bind (same launch+focus shape).
spotify_bind = '  o.bind("SUPER + SHIFT + M", "Spotify", { launch = "spotify", focus = "^spotify$" })'
if "SUPER + SHIFT + M" not in s:
    anchor = '  o.bind("SUPER + SHIFT + O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })'
    if anchor in s:
        s = s.replace(anchor, anchor + "\n" + spotify_bind, 1)
        changed.append("Super+Shift+M Spotify bind added")
    else:
        print("WARN: Obsidian bind anchor not found in applications.lua, Spotify bind NOT added")
else:
    print("Spotify bind already present, skipping")

# 2. Calculator: omacalc (Omarchy-repo-only) -> gnome-calculator (Arch extra).
if '"omacalc"' in s:
    s = s.replace('"omacalc"', '"gnome-calculator"')
    changed.append("omacalc -> gnome-calculator (Super+Shift+Q, XF86Calculator)")

# 3. Music TUI: cliamp bind REMOVED, not repointed at ncspot: Devi
#    2026-11-23 does not want ncspot, Super+Shift+Alt+M is unbound now.
_old_music = '  o.bind("SUPER + SHIFT + ALT + M", "Music TUI", { tui = "cliamp", focus = true })'
if _old_music in s:
    s = s.replace(_old_music + "\n", "", 1)
    changed.append("cliamp Music TUI bind removed (ncspot not wanted)")
elif '{ tui = "cliamp", focus = true }' in s:
    print("WARN: cliamp bind line shape changed, Music TUI bind NOT removed")

# 4. Writing app: omawrite bind REMOVED, not repointed at ghostwriter:
#    Devi 2026-11-23 does not want ghostwriter, Super+Shift+W is unbound.
_old_write = '  o.bind("SUPER + SHIFT + W", "Omawrite", { launch = "omawrite" })'
if _old_write in s:
    s = s.replace(_old_write + "\n", "", 1)
    changed.append("omawrite bind removed (ghostwriter not wanted)")
elif '"omawrite"' in s:
    print("WARN: omawrite bind line shape changed, bind NOT removed")

# 4b. Obsidian: bind REMOVED, Devi 2026-11-23 does not want obsidian.
# Runs AFTER the Spotify insert above, which anchors on this very line.
_old_obsidian = '  o.bind("SUPER + SHIFT + O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })'
if _old_obsidian in s:
    s = s.replace(_old_obsidian + "\n", "", 1)
    changed.append("Obsidian bind removed (obsidian not wanted, Super+Shift+O unbound)")

# 5. Herdr: Omarchy AI-agent terminal, not installed in v2 (AI agents are
# out of scope). Remove the bind instead of leaving a terminal that errors
# with "herdr: command not found". Tmux is already on Super+Alt+Return.
old_herdr = '  o.bind("SUPER + CTRL + RETURN", "Herdr", { omarchy = "terminal-herdr" })'
old_herdr_hex = '  o.bind("SUPER + CTRL + RETURN", "Herdr", { hexciri = "terminal-herdr" })'
# Patch runs after the rename map, so the live line is the hexciri form;
# accept both, so the removal does not silently no-op like it did before.
if old_herdr in s:
    s = s.replace(old_herdr, '  -- Hexciri: Herdr bind removed, herdr is an Omarchy AI-agent app not installed in v2, use Super+Alt+Return for tmux.')
    changed.append("Herdr bind removed (AI agent, out of v2 scope)")
elif old_herdr_hex in s:
    s = s.replace(old_herdr_hex, '  -- Hexciri: Herdr bind removed, herdr is an Omarchy AI-agent app not installed in v2, use Super+Alt+Return for tmux.')
    changed.append("Herdr bind removed (AI agent, out of v2 scope)")

# 5b. Activity TUI: btop (removed, v1 stock removal, never installed) ->
# btm (Arch extra package `bottom`, the Hexciri monitor). The package is
# `bottom` but its binary is `btm`: the old bind opened a terminal that
# errored with "btop: command not found", and the 2026-11-23 fix that
# changed it to tui = "bottom" errored with "no file or dir" because no
# such binary exists.
utils = root + "/default/hypr/bindings/utilities.lua"
with open(utils) as f:
    u = f.read()
u_orig = u
if '{ tui = "btop" }' in u:
    u = u.replace('{ tui = "btop" }', '{ tui = "btm" }')
    changed.append("btop -> btm (Super+Shift+T Activity TUI)")
elif '{ tui = "bottom" }' in u:
    u = u.replace('{ tui = "bottom" }', '{ tui = "btm" }')
    changed.append("bottom -> btm (Super+Shift+T Activity TUI, package bottom ships binary btm)")
# 5c. Super+Space / Super+Alt+Space swap, Devi 2026-11-23: Super+Space is
# apps, Super+Alt+Space is the menu. Upstream Omarchy has them reversed
# (Super+Space = menu root, Super+Alt+Space = dock apps), and the earlier
# Hexciri reports repeated that reversed mapping. Swap only the chords,
# keeping each bind's description/target with its own line. After the
# rename map the lines read "Hexciri menu" / "hexciri.dock.apps"; accept
# the unrenamed "Omarchy menu" / "omarchy.dock.apps" too. Both routes
# ("menu root" and "ipc hexciri.dock.apps") are already in the shortcuts
# file, so both binds still dispatch via Hyprland global shortcuts.
# Idempotent: if Super+Space already opens apps, skip.
_menu_desc = "Hexciri menu" if '"Hexciri menu"' in u else "Omarchy menu"
_apps_ipc = "hexciri.dock.apps" if "hexciri.dock.apps" in u else "omarchy.dock.apps"
_menu_line = 'o.bind("SUPER + SPACE", "%s", { menu = "root" })' % _menu_desc
_apps_line = 'o.bind("SUPER + ALT + SPACE", "Apps", { ipc = "%s" })' % _apps_ipc
if _menu_line in u and _apps_line in u:
    _ph = "o.bind(\"__HEXCIRI_SWAP_MENU__\", \"%s\", { menu = \"root\" })" % _menu_desc
    u = u.replace(_menu_line, _ph, 1)
    u = u.replace(_apps_line, 'o.bind("SUPER + SPACE", "Apps", { ipc = "%s" })' % _apps_ipc, 1)
    u = u.replace(_ph, 'o.bind("SUPER + ALT + SPACE", "%s", { menu = "root" })' % _menu_desc, 1)
    changed.append("Super+Space -> apps (dock apps), Super+Alt+Space -> menu (root)")
elif 'o.bind("SUPER + SPACE", "Apps"' in u and 'o.bind("SUPER + ALT + SPACE", "%s"' % _menu_desc in u:
    print("Super+Space / Super+Alt+Space already swapped, skipping")
else:
    print("WARN: Super+Space / Super+Alt+Space bind lines not found in utilities.lua, swap NOT applied")
if u != u_orig:
    with open(utils, "w") as f:
        f.write(u)

if s != orig:
    with open(apps, "w") as f:
        f.write(s)
for c in changed:
    print("applications.lua: " + c)
if not changed:
    print("applications.lua: no bind changes needed")

# 6. Reclaim Super+Shift+S / Super+Shift+C from Omarchy's region webapps.
# (The applications.lua print loop above already ran, so reclaim changes
# are printed here, not there.)
_changed_before_reclaim = len(changed)
# Upstream regions/global.lua (loaded when preinstalled bindings are
# enabled) binds S to Google Maps and C to Hey Calendar. Devi
# 2026-11-24: in v1 S was web search and C was calculator. Remove those
# two lines (commented, not silently deleted) and let
# default/hypr/bindings/hexciri.lua own the chords instead, where S runs
# hexciri-web-search (QS prompt, Brave Origin) and C runs
# gnome-calculator (same app as Super+Shift+Q). Idempotent: already
# commented lines are skipped, a changed line shape warns instead of
# silently no-opping.
_glob = root + "/default/hypr/bindings/regions/global.lua"
with open(_glob) as f:
    _g = f.read()
_g_orig = _g
_old_maps = 'o.bind("SUPER + SHIFT + S", "Google Maps", { webapp = "https://maps.google.com/", focus = true })'
_old_cal = 'o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://app.hey.com/calendar/weeks/" })'
if _old_maps in _g:
    _g = _g.replace(_old_maps, '-- Hexciri: Super+Shift+S is web search in v1 (hexciri-web-search), not Google Maps.', 1)
    changed.append("Google Maps bind removed from regions/global.lua (Super+Shift+S is web search)")
elif "SUPER + SHIFT + S" in _g and "Google Maps" in _g:
    print("WARN: Google Maps bind line shape changed, Super+Shift+S NOT reclaimed")
if _old_cal in _g:
    _g = _g.replace(_old_cal, '-- Hexciri: Super+Shift+C is calculator in v1 (gnome-calculator), not Hey Calendar.', 1)
    changed.append("Hey Calendar bind removed from regions/global.lua (Super+Shift+C is calculator)")
elif "SUPER + SHIFT + C" in _g and "Calendar" in _g:
    print("WARN: Hey Calendar bind line shape changed, Super+Shift+C NOT reclaimed")
if _g != _g_orig:
    with open(_glob, "w") as f:
        f.write(_g)
# Same chord in the China region file (only one region module loads, so
# global and cn never double-bind, but a cn install would otherwise keep
# Amap on Super+Shift+S instead of web search).
_cn = root + "/default/hypr/bindings/regions/cn.lua"
with open(_cn) as f:
    _c = f.read()
_c_orig = _c
_old_amap = 'o.bind("SUPER + SHIFT + S", "Amap", { webapp = "https://www.amap.com/", focus = true })'
if _old_amap in _c:
    _c = _c.replace(_old_amap, '-- Hexciri: Super+Shift+S is web search in v1 (hexciri-web-search), not Amap.', 1)
    changed.append("Amap bind removed from regions/cn.lua (Super+Shift+S is web search)")
elif "SUPER + SHIFT + S" in _c and "Amap" in _c:
    print("WARN: Amap bind line shape changed, Super+Shift+S NOT reclaimed in cn.lua")
if _c != _c_orig:
    with open(_cn, "w") as f:
        f.write(_c)
# 6b. Reclaim SUPER+CTRL+S for Hexciri Settings (2026-11-24, Devi:
# Super+Ctrl+S does not open Settings, Super+Alt+S does not either).
# The 690c325 agent claimed the chord was free; it was not. Upstream
# utilities.lua:106 binds SUPER+CTRL+S to Share ({ menu = "share" }),
# and SUPER+ALT+S is scratchpad (tiling.lua). Move Share to
# SUPER+CTRL+SHIFT+S, verified free in upstream 94a8c3c (no
# SUPER+SHIFT+CTRL+S bind exists), and let
# default/hypr/bindings/hexciri.lua own SUPER+CTRL+S for hexciri-settings.
_utils = root + "/default/hypr/bindings/utilities.lua"
with open(_utils) as f:
    _u2 = f.read()
_u2_orig = _u2
_old_share = 'o.bind("SUPER + CTRL + S", "Share", { menu = "share" })'
if _old_share in _u2:
    _u2 = _u2.replace(_old_share, 'o.bind("SUPER + CTRL + SHIFT + S", "Share", { menu = "share" })  -- Hexciri: Super+Ctrl+S is Hexciri Settings, Share moved here', 1)
    changed.append("Share bind moved Super+Ctrl+S -> Super+Ctrl+Shift+S (Super+Ctrl+S is Hexciri Settings)")
elif 'o.bind("SUPER + CTRL + SHIFT + S", "Share"' in _u2:
    print("Share bind already on Super+Ctrl+Shift+S, skipping")
else:
    print("WARN: Share bind line shape changed, Super+Ctrl+S NOT reclaimed")
if _u2 != _u2_orig:
    with open(_utils, "w") as f:
        f.write(_u2)
for c in changed[_changed_before_reclaim:]:
    print("regions: " + c)

# 5d. Touchpad: bottom lower right = right click, Devi 2026-11-23.
# Upstream default/hypr/input.lua sets clickfinger_behavior = true, which
# maps 1/2/3 fingers to LMB/RMB/MMB and disables location-based clicks, so
# a 1-finger press in the bottom-right corner is a LEFT click, not right.
# Devi clicks bottom lower right like a normal mouse and expects right
# click (e.g. right-clicking the clock to cycle its format, which does
# work once the click actually registers as right). Set it false so
# libinput area mapping applies: bottom-left left, bottom-middle middle,
# bottom-right right. 2-finger tap still right-clicks via tap_to_click.
# Only this one key changes; natural_scroll, scroll_factor and everything
# else in input.lua are untouched. config/hypr/input.lua is a commented
# user template and is left alone. Idempotent.
_input = root + "/default/hypr/input.lua"
with open(_input) as f:
    _inp = f.read()
_inp_orig = _inp
if "clickfinger_behavior = true" in _inp:
    _inp = _inp.replace("clickfinger_behavior = true", "clickfinger_behavior = false", 1)
    changed.append("clickfinger_behavior true -> false (bottom-right touchpad = right click)")
elif "clickfinger_behavior = false" in _inp:
    print("clickfinger_behavior already false, skipping")
else:
    print("WARN: clickfinger_behavior not found in default/hypr/input.lua, touchpad patch NOT applied")
if _inp != _inp_orig:
    with open(_input, "w") as f:
        f.write(_inp)

# 7. Screenshot: hexciri-capture-screenshot execs omasnap (Omarchy-repo-only).
# Rewrite it to grim + slurp (both in CORE_PKGS), wl-copy, and
# hexciri-notification-send. Same CLI the binds and menu use:
#   [smart|region|windows|fullscreen|scroll] [copy|save]
# No args (menu Capture > Screenshot, PRINT) behaves like smart: a slurp
# region pick, saved to ~/Pictures/Screenshots. copy puts the PNG on the
# clipboard only. scroll is not supported by grim, it falls back to
# fullscreen. capture-text and capture-qr already used grim/slurp directly.
cap = root + "/bin/hexciri-capture-screenshot"
with open(cap) as f:
    cap_old = f.read()
if "omasnap" in cap_old:
    new_cap = '''#!/bin/bash

# omarchy:summary=Take a screenshot
# omarchy:group=capture
# omarchy:args=[smart|region|windows|fullscreen|scroll] [copy|save]
# omarchy:examples=omarchy screenshot | omarchy capture screenshot region
# omarchy:aliases=omarchy screenshot
#
# NOTE: the omarchy: metadata headers above are kept as-is, like every
# other copied bin script in the fork: the rename map deliberately does
# not touch the "omarchy:" prefix, and the menu/help metadata parser
# reads these lines in that shape.
#
# Hexciri substitute for Omarchy's omasnap (Omarchy-repo-only, no Arch or
# AUR package): grim + slurp, both in CORE_PKGS. Same CLI the binds
# (PRINT, SUPER+CTRL+ALT+C) and the menu (Capture > Screenshot) already
# call, so neither needs to change. capture-text and capture-qr already
# used grim/slurp directly, this brings screenshot in line with them.

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
SHOT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$SHOT_DIR" 2>/dev/null || SHOT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SHOT_DIR" 2>/dev/null || SHOT_DIR="$HOME"
SHOT_FILE="$SHOT_DIR/Screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"

MODE="smart"
DO_COPY=0
DO_SAVE=1
for arg in "$@"; do
  case "$arg" in
    smart|region|windows|fullscreen|scroll) MODE="$arg" ;;
    copy) DO_COPY=1; DO_SAVE=0 ;;
    save) DO_SAVE=1; DO_COPY=0 ;;
    slurp) ;; # passthrough arg from the old omasnap CLI, ignored
    *) ;; # unknown arg, ignored
  esac
done

# Geometry: fullscreen needs no picker, scroll is not supported by grim
# and falls back to fullscreen, everything else picks with slurp
# (windows snaps via hexciri-capture-region when it exists).
GEOM=""
case "$MODE" in
  fullscreen|scroll)
    [ "$MODE" = "scroll" ] && hexciri-notification-send -u low "Screenshot" "Scroll capture is not supported, took a fullscreen shot instead" 2>/dev/null || true
    ;;
  windows)
    if command -v hexciri-capture-region >/dev/null 2>&1; then
      GEOM="$(hexciri-capture-region windows 2>/dev/null || true)"
    fi
    [ -n "$GEOM" ] || GEOM="$(slurp 2>/dev/null || true)"
    ;;
  *)
    GEOM="$(slurp 2>/dev/null || true)"
    ;;
esac
[ -n "$GEOM" ] || [ "$MODE" = "fullscreen" ] || [ "$MODE" = "scroll" ] || exit 0

if [ "$DO_COPY" -eq 1 ]; then
  if [ -n "$GEOM" ]; then
    grim -g "$GEOM" - | wl-copy || exit 1
  else
    grim - | wl-copy || exit 1
  fi
  hexciri-notification-send "Screenshot" "Screenshot copied to clipboard" 2>/dev/null || true
else
  if [ -n "$GEOM" ]; then
    grim -g "$GEOM" "$SHOT_FILE" || exit 1
  else
    grim "$SHOT_FILE" || exit 1
  fi
  hexciri-notification-send "Screenshot" "Screenshot saved to $SHOT_FILE" 2>/dev/null || true
fi
'''
    with open(cap, "w") as f:
        f.write(new_cap)
    print("bin/hexciri-capture-screenshot: rewritten to grim + slurp (omasnap substitute)")
else:
    print("bin/hexciri-capture-screenshot: already rewritten, skipping")
PY
