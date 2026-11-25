#!/usr/bin/env bash
# Hexiri 2.0 single installer
# Name: Hexiri
# Base: EndeavourOS, Calamares online install, No Desktop selected
# Shell: forked Omarchy Quickshell shell, renamed hexciri, exact same menu, bar, themes
# Goal: a very minimal almost nothing installed Arch that still has the feel and look of Omarchy.
#
# This is the one command, minus the EndeavourOS install itself.
# It merges the old two Phase 1 scripts into one, in order:
#   1. Preflight, packages, GPU drivers, Quickshell, Hyprland, SDDM plus uwsm,
#      Hexciri default apps (Omarchy defaults + Hexciri replacements, so
#      binds can be tested: Brave Origin, zathura, imv, zed, Obsidian, mpv)
#   2. Download omacom/omarchy at the pinned commit as a tarball (no git, no auth),
#      verify SHA from the tarball top dir, then fork and rename the shell
#      (fork patches live in v2/patches/, one file per patch, applied
#      in order by v2/patches/apply.sh).
#      On a re-run the fork is CACHED (2026-11-24, Devi: every update re-forked
#      Omarchy from scratch): if the fork fingerprint (fork code + pinned
#      commit + repo files copied into the fork) is unchanged, the download
#      and the whole fork are skipped and the cached tree is reused.
#      --refork forces a full re-fork. Per-file fork noise goes to
#      /tmp/hexciri-install-fork.log, screen gets one summary per stage.
#   4. Place the forked tree to /usr/share/hexciri, ~/.config/hexciri,
#      ~/.local/state/hexciri, and ~/.config/hypr, and wire the compat alias in
#   5. Apply a default theme, theme SDDM with that theme, health check,
#      then reboot test checklist
#   Lua module rename: config/hypr/hyprland.lua requires
#   default.hypr.hexciri (not default.hypr.omarchy), and bootstrap.lua
#   preloads the old name as an alias, or Hyprland trips emergency mode.
#
# The old two scripts are kept as reference, do not delete them yet:
#   v2/install-2.0.sh  (packages and session, now step 1 and 5 below)
#   v2/fork-shell.sh   (fork and rename, now steps 2 and 3 below)
# This file, v2/install.sh, is the primary entry point.
#
# DO NOT INSTALL (do not add these back):
#   mkinitcpio (conflicts with dracut, EndeavourOS uses dracut)
#   Limine, snapper, linux-omarchy, Plymouth, LUKS scripts, pacman guard hook
#   Upstream Omarchy migrations, channel/keyring/mirror scripts
#   Waybar, Mako, Walker, hyprlock, hypridle, swaybg, hyprpolkitagent
#   Apps beyond the Hexciri default apps step below, Docker, AI agents
#   other than opencode (in the default apps step, v1 pacman install)
#   Noctalia, Niri. Hyprland plus Quickshell only, SDDM like Omarchy.
#
# Hard rule: no file named omarchy in the Hexiri repo. Files, paths, and CLI
# are renamed to hexciri. Theme format (colors.toml + shell.toml) and plugin
# format (manifest.json + BarWidget.qml + scripts/ + shell.json layout) stay
# Omarchy compatible, through a runtime alias in code, not a file named omarchy.
# A plugin asking for omarchy.bar gets hexciri.bar, omarchy-shell IPC gets
# hexciri-shell, OMARCHY_PATH is a runtime alias set to HEXCIRI_PATH.
#
# TODO Phase 2 only, not in this script:
#   Port Hexciri scripts from Noctalia calls to QS calls
#   arch-updates EndeavourOS backend, Nyxiri overlay
#   (Hexciri Lua custom-only, THPM + theme hook done 2026-11-24:
#   v2/hexciri-custom-binds.lua + hexciri-custom-apps.lua in the fork,
#   v2/hexciri-theme-hook-*.sh + theme-env.sh in theme-set.d, THPM
#   from GitHub source. Theme support itself needs no separate
#   fork/re-add: the forked Omarchy shell/code already provides it.
#   hyprctl reload fix + quiet re-run done 2026-11-24 (third breakage):
#   the 926c9d7 update placed a good hexciri.lua, but the running Hyprland
#   kept its stale/emergency config until a manual `hyprctl reload` fixed
#   it, because hexciri-update-restart only restarts Quickshell and
#   theme-set reloads Hyprland only on a real theme change. Installer now
#   reloads Hyprland after placement/health, and placement runs a real
#   TRUE root cause (2026-11-24, Devi's refork theory was right):
#   Hyprland 0.57 Lua tracks every file the config require()s and its
#   inotify watcher reloads on any change, so the installer's rm -rf +
#   cp -a of /usr/share/hexciri near-certainly reloads mid-copy into
#   emergency mode. Upstream fixed this with omarchy-hyprland-reload-
#   guard driven by ALPM hooks on omarchy-settings; Hexciri has no
#   packages and never forked those hooks, so the guard shipped but
#   nothing called it. The installer now pauses the guard (via sudo,
#   like upstream's root-run hooks, /run/hexciri is root-owned) before
#   placement and resumes it at the end; resume reloads once itself.
#   boot-path test (dofile bootstrap.lua, search default.hypr.hexciri in
#   package.path) plus hyprlua_ok() content checks everywhere
#   bootstrap_ok() is used. Re-run spam cut again: Kept/already-present
#   lines to the detail log, fork-patch python blocks to the fork log.
#   System packages count fixed: pacman printed "upgrading flex..." with
#   no (n/n) prefix, old ^(n/n) pattern counted 0 and claimed up to date
#   after a real upgrade (flex 2.7.1 -> 2.7.6); loose pattern + _pending
#   fallback when the log has no "there is nothing to do".
#   updater reload done 2026-11-24 (fourth breakage, Devi 11:07 MST):
#   after the e80264a2 update bootstrap.lua emergency came back and a
#   manual hyprctl reload fixed it again. The alias patch is atomic
#   (os.replace, in live e80264a2), so this is not a half-written file:
#   the emergency state is sticky and NO update step ever reloaded
#   Hyprland, so it persisted across updates until a manual reload.
#   hexciri-update-restart now reloads Hyprland config after the shell
#   restart, on EVERY update, even when the installer does not re-run.
#   bootstrap.lua integrity done 2026-11-24 (second breakage): content
#   checks everywhere instead of -f, atomic alias write, verified fork
#   cache saves, self-heal in the drift check; update noise cut ~90%
#   (command scan + omarchy scan to the fork log, one summary line
#   each; run_pacman shows error lines only; eject dropped, it is not
#   in the Arch repos); health WARNs fixed (sudoers via sudo test,
#   fprintd via pacman -Q, boot timeout trusts the EFI variable).
#   theme-link done 2026-11-24: ministry-of-taste/theme-link restores
#   theme Lua via trusted symlinks, v2/hexciri-theme-link wrapper.)
#   (hexciri-update rework done 2026-11-24: eos-update --aur + Hexciri
#   self-update + mise, see the fork-time update patch below)
#   Nyxiri overlay, THPM install
#
# Run as your normal user, not as root, on a fresh EndeavourOS no-DE install:
#   bash v2/install.sh
# Ghostty is an alternative terminal to foot. It is not installed here.
# Install it manually later if wanted: yay -S ghostty

set -euo pipefail
# Never exit silently again: if any command fails, print where it failed.
# (2026-11-23: the bootstrap died silently after "Validation passed"
# with exit 141, from a tar | head pipe under pipefail. Same fix below.)
trap 'printf "ERROR: [hexciri] failed at line %s, exit %s, command: %s\n" "$LINENO" "$?" "$BASH_COMMAND" >&2' ERR

# Args, like v1: --yes answers prompts with yes, --reboot reboots at the
# end without asking, otherwise the reboot offer still asks (never
# auto-reboots). Forwarded by v2/bootstrap.sh.
UPDATE_YES=""
AUTO_REBOOT=0
NO_REBOOT=0
REFORK=0
LIGHT_SYNC=0
PRINT_FP=0
REAPPLY=0
REAPPLY_PROV=0
WITH_CATS=0
WITH_NYXIRI=0
for _a in "$@"; do
  case "$_a" in
    --yes|-y) UPDATE_YES="--yes" ;;
    --reboot) AUTO_REBOOT=1 ;;
    --no-reboot) NO_REBOOT=1 ;;
    --refork|--force) REFORK=1 ;;
    --re-apply) REAPPLY=1 ;;
    --re-apply-provision) REAPPLY_PROV=1 ;;
    --light-sync) LIGHT_SYNC=1 ;;
    --print-fingerprints) PRINT_FP=1 ;;
    --with-cats) WITH_CATS=1 ;;
    --with-nyxiri) WITH_NYXIRI=1 ;;
    -h|--help) echo "usage: install.sh [--yes] [--reboot] [--no-reboot] [--refork] [--light-sync] [--print-fingerprints] [--re-apply] [--re-apply-provision] [--with-cats] [--with-nyxiri]"; exit 0 ;;
    *) printf 'install.sh: unknown arg: %s (usage: install.sh [--yes] [--reboot] [--no-reboot] [--with-cats] [--with-nyxiri])\n' "$_a" >&2; exit 1 ;;
  esac
done
unset _a

# No git credential prompts anywhere in this script. The Omarchy source is
# fetched as a public codeload tarball with curl, never with git clone.
# Git is installed as a package for later use only, it is never invoked here
# in a way that can ask for a username or password.
export GIT_TERMINAL_PROMPT=0

PINNED_SHA="94a8c3c3321129fae87a329947711355897e69fd"
PINNED_BRANCH="quattro"
PINNED_DATE="2026-11-23"
OMARCHY_TARBALL_URL="https://codeload.github.com/omacom/omarchy/tar.gz/${PINNED_SHA}"

HEXCIRI_PATH="/usr/share/hexciri"
TMP_WORK=""
FORK_OUT=""

# Repo root of the Hexciri checkout the bootstrap extracted: install.sh runs
# from <root>/v2/, so its parent dir is the root. branding/sddm/ and
# bin/hexciri-strata-install live here. If install.sh was downloaded alone,
# this is just its parent dir and those optional sources are skipped with a
# warning instead of dying.
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="$(dirname "$INSTALLER_DIR")"

step() { printf '\n==> %s\n' "$1"; }

# Fork detail log: per-file fork noise (Copied bin, Renamed paths, the
# full fork-out listing) goes here, not to the screen. Screen gets one
# summary line per fork stage; full detail is in the log, or on screen
# with HEXCIRI_INSTALL_VERBOSE=1 / HEXCIRI_UPDATE_VERBOSE=1.
FORK_LOG="${HEXCIRI_INSTALL_FORK_LOG:-/tmp/hexciri-install-fork.log}"
FORK_CACHE_DIR="$HOME/.cache/hexciri/fork-cache"
SKIP_FORK=0
FORK_FP=""

# Fork fingerprints, split 2026-11-24 (Devi: v1 left the system alone,
# v2 re-forked on every installer tweak). The old single fingerprint
# hashed fork marker -> placement marker, so ANY installer change that
# touched a fork patch (update output, keyring, thpm filter) forced a
# full 94 MB re-fork. Split it:
#   upstream_fingerprint(): fork+rename+rewrite core only (fork marker
#     -> patches marker) + pinned commit. Changes only when the
#     upstream fork itself changes.
#   patch_fingerprint(): v2/patches/* content (sorted) + repo files
#     copied into the fork (hexciri-update-hexciri, hexciri-theme-ansi)
#     + the Hexciri Settings plugin step below. Changes when a patched
#     bin/script or the Settings step changes. A patch change moves
#     ONLY this fingerprint now, never upstream/system, so the updater
#     re-applies the fork instead of re-running the whole installer.
#     (2026-11-24 patches refactor: the fork patches moved out of this
#     file into v2/patches/, one file per patch, applied in order by
#     v2/patches/apply.sh. The Settings range is the one remaining
#     install.sh range here, kept deliberately: that step installs into
#     the placed tree and is covered by --re-apply like the patches.)
#   installer_tree_sha(): install.sh + v2/patches/* (content, sorted).
#     What hexciri-update-hexciri compares against
#     /usr/share/hexciri/.installer-sha. It used to be install.sh alone,
#     so a patch-only change would have looked unchanged and the update
#     would have skipped it.
#   fork_fingerprint(): combined, kept for legacy checks.
#   provision_fingerprint() (2026-11-24, minimal re-apply): the
#     system-config steps after placement (browser sudoers, lock PAM,
#     SDDM fingerprint/keyring, locale, boot timeout, theme, GTK,
#     EOS icon, speedtest, SDDM theme, Strata, Spotify wrapper,
#     trim). Changes when one of those steps changes.
#   system_fingerprint() (2026-11-24, minimal re-apply): system
#     provisioning before the fork (preflight, packages, apps, GPU,
#     SDDM, services) + mise/THPM. Changes when a package list or
#     provisioning step changes; that used to change NEITHER fork
#     fingerprint, so it light-synced and never applied at all.
#     Now it forces a full installer re-run instead.
# A change to output wording / health only changes NONE of the four:
# the self-update light-syncs instead of re-running the installer.
upstream_fingerprint() {
  {
    sed -n '/^# --- Fork and rename, inline/,/^# --- Apply fork patches (v2\/patches\/) ---/p' "$INSTALLER_DIR/install.sh"
    printf 'pinned=%s\n' "$PINNED_SHA"
  } | sha256sum | cut -d' ' -f1
}
installer_tree_sha() {
  {
    sha256sum "$INSTALLER_DIR/install.sh" 2>/dev/null || printf 'missing %s\n' "$INSTALLER_DIR/install.sh"
    if [ -d "$INSTALLER_DIR/patches" ]; then
      for _ts in "$INSTALLER_DIR"/patches/*; do
        [ -f "$_ts" ] && sha256sum "$_ts"
      done
    else
      printf 'missing patches dir %s\n' "$INSTALLER_DIR/patches"
    fi
  } | sha256sum | cut -d' ' -f1
}
patch_fingerprint() {
  {
    if [ -d "$INSTALLER_DIR/patches" ]; then
      for _pf in "$INSTALLER_DIR"/patches/*; do
        [ -f "$_pf" ] && sha256sum "$_pf"
      done
    else
      printf 'missing patches dir %s\n' "$INSTALLER_DIR/patches"
    fi
    sed -n '/^# --- Hexciri Settings, Hexciri shell plugin/,/^step "Installing Hexciri theme hooks/p' "$INSTALLER_DIR/install.sh"
    for _ff in "$HEXCIRI_REPO_ROOT/v2/hexciri-update-hexciri" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-ansi" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-env.sh" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-hook-gtk.sh" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-hook-adapta.sh" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-hook-thpm.sh" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-hook.toml" "$HEXCIRI_REPO_ROOT/v2/hexciri-custom-binds.lua" "$HEXCIRI_REPO_ROOT/v2/hexciri-custom-apps.lua" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-link" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-sync" "$HEXCIRI_REPO_ROOT/v2/hexciri-web-search" "$HEXCIRI_REPO_ROOT/v2/hexciri-settings-tabs" "$HEXCIRI_REPO_ROOT/v2/hexciri-launch-settings" "$HEXCIRI_REPO_ROOT/v2/hexciri-font-maple-cn-present"; do
      if [ -f "$_ff" ]; then sha256sum "$_ff"; else printf 'missing %s\n' "$_ff"; fi
    done
  } | sha256sum | cut -d' ' -f1
}
fork_fingerprint() {
  printf '%s %s\n' "$(upstream_fingerprint)" "$(patch_fingerprint)" | sha256sum | cut -d' ' -f1
}
provision_fingerprint() {
  {
    sed -n '/^# --- Browser policy for theme-set-browser + lock PAM ---/,/^# --- Hexciri theme hooks (2026-11-24, Devi: modified better Omarchy theme hook) ---/p' "$INSTALLER_DIR/install.sh"
    sed -n '/^# --- Spotify fallback wrapper (post-placement) ---/,/^# --- Health check, like v1 ---/p' "$INSTALLER_DIR/install.sh"
  } | sha256sum | cut -d' ' -f1
}
system_fingerprint() {
  {
    sed -n '/^# --- Preflight ---/,/^# --- Fork cache check/p' "$INSTALLER_DIR/install.sh"
    sed -n '/^# --- mise + Hexciri tools config/,/^# --- Place the forked tree to its install targets ---/p' "$INSTALLER_DIR/install.sh" | grep -vF 'binds_chain_ok "$FORK_OUT"'
  } | sha256sum | cut -d' ' -f1
}
# --print-fingerprints: no side effects, used by hexciri-update-hexciri
# to decide light-sync vs full installer without running anything.
# Must run before the IS_RERUN info line below, so the output is just
# the two fingerprint lines and nothing else.
if [ "${PRINT_FP:-0}" = "1" ]; then
  printf 'upstream=%s\npatch=%s\nprovision=%s\nsystem=%s\n' "$(upstream_fingerprint)" "$(patch_fingerprint)" "$(provision_fingerprint)" "$(system_fingerprint)"
  exit 0
fi
# run_pacman: pacman bulk call with its noise captured. On a fresh
# install pacman prints "warning: X is up to date -- skipping" for
# every already-installed package and "there is nothing to do" -- on a
# re-run that is most of the output and none of it is a problem. Capture
# it to a log, print one status line, and only show the log on failure
# (or on real error lines). Usage: run_pacman "<label>" <pacman args...>
run_pacman() {
  local _label="$1"; shift
  local _log _n
  _log="$(mktemp /tmp/hexciri-pacman.XXXXXX)"
  if sudo pacman "$@" >"$_log" 2>&1; then
    _n="$(grep -cE '(\\([0-9]+/[0-9]+\\) )?(installing|upgrading|reinstalling) ' "$_log" 2>/dev/null || true)"
    _n="${_n:-0}"
    if [ "$_n" -gt 0 ]; then
      info "$_label: $_n package(s) installed/updated"
    else
      info "$_label: already up to date"
    fi
    grep -E 'error:|failed to commit' "$_log" 2>/dev/null | head -5 | sed 's/^/[hexciri] pacman: /' || true
    rm -f "$_log"
    return 0
  fi
  printf '[hexciri] pacman failed (%s), error lines only (full log kept at %s):\n' "$_label" "$_log" >&2
  grep -E 'error:|failed|target not found|conflicting|invalid' "$_log" 2>/dev/null | head -20 | sed 's/^/[hexciri] pacman: /' >&2 || true
  return 1
}
INSTALL_DETAIL_LOG="${HEXCIRI_INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
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
# bootstrap.lua integrity (2026-11-24, second emergency-mode breakage):
# existence is NOT enough. Hyprland dofiles this file first; a 0-byte or
# truncated copy passes every -f check and still bricks the next boot
# with no binds. Proven in sim8: a failed write during the patch
# re-apply left a 0-byte bootstrap.lua that sailed through placement
# verification into the installed tree. A good file is the upstream
# 921-byte bootstrap (package.path + HEXCIRI_PATH) plus the preload
# alias on a patched tree (1399 bytes). Check size AND content.
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
# hexciri.lua integrity (2026-11-24, third breakage): same class as
# bootstrap.lua, existence is NOT enough. Hyprland requires
# default.hypr.hexciri at hyprland.lua:17; a 0-byte or truncated copy
# passes every -f / -s check and still trips emergency mode. A good
# patched file is 1428 bytes and requires default.hypr.helpers (plus
# the hexciri-compat require, checked separately at placement).
hyprlua_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 1000 ] || return 1
  grep -q 'require("default.hypr.helpers")' "$_f" 2>/dev/null || return 1
  return 0
}
# hypr_searchpath_ok(): reproduce what Hyprland itself does at boot.
# hyprland.lua dofiles bootstrap.lua (sets package.path), then requires
# default.hypr.hexciri. Existence checks never proved that search, and
# the 926c9d7 update said placement PASS while the next boot still
# could not find the module. Run the exact search with lua5.1
# (5.1-safe: package.searchpath does not exist in Lua 5.1, so walk
# package.path by hand with io.open). Skips silently when lua5.1 is
# not installed; the content checks above still apply.
hypr_searchpath_ok() {
  command -v lua5.1 >/dev/null 2>&1 || { info "hyprland lua searchpath test skipped (lua5.1 not installed)"; return 0; }
  local _lua
  _lua="$(mktemp /tmp/hexciri-hypr-searchpath.XXXXXX.lua)"
  cat > "$_lua" <<'LUA'
dofile((os.getenv("HEXCIRI_PATH") or "/usr/share/hexciri") .. "/default/hypr/bootstrap.lua")
local mod = "default.hypr.hexciri"
local found = nil
for pat in string.gmatch(package.path, "[^;]+") do
  local p = string.gsub(pat, "%?", string.gsub(mod, "%.", "/"))
  local f = io.open(p, "r")
  if f then f:close(); found = p; break end
end
if not found then
  io.stderr:write("hyprland lua searchpath: module '" .. mod .. "' not found in package.path\n")
  os.exit(1)
end
print("hyprland lua searchpath: " .. mod .. " -> " .. found)
LUA
  if HEXCIRI_PATH="$HEXCIRI_PATH" lua5.1 "$_lua"; then rm -f "$_lua"; return 0; fi
  rm -f "$_lua"; return 1
}

# binds_chain_ok(): Super+Space (apps) / Super+Alt+Space (menu) chain
# (2026-11-24, Devi: both chords died after the 2cdc33c7 update failed
# placement on config/tmux/tmux.conf). Both chords dispatch through
# Hyprland GlobalShortcuts, not plain commands: Hyprland Lua binds them
# (default/hypr/bindings/utilities.lua, swapped from upstream so
# SUPER+SPACE is apps and SUPER+ALT+SPACE is menu), the shell registers
# them from default/hexciri/shortcuts, the custom binds file must be
# required by hexciri.lua, and shell.qml must keep GlobalShortcut
# appid "omarchy" (helpers.lua dispatches "omarchy:...", the rename
# must not touch it). Existence is not enough: check the actual lines,
# in the fork before placement and in the placed tree after it, so a
# broken fork dies before rm -rf replaces the last good tree.
binds_chain_ok() {
  local _root="$1" _why=""
  grep -q 'SUPER + ALT + SPACE.*{ menu = "root" }' "$_root/default/hypr/bindings/utilities.lua" 2>/dev/null || _why="utilities.lua: SUPER + ALT + SPACE is not bound to menu root (swap lost)"
  [ -n "$_why" ] || grep -q 'SUPER + SPACE.*{ ipc = "hexciri.dock.apps" }' "$_root/default/hypr/bindings/utilities.lua" 2>/dev/null || _why="utilities.lua: SUPER + SPACE is not bound to ipc hexciri.dock.apps (swap lost)"
  [ -n "$_why" ] || grep -qx 'menu root' "$_root/default/hexciri/shortcuts" 2>/dev/null || _why="shortcuts: 'menu root' missing, shell never registers omarchy:menu.root"
  [ -n "$_why" ] || grep -qx 'ipc hexciri.dock.apps' "$_root/default/hexciri/shortcuts" 2>/dev/null || _why="shortcuts: 'ipc hexciri.dock.apps' missing, shell never registers omarchy:ipc.hexciri.dock.apps"
  [ -n "$_why" ] || grep -q 'require("default.hypr.bindings.hexciri")' "$_root/default/hypr/hexciri.lua" 2>/dev/null || _why="hexciri.lua does not require default.hypr.bindings.hexciri (custom binds never execute)"
  [ -n "$_why" ] || [ -s "$_root/default/hypr/bindings/hexciri.lua" ] || _why="bindings/hexciri.lua missing or empty"
  [ -n "$_why" ] || grep -q 'appid: "omarchy"' "$_root/shell/shell.qml" 2>/dev/null || _why="shell.qml GlobalShortcut appid is not omarchy (helpers.lua dispatches omarchy:..., rename broke it)"
  [ -n "$_why" ] || [ -f "$_root/config/tmux/tmux.conf" ] || _why="config/tmux/tmux.conf missing (placement verification dies on it, update aborts with a new unverified tree live)"
  [ -n "$_why" ] || [ -f "$_root/config/chromium-flags.conf" ] || _why="config/chromium-flags.conf missing (same placement-verification die as tmux)"
  if [ -n "$_why" ]; then printf 'binds chain broken in %s: %s\n' "$_root" "$_why" >&2; return 1; fi
  return 0
}

# --- Hyprland reload guard (2026-11-24, Devi: emergency mode trips on
# every installer re-run) ---
# The guard binary is upstream's, forked into bin/ but never called:
# hexciri-hyprland-reload-guard pause sets misc.disable_autoreload=true
# + debug.suppress_errors=true via hyprctl eval and saves the previous
# values to /run/hexciri/hyprland-reload-guard/<sig>; resume restores
# suppress_errors, reloads once on the complete tree, then restores
# disable_autoreload. monitor-watch already respects it (it skips its
# own reload while the guard is paused). Run via sudo, like upstream's
# root-run ALPM hooks: /run/hexciri is root-owned and a user pause
# would die on mkdir. Best-effort everywhere: a guard failure warns,
# never dies the installer. HYPR_GUARD_PAUSED is only ever 1 between
# pause and resume in this run; cleanup() resumes it on any exit, so
# a dying installer can never leave autoreload off and errors hidden.
HYPR_GUARD_PAUSED=0
HYPR_GUARD_BIN=""
hypr_guard_bin() {
  if [ -x "$HEXCIRI_PATH/bin/hexciri-hyprland-reload-guard" ]; then
    HYPR_GUARD_BIN="$HEXCIRI_PATH/bin/hexciri-hyprland-reload-guard"
  elif [ -n "${FORK_OUT:-}" ] && [ -x "$FORK_OUT/bin/hexciri-hyprland-reload-guard" ]; then
    HYPR_GUARD_BIN="$FORK_OUT/bin/hexciri-hyprland-reload-guard"
  else
    HYPR_GUARD_BIN=""
  fi
  [ -n "$HYPR_GUARD_BIN" ]
}
hypr_guard_pause() {
  pgrep -x Hyprland >/dev/null 2>&1 || return 0
  hypr_guard_bin || { warn "reload guard not found, Hyprland may trip emergency mode during placement (run: hyprctl reload)"; return 0; }
  if sudo "$HYPR_GUARD_BIN" pause 2>/dev/null; then
    HYPR_GUARD_PAUSED=1
    info "Hyprland config auto-reload paused (reload guard, placement replaces /usr/share/hexciri)"
  else
    warn "reload guard pause failed, Hyprland may trip emergency mode during placement (run: hyprctl reload)"
  fi
  return 0
}
hypr_guard_resume() {
  [ "${HYPR_GUARD_PAUSED:-0}" = "1" ] || return 0
  HYPR_GUARD_PAUSED=0
  hypr_guard_bin || return 0
  if sudo "$HYPR_GUARD_BIN" resume 2>/dev/null; then
    info "Hyprland config auto-reload resumed (reload guard, one clean reload on the placed tree)"
  else
    warn "reload guard resume failed, re-enable auto-reload by hand: sudo hexciri-hyprland-reload-guard resume (then check misc.disable_autoreload)"
  fi
  return 0
}

# --- Re-run detection (2026-11-24, Devi: every update reset shell/theme) ---
# A re-run is any install where Hexciri is already installed: the
# self-update path (hexciri-update-hexciri) re-runs this installer whenever
# its sha changed, and a bootstrap after a working install is the same
# thing. On a re-run user config is PRESERVED, only code is updated.
# Fresh install: no marker, no shell.json, no theme.name -> IS_RERUN=0.
IS_RERUN=0
if [ -f "/usr/share/hexciri/.installer-sha" ] || [ -f "$HOME/.config/hexciri/shell.json" ] || [ -f "$HOME/.local/state/hexciri/current/theme.name" ]; then
  IS_RERUN=1
  info "Re-run detected (existing Hexciri install): user settings, theme and shell.json will be preserved, only code is updated"
fi
# Current theme name, if one is staged and still exists in the (new) tree.
# Used by the theme and SDDM steps so a re-run re-applies the user's theme,
# never the first theme dir alphabetically.
current_theme_name() {
  local _t=""
  if [ -f "$HOME/.local/state/hexciri/current/theme.name" ]; then
    _t="$(cat "$HOME/.local/state/hexciri/current/theme.name" 2>/dev/null | tr -d '[:space:]')"
  fi
  if [ -n "$_t" ] && [ -d "$HEXCIRI_PATH/themes/$_t" ]; then
    printf '%s' "$_t"
    return 0
  fi
  return 1
}

# --light-sync: v1-style self-update. Both fingerprints match, so the
# installed fork is already correct and nothing in the system needs to
# change; only the installer sha marker (and the repo bins that are
# copied straight into /usr/share/hexciri/bin) need syncing. No pacman,
# no fork, no theme re-apply, no settings touched at all.
if [ "${LIGHT_SYNC:-0}" = "1" ]; then
  _ls_sha="$(installer_tree_sha)"
  for _ls_f in hexciri-update-hexciri hexciri-theme-ansi hexciri-theme-link hexciri-web-search hexciri-settings-tabs hexciri-launch-settings hexciri-font-maple-cn-present; do
    if [ -f "$HEXCIRI_REPO_ROOT/v2/$_ls_f" ] && [ -d /usr/share/hexciri/bin ]; then
      if ! cmp -s "$HEXCIRI_REPO_ROOT/v2/$_ls_f" "/usr/share/hexciri/bin/$_ls_f" 2>/dev/null; then
        sudo install -Dm755 "$HEXCIRI_REPO_ROOT/v2/$_ls_f" "/usr/share/hexciri/bin/$_ls_f" && info "Light sync: updated /usr/share/hexciri/bin/$_ls_f"
      fi
    fi
  done
  unset _ls_f
  printf '%s\n' "$_ls_sha" | sudo tee /usr/share/hexciri/.installer-sha >/dev/null
  printf '%s\n' "$(upstream_fingerprint)" | sudo tee /usr/share/hexciri/.upstream-fingerprint >/dev/null
  printf '%s\n' "$(patch_fingerprint)" | sudo tee /usr/share/hexciri/.patch-fingerprint >/dev/null
  printf '%s\n' "$(fork_fingerprint)" | sudo tee /usr/share/hexciri/.fork-fingerprint >/dev/null
  printf '%s\n' "$(provision_fingerprint)" | sudo tee /usr/share/hexciri/.provision-fingerprint >/dev/null
  printf '%s\n' "$(system_fingerprint)" | sudo tee /usr/share/hexciri/.system-fingerprint >/dev/null
  info "Light sync done: installer marker updated, no packages, theme or settings touched"
  exit 0
fi

cleanup() {
  if [ -n "${TMP_WORK:-}" ] && [ -d "$TMP_WORK" ]; then
    rm -rf "$TMP_WORK"
  fi
  # A dying installer must never leave auto-reload off and errors hidden:
  # resume the reload guard if this run paused it. No-op when it never
  # paused (fresh install, no Hyprland, light-sync, --print-fingerprints).
  if [ "${HYPR_GUARD_PAUSED:-0}" = "1" ]; then
    hypr_guard_resume || true
  fi
}
trap cleanup EXIT

# --- Minimal re-apply (2026-11-24, Devi: the full installer re-ran
# on every update even when 99.9% of it never changed) ---
# --re-apply (fork patch only) and --re-apply-provision (system
# config only) skip whole installer chunks below via REAPPLY /
# REAPPLY_PROV guards. The skipped chunks own things the kept chunks
# need, so set them up here first:
#   * Fresh install guard: on a machine with no Hexciri yet, a
#     re-apply would skip provisioning before the first install.
#     Fall back to the full installer instead, never silently
#     ship a half-installed system.
#   * EUID / sudo: the Preflight chunk is skipped in both modes,
#     so its checks move here (placement still needs sudo).
#   * TMP_WORK / FORK_OUT / OMARCHY_SRC: also set in Preflight,
#     also skipped. --re-apply uses the temp fork-out like a full
#     run; --re-apply-provision never forks, it only reads the
#     browser sudoers file out of the cached patched tree, so
#     FORK_OUT points at the fork cache there instead.
if [ "${REAPPLY:-0}" = "1" ] || [ "${REAPPLY_PROV:-0}" = "1" ]; then
  if [ "${IS_RERUN:-0}" != "1" ]; then
    warn "Re-apply requested on a fresh install, running the full installer instead (provisioning cannot be skipped before the first install)"
    REAPPLY=0
    REAPPLY_PROV=0
  else
    if [ "$EUID" -eq 0 ]; then
      die "Do not run as root. Run as your normal user with sudo available."
    fi
    if ! command -v sudo >/dev/null 2>&1; then
      die "sudo is required."
    fi
    TMP_WORK="$(mktemp -d /tmp/hexciri-install.XXXXXX)"
    FORK_OUT="$TMP_WORK/fork-out"
    OMARCHY_SRC="$TMP_WORK/omarchy"
    if [ "${REAPPLY_PROV:-0}" = "1" ] && [ -d "$FORK_CACHE_DIR/fork-out/etc/sudoers.d" ]; then
      FORK_OUT="$FORK_CACHE_DIR/fork-out"
    fi
    if [ "${REAPPLY:-0}" = "1" ]; then
      info "Re-apply: fork patch only (packages, GPU, SDDM, theme, GTK, PAM, trim skipped, none of their inputs changed)"
    else
      info "Re-apply: system config only (packages, fork, placement skipped, none of their inputs changed)"
    fi
    info "Work dir: $TMP_WORK"
  fi
fi

# Minimal re-apply: system provisioning (preflight, packages, apps,
# GPU, SDDM, services) runs on a fresh install and on a full re-run
# only. Both re-apply modes skip it: none of its inputs changed, and
# the early re-apply block above already set TMP_WORK / FORK_OUT and
# checked EUID + sudo.
if [ "${REAPPLY:-0}" != "1" ] && [ "${REAPPLY_PROV:-0}" != "1" ]; then
# --- Preflight ---

step "Preflight checks"

if [ "$EUID" -eq 0 ]; then
  die "Do not run as root. Run as your normal user with sudo available."
fi

if ! command -v sudo >/dev/null 2>&1; then
  die "sudo is required."
fi

if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "endeavouros" ]; then
    warn "This script expects EndeavourOS, found ID=${ID:-unknown}. Continuing anyway."
  else
    step "Confirmed EndeavourOS"
  fi
fi

if ! command -v yay >/dev/null 2>&1; then
  die "yay not found. EndeavourOS should ship yay. Fix yay first, then rerun."
fi

# Pac-Man progress bars, 2026-11-24 (Devi prefers the Arch ILoveCandy
# bar to pacman's plain [----] bar): ILoveCandy in /etc/pacman.conf makes
# pacman draw Pac-Man eating dots. yay and eos-update both shell out to
# pacman, so their bars get it too, as does the hexciri-update fallback
# pacman path. The curl downloads (bootstrap, tarball fetches) used
# to show curl's old -=O=- bar; they are now silent (curl -fsSL)
# with a size line after, so the only progress bar you see is
# pacman's ILoveCandy one. Note: on a re-run installer most
# packages are already installed (--needed), so pacman has
# nothing to download and no Pac-Man bar appears at all. That
# is normal, not a broken bar.
step "Enabling Pac-Man progress bar (ILoveCandy) in /etc/pacman.conf"
if grep -q '^ILoveCandy' /etc/pacman.conf; then
  info "ILoveCandy already enabled in /etc/pacman.conf (pacman eats dots)"
elif grep -q '^#ILoveCandy' /etc/pacman.conf; then
  sudo sed -i 's/^#ILoveCandy/ILoveCandy/' /etc/pacman.conf
  grep -q '^ILoveCandy' /etc/pacman.conf && info "ILoveCandy enabled in /etc/pacman.conf (was commented out)" || warn "could not enable ILoveCandy in /etc/pacman.conf"
elif grep -q '^\[options\]' /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a ILoveCandy' /etc/pacman.conf
  grep -q '^ILoveCandy' /etc/pacman.conf && info "ILoveCandy added to /etc/pacman.conf under [options]" || warn "could not add ILoveCandy to /etc/pacman.conf"
else
  warn "no [options] section in /etc/pacman.conf, ILoveCandy not set (add ILoveCandy under [options] by hand)"
fi

if ! command -v lspci >/dev/null 2>&1; then
  warn "lspci not found, installing pciutils first so GPU detection works."
  sudo pacman -S --needed --noconfirm pciutils
fi

step "Free space check (needs at least 10 GB free on /)"
AVAIL_GB="$(df --output=avail -BG / | tail -1 | tr -dc '0-9')"
if [ -z "$AVAIL_GB" ]; then
  die "Could not read free space on /."
fi
echo "Free on /: ${AVAIL_GB}G"
if [ "$AVAIL_GB" -lt 10 ]; then
  die "Only ${AVAIL_GB}G free on /. Free at least 10 GB, then rerun."
fi

step "Internet check"
if ! curl -fsSI --max-time 10 https://archlinux.org >/dev/null 2>&1; then
  die "No internet or archlinux.org unreachable. Fix networking, then rerun."
fi

step "Checking for mkinitcpio (must NOT be installed, dracut is used)"
if pacman -Q mkinitcpio >/dev/null 2>&1; then
  warn "mkinitcpio is installed. This script will not install or remove it. Check dracut setup manually."
else
  echo "mkinitcpio not installed, good."
fi

TMP_WORK="$(mktemp -d /tmp/hexciri-install.XXXXXX)"
FORK_OUT="$TMP_WORK/fork-out"
OMARCHY_SRC="$TMP_WORK/omarchy"
info "Work dir: $TMP_WORK"

# --- Multilib ---

step "Enabling multilib in pacman.conf (needed for lib32 packages)"
if grep -q '^\[multilib\]' /etc/pacman.conf; then
  echo "multilib already enabled."
else
  sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
  if grep -q '^\[multilib\]' /etc/pacman.conf; then
    echo "multilib enabled."
  else
    die "Could not enable multilib in /etc/pacman.conf. Enable it manually, then rerun."
  fi
fi

step "Syncing package databases"
run_pacman "Package databases" -Sy --noconfirm

# --- Kernel headers helper (needed for dkms Nvidia drivers) ---

install_kernel_headers() {
  local kernel
  kernel="$(uname -r)"
  echo "Running kernel: $kernel"
  if [[ "$kernel" == *lts* ]]; then
    run_pacman "Kernel headers (linux-lts-headers)" -S --needed --noconfirm linux-lts-headers
  else
    run_pacman "Kernel headers (linux-headers)" -S --needed --noconfirm linux-headers
  fi
}

# --- Core packages ---

step "Installing core Hyprland, uwsm, SDDM, portals, Qt6, tools, fonts"

CORE_PKGS=(
  hyprland uwsm sddm
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  xdg-user-dirs xdg-utils xdg-terminal-exec xorg-xwayland # xdg-terminal-exec: Arch Extra stable 0.14.4-1, verified live 2026-11-25 (was extra-testing at install time, Devi 20:37 MST). Every terminal-with-args launch needs it: launch-terminal with args, launch-tui, floating-terminal-with-presentation, TUI desktop entries, Quickshell Terminal=true entries. Without it the grid shows "App failure: Command not found: xdg-terminal-exec".
  qt6-base qt6-declarative qt6-wayland qt6-svg qt6-5compat qt6-multimedia qt6-imageformats squashfs-tools # squashfs-tools: Hexciri Settings AppImages pane (reads AppImage name/icon without running it)
  polkit rtkit gnome-keyring libsecret
  pamixer brightnessctl jq bc curl wget git base-devel pacman-contrib socat # checkupdates, for hexciri-update-available (update icon); socat is hexciri-shell's IPC transport (socket fast path), upstream omarchy-base.packages line 145, without it every hexciri-shell call fails "not responding"
  fprintd usbutils # fprintd + usbutils: Setup > Security > Fingerprint needs fprintd-enroll/verify, hw-fingerprint probes USB readers
  imagemagick inotify-tools grim slurp wl-clipboard hyprpicker hyprsunset ffmpeg unzip libvips ffmpegthumbnailer librsvg zenity # libvips (vipsthumbnail) + ffmpegthumbnailer: hexciri-menu-images needs both to draw image-picker thumbnails (Appearance > Icons, background picker); upstream omarchy-base.packages ships both (lines 82, 46) and the fork lacked them, so every row was dropped and the picker loaded nothing. librsvg (rsvg-convert): hexciri-icons-preview draws set previews with it. zenity: GTK file dialog, LocalSend's file picker falls back to it when the portal is unavailable.
  ripgrep fd fzf eza bat starship zoxide fastfetch gum # gum: upstream omarchy-base.packages line 60; forked scripts use it (icons-install custom repo URL, battlenet partial-prefix wipe prompt, xbox-controllers reboot prompt)
  # NOTE 2026-11-23: no btop here, v1 removes it, bottom (in APP_PKGS below)
  # is the Hexciri system monitor instead. fastfetch's Hexciri config is
  # placed in the default apps step below (config/fastfetch/config.jsonc).
  python python-gobject lua51 luarocks
  mise # Phase 2 2026-11-24: reinstall mise so the rest of the Omarchy scripts work (mise up, lazy tools from /etc/mise/conf.d/hexciri-tools.toml)
  kitty
  udiskie
  noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd woff2-font-awesome terminus-font
  # NOTE 2026-11-23: kitty, not foot: Devi chose Kitty as the default
  # terminal (Omarchy's default is Foot). ttf-jetbrains-mono-nerd is the
  # Nerd Font that provides the Arch logo glyph U+F303 used for the menu
  # trigger icon. udiskie is Arch extra: autostart runs it via uwsm-app,
  # and its absence showed as "App failure, Command not found: udiskie".
  # NOTE 2026-11-23: noto-fonts-cjk-vf and ttf-jetbrains-mono-nerd-basic are
  # Omarchy-repo-only names (Omarchy edge channel / omarchy pkg), NOT Arch.
  # pacman on plain Arch/EndeavourOS fails with "target not found" on both.
  # Arch extra equivalents: noto-fonts-cjk, ttf-jetbrains-mono-nerd.
)

run_pacman "Core packages" -S --needed --noconfirm "${CORE_PKGS[@]}"

# xdg-terminal-exec is in CORE_PKGS above (Arch Extra stable 0.14.4-1,
# verified live on archlinux.org 2026-11-25; the extra-testing note this
# replaced was stale, it moved to stable Extra). Verify it actually
# landed: a stale mirror can still fail the pacman call above, and
# without the binary every terminal-with-args launch dies with
# "App failure: Command not found: xdg-terminal-exec" (desktop dokoz,
# 2026-11-24). Plain Super+Return still works without it via the
# xdg-terminals.list fast path (kitty first), but launch-tui /
# floating-terminal / TUI entries do not.
if command -v xdg-terminal-exec >/dev/null 2>&1; then
  info "xdg-terminal-exec installed: $(command -v xdg-terminal-exec)"
else
  warn "xdg-terminal-exec NOT installed after Core packages (stale mirror?): terminal-with-args launches will fail, plain Super+Return still works via the xdg-terminals.list fast path. Re-run hexciri update once the mirror syncs."
fi

step "Updating user directories"
xdg-user-dirs-update || warn "xdg-user-dirs-update failed, not fatal."

# --- Hexciri default apps ---
# Devi 2026-11-23: install Hexciri default apps so basic binds can be tested.
# Base is Omarchy's defaults (install/omarchy-base.packages at the pinned
# commit), with only Hexciri's few replacements, per v1 main install.sh and
# bin/hexciri-mime-defaults:
#   Kitty over Foot (already in CORE_PKGS above)
#   Strata over Folio (GitHub release, Strata step below)
#   Brave Origin over Chrome (AUR below, Release channel, free on Linux)
#   zathura over papers/mupdf (v1 PDF pick), imv as image viewer (v1 pick)
#   zed as editor (v1 want), bottom over btop (v1 stock removal)
# NOT installed: google-chrome, foot, folio, btop, plain / omacalc /
# omawrite / omaview / herdr / cliamp / omasnap (Omarchy-repo-only, no Arch
# or AUR package exists for them), docker, AI agents (pi-coding-agent),
# fuzzel / noctalia (v2 shell is Quickshell, not fuzzel/Noctalia).
# opencode is the exception (2026-11-24, Devi): v1 shipped it via
# pacman and it just opens and works, so it is in APP_PKGS above.
# fuzzel/Noctalia). They are SUBSTITUTED with Arch defaults instead, so
# their binds work (2026-11-23, Devi: most Omarchy apps can just
# substitute with Arch defaults/alternatives):
#   omasnap (screenshot, PRINT / SUPER+CTRL+ALT+C) -> grim + slurp, the
#     fork patch step below rewrites hexciri-capture-screenshot to use
#     them (capture-text and capture-qr already used grim/slurp directly).
#   omacalc (SUPER+SHIFT+Q, XF86Calculator) -> gnome-calculator.
#   cliamp (Music TUI, SUPER+SHIFT+ALT+M) and omawrite (SUPER+SHIFT+W)
#     binds are REMOVED, not substituted: Devi 2026-11-23 does not want
#     ncspot or ghostwriter, and neither app is installed. herdr
#     (SUPER+CTRL+RETURN, Omarchy AI-agent terminal) -> bind removed,
#     herdr is an AI agent and AI agents are out of v2 scope; tmux is
#     already on Super+Alt+Return. omaview -> imv (already the v1 image
#     viewer pick). Editor is zed already, no substitute needed.
# Spotify is the one exception: it IS installed (its own step below),
# not substituted, because Devi's bind is Spotify specifically.
# Pacman step: one bulk call first, per-package best-effort retry if it
# fails, so one wrong/stale name never aborts the install. AUR/GitHub apps
# are best-effort, never fatal, same rule as Strata below.

step "Installing Hexciri default apps (Omarchy defaults + Hexciri replacements)"

APP_PKGS=(
  # Bind/menu-called: tmux (Super+Alt+Return),
  # gpu-screen-recorder + wf-recorder fallback (menu Capture > Screenrecord),
  # zbar (capture-qr decodes with zbarimg), localsend is AUR localsend-bin (own step below, menu Share > Receive),
  # mpv (v1 default video player), zathura + plugins (v1 PDF pick),
  # imv (v1 image viewer pick), zed (v1 editor pick), playerctl (v1 layer
  # need, media keys), bottom (v1 pick, replaces btop), seahorse (keyring
  # GUI), fwupd (menu Update > Firmware), adw-gtk-theme (v1 layer need, GTK
  # apps unthemed without it), tesseract-data-eng (OCR data) + tesseract
  # itself (capture-text OCR, SUPER+CTRL+PRINT, needs the binary, it was
  # NOT in CORE_PKGS despite an old comment saying so), cliphist (v1 want), libqalculate
  # (v1 want, ships the qalc CLI), libreoffice-fresh +
  # gnome-disk-utility (Omarchy default apps), lazygit, yt-dlp, gvfs
  # (file-manager trash/network backends), qrencode. eject was dropped
  # 2026-11-24: no eject package in the Arch repos (error: target not
  # found: eject), and it alone failed the bulk install, which dumped
  # the whole pacman log. The XF86Eject bind still calls eject;
  # laptops have no eject key, harmless.
  # REMOVED 2026-11-23, Devi does not want them, and the trim step below
  # removes them if present so they never come back: neovim (launch-editor
  # falls back to nano now, nano ships in Arch base), obsidian (its
  # Super+Shift+O bind is removed with it), pinta, ncspot (cliamp Music
  # TUI substitute, bind removed), ghostwriter (omawrite substitute, bind
  # removed). meld, xterm/uxterm and stoken (Software Token) were never in
  # this list (EndeavourOS base / deps) and are removed by the trim step.
  # Arch substitutes for Omarchy-repo-only apps (2026-11-23, Devi: most
  # Omarchy apps can just substitute with Arch defaults/alternatives, do
  # NOT try to install the Omarchy-repo-only ones): gnome-calculator for
  # omacalc (SUPER+SHIFT+Q, XF86Calculator). Screenshot (omasnap) is
  # substituted in the fork patch step below: hexciri-capture-screenshot is
  # rewritten to grim + slurp, both already in CORE_PKGS. Spotify is NOT
  # here, it is AUR (yay -S spotify) in its own step below.
  tmux gpu-screen-recorder wf-recorder
  mpv zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb
  zed playerctl bottom seahorse fwupd adw-gtk-theme tesseract tesseract-data-eng
  cliphist libqalculate libreoffice-fresh gnome-disk-utility
  lazygit yt-dlp gvfs zbar qrencode imv
  gnome-calculator
  opencode # v1 pacman install (2026-11-24, Devi): Hexciri v1 shipped
  # opencode in its pacman wants list, install and start using, no setup.
  # Arch extra has opencode 2.4.1-1 (2026-11-23). Its free models
  # (Big Pickle et al) need no account: the TUI opens straight to the
  # prompt. Do NOT move it to mise: hexciri-tools.toml excludes AI CLIs
  # on purpose, and default-agent must see the pacman binary as present.
)
if ! run_pacman "Default apps" -S --needed --noconfirm "${APP_PKGS[@]}"; then
  warn "Bulk default-apps install failed, retrying per package (best-effort)."
  _app_ok=0; _app_bad=0
  for _pkg in "${APP_PKGS[@]}"; do
    if sudo pacman -S --needed --noconfirm "$_pkg" >/dev/null 2>&1; then
      _app_ok=$((_app_ok + 1))
    else
      _app_bad=$((_app_bad + 1))
      warn "  NOT installed: $_pkg (install by hand: sudo pacman -S $_pkg)"
    fi
  done
  info "Default apps retry: $_app_ok installed, $_app_bad failed"
  unset _pkg _app_ok _app_bad
fi

# --- LocalSend (menu Share > Receive), AUR, best-effort ---
# localsend is NOT in the Arch repos, so it must never go in the pacman
# APP_PKGS call above: a missing target aborts the whole bulk transaction
# and the per-package retry just warns. The AUR package is localsend-bin
# (1.18.2-2, more popular than the source localsend build). Devi 2026-11-23:
# yay -S localsend-bin for that one.
step "Installing LocalSend (AUR localsend-bin, best-effort)"
if command -v localsend >/dev/null 2>&1; then
  info "LocalSend already present"
elif yay -S --needed --noconfirm localsend-bin 2>/dev/null; then
  info "LocalSend installed via yay (AUR localsend-bin)"
else
  warn "LocalSend install failed (yay/AUR unreachable), menu Share > Receive will fail until it is installed. Install by hand: yay -S localsend-bin"
fi

# --- Maple Mono NF (Devi's default font, 2026-11-24), AUR, best-effort ---
# maplemono-nf (AUR 7.9-1, NOT ttf-maple-mono-nf: no such package) is the
# Nerd Font build of Maple Mono: family "Maple Mono NF", spacing=100, so it
# passes hexciri-font-list's :spacing=100 filter (verified with fc-scan on
# the real v7.9 files). It is not in the Arch repos and was never installed
# by the base packages, so Appearance > Font could never list it and
# Install > Style > Font had no row for it: the only route was yay +
# hexciri-font-set by hand. Installing it here makes it show up in the
# menu font list like any other installed font.
# maplemono-nf-cn (Devi's actual variant) is deliberately NOT auto-installed
# here: 16 TTFs, 320 MiB (PR #16025's reason, and Devi already has it). It
# is one click away in Install > Style > Font > Maple Mono CN instead.
step "Installing Maple Mono NF (AUR maplemono-nf, best-effort)"
# 2026-11-24 reinstall fix (Devi: update re-installed Maple Mono NF CN
# when he already had it via AUR): the old guard was fc-list only, a
# family-name/fontconfig-cache check, never a pacman check. And
# maplemono-nf / maplemono-nf-cn are split packages of ONE pkgbase
# (maplemono, AUR 7.9-1): makepkg downloads ALL 11 source zips whatever
# split you ask for, including MapleMono-NF-CN.zip (320 MiB), so running
# yay here at all re-fetches CN. Guard on pacman first, over every known
# Maple NF package name (both AUR namings, plain + CN + unhinted): any
# one installed means the font is already there, skip, no yay, no
# download. fc-list stays as second guard for hand-installed fonts.
if pacman -Q maplemono-nf maplemono-nf-cn maplemono-nf-unhinted maplemono-nf-cn-unhinted maple-mono-nf-cn maple-mono-nf-cn-unhinted 2>/dev/null | grep -q .; then
  info "Maple Mono NF already installed (pacman: $(pacman -Q maplemono-nf maplemono-nf-cn maplemono-nf-unhinted maplemono-nf-cn-unhinted maple-mono-nf-cn maple-mono-nf-cn-unhinted 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'))"
elif fc-list 2>/dev/null | grep -Fqi "Maple Mono NF"; then
  info "Maple Mono NF already installed (fontconfig)"
elif yay -S --needed --noconfirm maplemono-nf 2>/dev/null; then
  info "Maple Mono NF installed via yay (AUR maplemono-nf)"
else
  warn "Maple Mono NF install failed (yay/AUR unreachable), Appearance > Font will not list it until it is installed. Install by hand: yay -S maplemono-nf"
fi

# --- LocalSend firewall (2026-11-24): discovery is multicast UDP
# 224.0.0.167:53317, transfer is HTTPS TCP 53317, and LocalSend is NOT
# mDNS (no UDP 5353 involved). firewalld is enabled on EndeavourOS and
# its default zone drops inbound traffic, so without this rule no other
# device can reach this laptop's LocalSend at all: it never appears in
# their device list, and they never appear here either. Best-effort,
# never dies: when the daemon is running, firewall-cmd --permanent plus
# --reload applies it live; when it is not running yet, the offline
# tool writes the permanent config and it applies at next start.
if systemctl is-active --quiet firewalld 2>/dev/null && command -v firewall-cmd >/dev/null 2>&1; then
  if sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp >/dev/null 2>&1 && sudo firewall-cmd --reload >/dev/null 2>&1; then
    info "LocalSend firewall: 53317/tcp + 53317/udp open in firewalld (discovery + transfer)"
  else
    warn "LocalSend firewall: could not open 53317 in firewalld, other devices may not see this laptop (run: sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp && sudo firewall-cmd --reload)"
  fi
elif command -v firewall-offline-cmd >/dev/null 2>&1; then
  if sudo firewall-offline-cmd --add-port=53317/tcp --add-port=53317/udp >/dev/null 2>&1; then
    info "LocalSend firewall: 53317/tcp + 53317/udp open in firewalld permanent config (applies at next firewalld start)"
  else
    warn "LocalSend firewall: could not open 53317 in firewalld, other devices may not see this laptop (run: sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp && sudo firewall-cmd --reload)"
  fi
fi

# --- Brave Origin (default browser), AUR, best-effort ---
# Brave Origin is the version Devi uses (v1 main install.sh: AUR want
# brave-origin-bin; brave-bin is only a stand-in, removed once Origin is
# present). Minimalist Brave build (no Leo AI / Rewards / Wallet / VPN),
# free on Linux (a $59.99 one-time purchase elsewhere), Release channel:
# NOT brave-origin-beta / brave-beta-bin / brave-nightly, NOT normal
# brave-bin. Omarchy's own install-browser uses the same package
# (omarchy-pkg-aur-add brave-origin-bin), and Brave's Linux docs give
# `yay -Sy brave-origin-bin` as the Arch route. Binary is brave-origin,
# desktop entry brave-origin.desktop. Do NOT install google-chrome:
# Brave Origin replaces Omarchy's Chrome.
step "Installing Brave Origin (default browser, AUR, best-effort)"
if command -v brave-origin >/dev/null 2>&1; then
  info "Brave Origin already present"
elif yay -S --needed --noconfirm brave-origin-bin 2>/dev/null; then
  info "Brave Origin installed via yay (brave-origin-bin)"
else
  warn "Brave Origin install failed (yay/AUR unreachable), browser binds will fail until it is installed. Install by hand: yay -S brave-origin-bin"
fi
# v1 behaviour: drop the normal-Brave stand-in once Origin is present.
if command -v brave-origin >/dev/null 2>&1 && pacman -Q brave-bin >/dev/null 2>&1; then
  if sudo pacman -Rns --noconfirm brave-bin 2>/dev/null; then
    info "Removed brave-bin stand-in (Brave Origin is present)"
  else
    warn "kept brave-bin (removal failed)"
  fi
fi

# --- Spotify (Super+Shift+M), AUR, best-effort ---
# Devi 2026-11-23: "shift + super m is usually spotify." Upstream Omarchy
# has NO Super+Shift+M bind at all: its only music bind is
# Super+Shift+Alt+M = cliamp (Music TUI, Omarchy-repo-only), which the fork
# patch step below REMOVES (ncspot not wanted, Devi 2026-11-23). Super+Shift+M = Spotify is Devi's
# own bind, added by that same patch step.
# Install method: v1 main install.sh installs no Spotify itself, but v1's
# bin/hexciri-setup spotify subcommand expects a Spotify bundle at
# /opt/spotify or /usr/share/spotify ("install spotify first"), which is
# exactly where the AUR `spotify` package puts it (verified AUR
# 1:1.3.8.620-1, /usr/bin/spotify + /opt/spotify + spotify.desktop).
# Arch extra's spotify-launcher (0.6.7) is only the fallback: it downloads
# the client to ~/.local/share/spotify-launcher, puts no bundle at
# /opt/spotify (so v1's spicetify setup would not find it), and its binary
# is spotify-launcher, not spotify, so the bind would miss it. The
# post-placement step below writes a `spotify` wrapper into
# /usr/share/hexciri/bin/ when only spotify-launcher is present.
# spicetify-cli (verified AUR 2.46.7-1) is installed best-effort too, for
# v1's Spicetify theming later; the hexciri-spotify-setup one-shot is NOT
# run here, it needs Spotify to have launched once first. Run it by hand
# after the first Spotify launch: hexciri-spotify-setup
step "Installing Spotify (Super+Shift+M, AUR, best-effort)"
if command -v spotify >/dev/null 2>&1; then
  info "Spotify already present"
elif yay -S --needed --noconfirm spotify 2>/dev/null; then
  info "Spotify installed via yay (AUR spotify)"
elif sudo pacman -S --needed --noconfirm spotify-launcher 2>/dev/null; then
  info "Spotify installed via pacman fallback (Arch extra spotify-launcher), a spotify wrapper is added after placement"
else
  warn "Spotify install failed (yay/AUR and pacman both failed), Super+Shift+M will fail until it is installed. Install by hand: yay -S spotify"
fi
if ! command -v spicetify >/dev/null 2>&1; then
  if yay -S --needed --noconfirm spicetify-cli 2>/dev/null; then
    info "spicetify-cli installed via yay (for Hexciri Spotify theming later)"
  else
    warn "spicetify-cli not installed (yay failed or AUR unreachable), Spotify theming via hexciri-spotify-setup will wait until it is. Install later: yay -S spicetify-cli"
  fi
fi

# --- Pin Hexciri default apps ---
# Same picks as v1 bin/hexciri-mime-defaults: browser brave-origin, PDF
# zathura, images imv, editor zed (nano fallback, neovim removed 2026-11-23). Files (Strata) is
# pinned in the Strata step below, its desktop entry does not exist until
# Strata is installed. State files live at ~/.local/state/hexciri/defaults/,
# the same path launch-editor reads (renamed from omarchy by the fork).
# Do NOT call hexciri-default-browser here: it checks browser extensions
# via omarchy-install-browser-extensions, which is NOT copied into the fork
# (install-* scripts are excluded), so it would fail. xdg-settings is what
# that script itself ends with, and launch-browser reads the same default
# via omarchy-cmd-default-browser.
mkdir -p "$HOME/.local/state/hexciri/defaults"
if command -v brave-origin >/dev/null 2>&1; then
  [ -f "$HOME/.local/state/hexciri/defaults/browser" ] || printf '%s' "brave-origin" > "$HOME/.local/state/hexciri/defaults/browser"
  if [ -f /usr/share/applications/brave-origin.desktop ] || [ -f "$HOME/.local/share/applications/brave-origin.desktop" ]; then
    if xdg-settings set default-web-browser brave-origin.desktop 2>/dev/null; then
      info "Default browser: Brave Origin (brave-origin.desktop)"
    else
      warn "xdg-settings could not set Brave Origin as default browser"
    fi
    xdg-mime default brave-origin.desktop x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml 2>/dev/null || warn "xdg-mime could not pin Brave Origin handlers"
  else
    warn "brave-origin.desktop not found, default browser not pinned (Brave Origin installed but its desktop entry is missing)"
  fi
else
  warn "brave-origin not installed, default browser not set"
fi
if command -v zathura >/dev/null 2>&1; then
  [ -f "$HOME/.local/state/hexciri/defaults/pdf" ] || printf '%s' "zathura" > "$HOME/.local/state/hexciri/defaults/pdf"
  xdg-mime default org.pwmt.zathura.desktop application/pdf application/epub+zip application/postscript image/vnd.djvu 2>/dev/null || warn "xdg-mime could not pin zathura for documents"
  info "Default PDF reader: zathura"
fi
if command -v zeditor >/dev/null 2>&1; then
  [ -f "$HOME/.local/state/hexciri/defaults/editor" ] || printf '%s' "zeditor" > "$HOME/.local/state/hexciri/defaults/editor"
  info "Default editor: zed (zeditor)"
elif command -v zed >/dev/null 2>&1; then
  [ -f "$HOME/.local/state/hexciri/defaults/editor" ] || printf '%s' "zed" > "$HOME/.local/state/hexciri/defaults/editor"
  info "Default editor: zed"
elif command -v nano >/dev/null 2>&1; then
  [ -f "$HOME/.local/state/hexciri/defaults/editor" ] || printf '%s' "nano" > "$HOME/.local/state/hexciri/defaults/editor"
  info "Default editor: nano (zed not installed, neovim removed 2026-11-23)"
fi
if command -v imv >/dev/null 2>&1; then
  [ -f "$HOME/.local/state/hexciri/defaults/images" ] || printf '%s' "imv" > "$HOME/.local/state/hexciri/defaults/images"
  info "Default image viewer: imv"
fi

# --- fastfetch config (Hexciri's, from the repo tree) ---
# fastfetch itself is already in CORE_PKGS above (Arch extra). Its config
# lives in v1 at config/fastfetch/config.jsonc, and its logo at
# branding/hexciri-nb.png, both present on nyx. The config goes to
# /etc/fastfetch/config.jsonc, NOT ~/.config/fastfetch/: the Hexciri config
# is the one About runs (hexciri-launch-about passes --config
# /etc/fastfetch/config.jsonc). A user config left behind is moved aside
# first, otherwise plain `fastfetch` in a terminal picks it up instead.
# Terminal fastfetch still finds the config: it searches /etc/fastfetch
# after the user dir.
# Best-effort, never fatal: a missing config still leaves a working
# fastfetch.
mkdir -p "$HOME/.config/fastfetch"
if [ -f "$HOME/.config/fastfetch/config.jsonc" ] && [ "${IS_RERUN:-0}" = "0" ]; then
  mv "$HOME/.config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc.hexciri.bak"
  info "Moved existing ~/.config/fastfetch/config.jsonc aside to config.jsonc.hexciri.bak (About would use it instead of the Hexciri config)"
elif [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
  info "Kept your ~/.config/fastfetch/config.jsonc (re-run, not moved aside again)"
fi
if [ -f "$HEXCIRI_REPO_ROOT/config/fastfetch/config.jsonc" ]; then
  if sudo install -Dm644 "$HEXCIRI_REPO_ROOT/config/fastfetch/config.jsonc" /etc/fastfetch/config.jsonc; then
    info "Placed: /etc/fastfetch/config.jsonc (Hexciri fastfetch config, About runs it from here)"
  else
    warn "could not install /etc/fastfetch/config.jsonc, fastfetch keeps its stock config and About falls back to the stock layout"
  fi
else
  warn "config/fastfetch/config.jsonc not found in the installer tree, fastfetch keeps its stock config."
fi
[ -f /etc/fastfetch/config.jsonc ] || warn "no /etc/fastfetch/config.jsonc, About will use the stock fastfetch layout"
[ ! -f "$HOME/.config/fastfetch/config.jsonc" ] || { if [ "${IS_RERUN:-0}" = "1" ]; then info "a user fastfetch config is present (re-run, kept, About falls back to it)"; else warn "a user fastfetch config is still present, About falls back to it until it is moved aside"; fi; }
if [ -f "$HEXCIRI_REPO_ROOT/branding/hexciri-nb.png" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/branding/hexciri-nb.png" "$HOME/.config/fastfetch/hexciri-nb.png"
  info "Placed: ~/.config/fastfetch/hexciri-nb.png (fastfetch logo)"
else
  warn "branding/hexciri-nb.png not found in the installer tree, fastfetch logo will be missing (the config references it)."
fi

# --- Quickshell ---

step "Installing Quickshell from Arch extra (stock first, NOT quickshell-git by default)"
if run_pacman "Quickshell" -S --needed --noconfirm quickshell; then
  echo "Stock quickshell installed."
else
  warn "Stock quickshell install failed. Falling back to quickshell-git from AUR."
  yay -S --needed --noconfirm quickshell-git
fi

step "Testing Quickshell"
if command -v quickshell >/dev/null 2>&1; then
  quickshell --version || warn "quickshell binary exists but --version failed. Try quickshell-git from AUR if the shell fails to start."
else
  warn "quickshell binary not found after install. Fallback: yay -S quickshell-git"
fi

# --- GPU detection and drivers ---

step "Detecting GPU"
GPU_INFO="$(lspci -nn | grep -iE 'vga|3d controller' || true)"
echo "$GPU_INFO"
if [ -z "$GPU_INFO" ]; then
  warn "No VGA device found in lspci output. Skipping GPU driver install. Install drivers manually."
fi

HAS_AMD=0
HAS_NVIDIA=0
if echo "$GPU_INFO" | grep -qi 'amd\|advanced micro devices'; then
  HAS_AMD=1
fi
if echo "$GPU_INFO" | grep -qi 'nvidia'; then
  HAS_NVIDIA=1
fi

# install_nvidia_open (2026-11-24, desktop hybrid bug): nvidia-open and
# nvidia-open-dkms conflict with each other, and both conflict with the
# closed nvidia / nvidia-dkms. EndeavourOS base already ships nvidia-open
# on Nvidia systems, so unconditionally installing nvidia-open-dkms made
# pacman prompt [y/N], --noconfirm answered No, and the installer died
# at the Nvidia step (Devi desktop, RTX 4080 Super + AMD 610M iGPU).
# Keep whichever driver variant is already installed; on a clean system
# install prebuilt nvidia-open (stock Arch kernel, no dkms build, no
# headers needed), never dkms. Companion utils are safe under any variant.
install_nvidia_open() {
  if pacman -Q nvidia-open-dkms >/dev/null 2>&1; then
    info "nvidia-open-dkms already installed, keeping it (not installing conflicting nvidia-open)."
    install_kernel_headers
    run_pacman "Nvidia drivers (nvidia-open-dkms)" -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  elif pacman -Q nvidia-open >/dev/null 2>&1; then
    info "nvidia-open already installed (EndeavourOS base), keeping it (not installing conflicting nvidia-open-dkms)."
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  elif pacman -Q nvidia >/dev/null 2>&1 || pacman -Q nvidia-dkms >/dev/null 2>&1; then
    info "Closed Nvidia driver already installed, keeping it (not installing conflicting nvidia-open)."
    run_pacman "Nvidia drivers (closed, already installed)" -S --needed --noconfirm nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  else
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  fi
}

if [ "$HAS_AMD" -eq 1 ]; then
  step "AMD GPU detected. Installing Mesa and Vulkan for the AMD GPU."
  info "Hybrid AMD iGPU + Nvidia dGPU: Mesa/Vulkan for AMD here, Nvidia driver below, both install."
  run_pacman "AMD GPU drivers" -S --needed --noconfirm mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon amd-ucode linux-firmware
fi

if [ "$HAS_NVIDIA" -eq 1 ]; then
  if echo "$GPU_INFO" | grep -qiE 'RTX|GTX 16|GTX 20|GTX 30|GTX 40'; then
    step "Nvidia Turing or newer detected (RTX 4080 Super path). Installing nvidia-open."
    install_nvidia_open
  elif echo "$GPU_INFO" | grep -qiE 'GTX 10'; then
    step "Nvidia Pascal detected (GTX 1080 Ti, 10xx path). Installing nvidia-580xx from AUR."
    warn "Pascal is legacy. nvidia-580xx is the legacy branch, end of support is coming. Do NOT install nvidia-open on this card."
    # Same conflict as Turing: if the base shipped nvidia-open(*), the
    # 580xx install would die on the conflict prompt. Remove the
    # conflicting driver first, non-interactively, one package at a time.
    for _conf in nvidia-open nvidia-open-dkms nvidia nvidia-dkms; do
      if pacman -Q "$_conf" >/dev/null 2>&1; then
        info "Removing conflicting $_conf before installing nvidia-580xx (Pascal cannot use it)."
        sudo pacman -R --noconfirm "$_conf" >/dev/null 2>&1 || warn "Could not remove $_conf, nvidia-580xx install may conflict."
      fi
    done
    install_kernel_headers
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils
  else
    warn "Nvidia GPU found but model not matched as Turing+ or Pascal 10xx. Check lspci output above."
    warn "Defaulting to nvidia-open. If this is a Pascal 10xx card, remove nvidia-open and install nvidia-580xx-dkms and nvidia-580xx-utils from AUR instead."
    install_nvidia_open
  fi
fi

if [ "$HAS_AMD" -eq 0 ] && [ "$HAS_NVIDIA" -eq 0 ] && [ -n "$GPU_INFO" ]; then
  step "No AMD or Nvidia GPU matched. Installing generic Intel Mesa stack."
  run_pacman "Intel GPU drivers" -S --needed --noconfirm mesa vulkan-intel lib32-mesa lib32-vulkan-intel
fi

# --- Hyprland version trap ---

step "Checking Hyprland version (0.56 uses Lua config, 0.57 is Lua only, no .conf)"
if command -v hyprland >/dev/null 2>&1; then
  HYPR_VERSION="$(hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
  echo "Hyprland version: ${HYPR_VERSION:-unknown}"
  if [ "$HYPR_VERSION" = "0.57" ]; then
    echo "Hyprland 0.57: Lua only. Do NOT use a .conf file."
    if [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
      warn "Hyprland 0.57 detected and $HOME/.config/hypr/hyprland.conf exists. It will be moved to .hexciri.bak after the fork is placed."
    fi
  elif [ "$HYPR_VERSION" = "0.56" ]; then
    echo "Hyprland 0.56: Lua config works, .conf still works. This installer ships Lua only, no .conf."
  else
    warn "Hyprland version is ${HYPR_VERSION:-unknown}, not 0.56 or 0.57. Check whether Lua is the only config format for this version before writing a config."
  fi
else
  warn "hyprland binary not found after install. Check the pacman install output above."
fi
echo "This step ships no Hyprland config file yet. The forked Lua config is placed in step 4 below."

# --- SDDM and uwsm session ---

step "Setting up SDDM and the Hexiri uwsm session"

if [ ! -f /usr/share/wayland-sessions/hyprland.desktop ]; then
  warn "hyprland.desktop not found in /usr/share/wayland-sessions/. The Hexiri session below depends on it."
fi

TMP_DESKTOP="$(mktemp)"
cat > "$TMP_DESKTOP" <<'EOF'
[Desktop Entry]
Name=Hexiri
Comment=Hexiri Hyprland session via uwsm
Exec=uwsm start -e -D Hyprland hyprland.desktop
TryExec=uwsm
Type=Application
DesktopNames=Hyprland
Keywords=Hyprland;Hexiri;Wayland;
EOF
sudo install -Dm644 "$TMP_DESKTOP" /usr/share/wayland-sessions/hexciri.desktop
rm -f "$TMP_DESKTOP"
echo "Installed /usr/share/wayland-sessions/hexciri.desktop"
if [ "${IS_RERUN:-0}" != "1" ]; then cat /usr/share/wayland-sessions/hexciri.desktop; fi

step "Enabling SDDM"
sudo systemctl enable sddm

# --- Verify EndeavourOS shipped services ---

step "Verifying EndeavourOS services are enabled (these ship with EndeavourOS, do not reinstall)"
echo "EndeavourOS already ships: pacman, yay, PipeWire, NetworkManager, bluez, power-profiles-daemon, upower, fonts, FirewallD, dracut, systemd-boot."
for svc in NetworkManager bluetooth power-profiles-daemon firewalld sddm; do
  if systemctl is-enabled --quiet "$svc"; then
    echo "enabled: $svc"
  else
    echo "not enabled, enabling now: $svc"
    sudo systemctl enable "$svc"
  fi
done

step "Quick service state check"
if systemctl is-enabled --quiet NetworkManager bluetooth power-profiles-daemon firewalld sddm 2>/dev/null; then
  info "Services enabled: NetworkManager, bluetooth, power-profiles-daemon, firewalld, sddm"
else
  warn "One or more services above did not report enabled. Check systemctl status for that service."
fi

fi # end system-provisioning guard (minimal re-apply: skipped in both re-apply modes)
# Minimal re-apply: the fork + placement block runs in full mode and
# in --re-apply (fork patch) mode. --re-apply-provision skips it: the
# fork did not change, the placed tree is already correct.
if [ "${REAPPLY_PROV:-0}" != "1" ]; then
# --- Fork cache check (2026-11-24, split 2026-11-24: upstream vs patches) ---
# BEGIN FORK CACHE CHECK
UP_FP="$(upstream_fingerprint)"
PATCH_FP="$(patch_fingerprint)"
FORK_FP="$(fork_fingerprint)"
SKIP_FORK=0
SKIP_UPSTREAM=0
SKIP_PATCHES=0
if [ "${REFORK:-0}" = "1" ]; then
  rm -rf "$FORK_CACHE_DIR"
  info "Re-fork requested (--refork), fork cache cleared"
fi
# Upstream cache: the pre-patch fork (download + copy + rename + rewrite).
if [ -f "$FORK_CACHE_DIR/upstream-fingerprint" ] && [ -d "$FORK_CACHE_DIR/upstream-out/bin" ] && [ "$(cat "$FORK_CACHE_DIR/upstream-fingerprint" 2>/dev/null)" = "$UP_FP" ]; then
  SKIP_UPSTREAM=1
  rm -rf "$FORK_OUT"
  cp -a "$FORK_CACHE_DIR/upstream-out" "$FORK_OUT"
  info "Fork cache hit (upstream): Omarchy $PINNED_SHA unchanged, reusing cached upstream fork (no download, no re-copy, no re-rename)"
  # Emergency-mode guard, 2026-11-24: a restored cache was trusted
  # blindly, and the 0376cee update shipped an installed tree missing
  # default/hypr/bootstrap.lua (Hyprland dofiles it first; missing =
  # emergency mode, no binds) while the installer reported success.
  # If the cached upstream tree lacks it, the cache is stale or
  # incomplete: drop it and full re-fork below instead of shipping it.
  if ! bootstrap_ok "$FORK_OUT/default/hypr/bootstrap.lua" || ! hyprlua_ok "$FORK_OUT/default/hypr/hexciri.lua"; then
    warn "Fork cache invalid: cached upstream tree is missing or corrupt (empty/truncated) default/hypr/bootstrap.lua or hexciri.lua, dropping the cache and full re-forking"
    rm -rf "$FORK_CACHE_DIR"
    SKIP_UPSTREAM=0
  fi
else
  info "Fork cache miss (upstream): forking Omarchy $PINNED_SHA (full fork; per-file detail: $FORK_LOG)"
fi
# Patch cache: the fully patched fork. Only usable when the upstream
# tree it was patched from is the same one (SKIP_UPSTREAM=1, or the
# upstream fork just ran fresh in this run -- in that case the patched
# cache is stale by definition and patches must run).
if [ "${SKIP_UPSTREAM:-0}" = "1" ] && [ -f "$FORK_CACHE_DIR/patch-fingerprint" ] && [ -f "$FORK_CACHE_DIR/fork-out/bin/hexciri" ] && [ "$(cat "$FORK_CACHE_DIR/patch-fingerprint" 2>/dev/null)" = "$PATCH_FP" ]; then
  SKIP_PATCHES=1
  SKIP_FORK=1
  rm -rf "$FORK_OUT"
  cp -a "$FORK_CACHE_DIR/fork-out" "$FORK_OUT"
  _fc_files="$(find "$FORK_OUT" -type f 2>/dev/null | wc -l | tr -d ' ')"
  _fc_themes="$(find "$FORK_OUT/themes" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
  _fc_bins="$(find "$FORK_OUT/bin" -type f 2>/dev/null | wc -l | tr -d ' ')"
  info "Fork cache hit: Omarchy $PINNED_SHA, fork unchanged, reusing cached fork ($_fc_files files, $_fc_themes themes, $_fc_bins bin scripts, no download, no re-fork)"
  unset _fc_files _fc_themes _fc_bins
  # Same emergency-mode guard for the patched cache: if it lacks
  # bootstrap.lua (or hexciri.lua) it is stale -- drop back to the
  # cached upstream tree and re-apply patches instead of shipping it.
  if ! bootstrap_ok "$FORK_OUT/default/hypr/bootstrap.lua" || ! hyprlua_ok "$FORK_OUT/default/hypr/hexciri.lua"; then
    warn "Fork cache invalid: cached patched tree is missing or corrupt (empty/truncated) default/hypr/bootstrap.lua or hexciri.lua, re-applying patches to the cached upstream tree"
    rm -rf "$FORK_CACHE_DIR/fork-out" "$FORK_CACHE_DIR/patch-fingerprint" "$FORK_CACHE_DIR/fork-fingerprint"
    SKIP_PATCHES=0
    SKIP_FORK=0
    rm -rf "$FORK_OUT"
    cp -a "$FORK_CACHE_DIR/upstream-out" "$FORK_OUT"
    # The fallback tree is only as good as the upstream cache it came
    # from: if that is corrupt too, patches would run on a broken tree
    # and the fork-stage guard below is skipped (SKIP_UPSTREAM is still
    # 1), so check it here and full re-fork instead of shipping it.
    if ! bootstrap_ok "$FORK_OUT/default/hypr/bootstrap.lua" || ! hyprlua_ok "$FORK_OUT/default/hypr/hexciri.lua"; then
      warn "Fork cache invalid: cached upstream tree is also missing or corrupt bootstrap.lua or hexciri.lua, dropping the whole cache and full re-forking"
      rm -rf "$FORK_CACHE_DIR"
      SKIP_UPSTREAM=0
    fi
  fi
elif [ "${SKIP_UPSTREAM:-0}" = "1" ]; then
  info "Fork cache hit (upstream only): patches changed, re-applying fork patches to the cached upstream tree (no download)"
fi
# END FORK CACHE CHECK

# --- Download Omarchy at the pinned commit as a tarball, no git, no auth ---

if [ "${SKIP_UPSTREAM:-0}" = "0" ]; then
step "Downloading Omarchy, branch $PINNED_BRANCH, pinned commit $PINNED_SHA ($PINNED_DATE)"
step "No git clone, no username or password prompt: public codeload tarball via curl"
for cmd in curl python3 tar grep find cp mkdir rm; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done
OMARCHY_TARBALL="$TMP_WORK/omarchy.tar.gz"
info "Omarchy tarball is about 94 MB, this can take a minute on a slow connection (silent download, no progress bar)"
curl -fsSL --max-time 300 -o "$OMARCHY_TARBALL" "$OMARCHY_TARBALL_URL" || die "curl download of omacom/omarchy tarball failed. Fix networking, then rerun."
[ -s "$OMARCHY_TARBALL" ] || die "Downloaded Omarchy tarball is empty: $OMARCHY_TARBALL"
OMARCHY_SIZE="$(wc -c < "$OMARCHY_TARBALL" | tr -d ' ')"
info "Downloaded: $OMARCHY_SIZE bytes (~$((OMARCHY_SIZE / 1024 / 1024)) MB): $OMARCHY_TARBALL"
# Validate it is really a gzip tarball, not an HTML error page.
# Write the listing to a file first. The old code did
#   TOP_DIR="$(tar -tzf "$OMARCHY_TARBALL" | head -1 | cut -d/ -f1)"
# which is the same silent-exit-141 bug the bootstrap had: head exits
# after the first line, tar gets SIGPIPE under pipefail, set -e exits
# with no error. A file listing cannot do that.
tar -tzf "$OMARCHY_TARBALL" > "$TMP_WORK/omarchy-list.txt" || die "Downloaded file is not a valid gzip tarball: $OMARCHY_TARBALL. Check the URL and networking, then rerun."
info "Validation passed: valid gzip tarball"
# Codeload names the top dir omarchy-<full commit SHA>. That is the SHA check:
# a tarball for any other commit has a different top dir name and fails here.
TOP_DIR="$(head -1 "$TMP_WORK/omarchy-list.txt" | cut -d/ -f1)"
[ -n "$TOP_DIR" ] || die "Could not read a top dir from the Omarchy tarball listing: $TMP_WORK/omarchy-list.txt"
if [ "$TOP_DIR" != "omarchy-$PINNED_SHA" ]; then
  die "commit mismatch: tarball top dir is '$TOP_DIR', expected 'omarchy-$PINNED_SHA'. Refusing to continue."
fi
info "Top dir: $TOP_DIR"
info "Extracting Omarchy tarball (this can take a minute, no output while tar runs)..."
tar -xzf "$OMARCHY_TARBALL" -C "$TMP_WORK" || die "Failed to extract Omarchy tarball."
info "Extraction done."
OMARCHY_SRC="$TMP_WORK/$TOP_DIR"
[ -d "$OMARCHY_SRC" ] || die "Extracted Omarchy tree not found: $OMARCHY_SRC"
# Marker files from the pinned tree, a wrong or truncated tarball fails here.
for marker in shell/shell.qml default/hypr config/omarchy/shell.json themes; do
  [ -e "$OMARCHY_SRC/$marker" ] || die "Extracted Omarchy tree is missing expected path: $marker"
done
info "Commit verified by tarball top dir: $TOP_DIR"
fi # end SKIP_FORK download guard

# --- Fork and rename, inline (was fork-shell.sh) ---
# Phase 1 only: extract the listed subsets verbatim, then rename. No Phase 2 Hexciri edits.
# Stock Lua only. Lua double backslashes are preserved byte-safe:
# a regex dot is \\. in Lua, and this script never collapses \\ to \.
# It uses Python byte replacement, not sed, for content rewrites.
#
# Fork cache (2026-11-24, split): when SKIP_UPSTREAM=1 the upstream
# block below is skipped and FORK_OUT is the cached upstream tree
# restored above; when SKIP_PATCHES=1 the patch block below is skipped
# and FORK_OUT is the cached patched tree. Fresh installs and fork
# changes run them in full. Per-file noise in here goes to the fork
# detail log, screen gets one summary line per stage.
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
 }
# _patch_log: fork-patch python blocks print "already present, skipping"
# / "menu removed: ..." on every patch re-apply (2026-11-24, Devi: a
# plain update printed ~500 lines of installer re-run spam, and a patch
# re-apply re-runs them on the pristine upstream tree, so the menu audit
# prints its removals every time). Those go to the fork log; only
# changed / failed steps print. stderr stays on the terminal, so a
# patch failure still shows. Verbose mode prints them as before.
_patch_log="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then _patch_log="/dev/stdout"; fi
if [ "${SKIP_UPSTREAM:-0}" = "0" ]; then

copy_subset() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    fork_detail "Copied: $label ($src -> $dest)"
  else
    die "required subset missing in source: $label ($src)"
  fi
}

copy_optional_file() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    fork_detail "Copied: $label ($src -> $dest)"
    return 0
  fi
  return 1
}

copy_optional_path() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    fork_detail "Copied: $label ($src -> $dest)"
    return 0
  fi
  return 1
}

is_allowed_bin() {
  local name="$1"
  case "$name" in
    launch-shell | omarchy | done | toggle | dictation | default-dictation | dictation-* | restart-* | theme-set | theme-set-templates | plugin-add | plugin-catalog | plugin-clone | plugin-disable | plugin-enable | plugin-list | plugin-remove | plugin-update | plugin-validate | bar | bar-text-color | shell | shell-config | migrate | migrate-notify | hook | hook-install | \
      refresh-hyprland | hyprland-reload-guard | notification-send | menu | menu-clipboard | menu-emoji | menu-emoji-insert | menu-file | menu-herdr-keybindings | menu-images | menu-input | menu-keybindings | menu-plugin | menu-region-formats | menu-select | menu-share | menu-timezone | menu-tmux-keybindings | \
      provision-user | provision-first-run | provision-hardware | provision-owner | reinstall-configs | reinstall | reinstall-pkgs | version | version-branch | version-channel | version-pkgs | update | update-* | mise-install | mise-default-tools | launch-* | \
      cmd-* | default-terminal | action | i18n | notification-wait | software-rendering | toggle-enabled | hyprland-toggle-enabled | hyprland-software-rendering | hw-software-rendering | powerprofiles-init | powerprofiles-set | powerprofiles-floor | powerprofiles-list | hyprland-monitor-watch | hyprland-monitor-clamshell | hyprland-monitor-modeless | hyprland-monitor-external-active | hyprland-monitor-identity | hyprland-monitor-internal | hyprland-monitor-internal-mirror | hyprland-monitor-laptop | hyprland-workspace-layout-current | hyprland-workspace-layout-toggle | hyprland-workspace-layout-default | hw-laptop | hw-clamshell | hw-external-monitors | system-lid-inhibit | restart-hyprctl | \
      capture-* | system-* | system | hyprland-* | notification-* | toggle-* | icons-* | hw-* | region | region-* | hibernation-* | sleep-* | audio-* | battery-* | bluetooth-* | brightness-* | clipboard-* | branding-* | default-* | theme-* | agent | agent-* | pkg-present | pkg-add | pkg-missing | pkg-install | pkg-aur-install | pkg-aur-accessible | pkg-remove | pkg-drop | sudo-keepalive | cmd-present | reminder | transcode | transcode-* | tray-* | weather-* | tui-* | webapp-* | osd | \
      dock | dns | state | show-* | setup-* | device-* | apply-lock | sudo-passwordless | security-functions | display-* | monitor-* | network-* | font-* | disk-speedtest | file-select | input-method | git-url-check | kernel | language | locale-session | locale-generate | refresh-shell | refresh-tmux | refresh-hyprsunset | refresh-applications | refresh-config | install-font | install-app | install-and-launch | install-editor-zed | install-gaming-steam | install-gaming-heroic | install-gaming-lutris | install-gaming-retroarch | install-gaming-battlenet | install-gaming-geforce-now | install-gaming-gpu-lib32 | remove-browser | remove-security-fingerprint | remove-gaming-steam | remove-gaming-retroarch | remove-gaming-minecraft | remove-gaming-geforce-now | install-browser | install-terminal | install-editor-vscode | install-editor-helix | install-dev-env | remove-dev-env | install-service-1password | install-service-dropbox | install-service-microsoft | install-service-nordvpn | install-service-once | install-service-signal | install-service-tailscale | remove-service-1password | remove-service-dropbox | remove-service-microsoft | remove-service-ssh-agent | remove-service-tailscale | remove-security-fido2 | remove-security-sshd | install-dictation-hex | install-dictation-superwhisper | install-dictation-voxtype | remove-dictation-hex | remove-dictation-superwhisper | remove-dictation-voxtype | install-gaming-xbox-cloud | install-gaming-xbox-controllers | remove-gaming-battlenet | remove-gaming-heroic | remove-gaming-lutris | remove-gaming-moonlight | remove-gaming-xbox-cloud | remove-gaming-xbox-controllers | games-retro-install | games-retro-cores | games-vibes-install | games-vibes-remove | games-vibes-launch | games-vibes-copy | install-chromium-copy-url | install-chromium-ytdlp | install-video-decode | install-camera | pkg-aur-add | chromium-add-feature | chromium-copy-url-host | chromium-ytdlp-host | tailscale-receive | tailscale-send | install-ai-chatgpt | install-ai-claude | install-ai-hermes | install-ai-openclaw | install-ai-t3-code | remove-ai-amp | remove-ai-antigravity | remove-ai-chatgpt | remove-ai-claude | remove-ai-grok-bot | remove-ai-hermes | remove-ai-lm-studio | remove-ai-ollama | remove-ai-openclaw | remove-ai-perplexity | remove-ai-t3-code | install-hermes-cli | install-openclaw-cli | install-t3code-app | openclaw-onboard | launch-openclaw)
      # Dinner audit 2026-11-23: the families above were missing, so binds and
      # menu rows that call them failed with Command not found, exactly like
      # monitor-watch did. capture-* (screenshot/screenrecording/text/region),
      # system-* (lock/logout/reboot/shutdown, lid-close), hyprland-* (window
      # gaps/transparency/corners, monitor toggles), notification-* (send is
      # already listed, plus time/battery/weather), toggle-* (bar, animations,
      # transparency), icons-*, hw-*, region-*, hibernation-*, sleep-*,
      # audio-*, battery-*, bluetooth-*, brightness-*, clipboard-*, branding-*,
      # default-* (editor/browser/terminal), theme-*, agent / agent-* (shell
      # AI-agent helpers, not apps), pkg-present / cmd-present (menu when/
      # disabled checks), reminder, transcode, osd. 2026-11-23 helpers.lua:110
      # fix: transcode-* (branding-about/screensaver call transcode-ascii),
      # tray-* (Tray.qml right-click calls tray-context-menu), weather-*
      # (weather panel calls weather-status/location/icon), tui-* and
      # webapp-* (menu Install/Remove rows call tui/webapp-install/remove,
      # which only create local .desktop launchers, no Omarchy repo).
      # Menu audit 2026-11-23: bare names need listing too, a "system-*"
      # pattern does NOT match bare "system" (and the same for dock, dns,
      # state, region). Those four were never copied, which is why System >
      # Logout/Reboot/Shutdown, Appearance > Dock, Setup > Network > DNS
      # and omarchy-system's own omarchy-state call all failed at once.
      # Added families, each proved by a caller in the fork: setup-* (Setup
      # wizards: git/hostname/keyboard/input/fingerprint/fido2/sshd/
      # ssh-agent/passwordless-sudo), device-* (Trigger > Hardware touchpad
      # / touchscreen / hybrid GPU), pkg-add + pkg-missing (trivial pacman
      # wrappers the setup wizards call; NOT the install-* app machinery),
      # apply-lock (writes /etc/pam.d/hexciri-lock-password, System > Lock
      # needs it), sudo-passwordless + security-functions (its source),
      # display-* + monitor-* (display panel: scale comes from
      # monitor-state, text size from display-text-size), network-*
      # (network panel: status/band/captive-portal/wifi-connected),
      # font-* (fonts provider + display-text-size), disk-speedtest
      # (disk-speedtest panel), file-select (branding pickers, menu-share),
      # input-method (Super+I binds), git-url-check (plugin-add),
      # kernel (kernels provider, Update > Kernel), language +
      # locale-session + locale-generate (languages provider, Setup >
      # Region > Language), refresh-shell/tmux/hyprsunset/applications/
      # config (Update > Config rows; refresh-chromium/sddm/pacman/
      # plymouth/limine/herdr stay out, they call install-*/plymouth).
      # toggle (bare): hexciri-toggle-bar/crash-capture/screensaver/suspend/
      # theme-sync all call it, it is a trivial flag-file script, and the
      # sim proved it was missing (Hide/Show Bar menu rows failed on it).
      # dictation + default-dictation + dictation-*: Setup > Defaults >
      # Dictation rows and the Alt+Space bind. No backend is installed yet
      # (install-dictation-* stays out), so dictation fails gracefully
      # ("No dictation backend configured") until one is picked.
      # Deliberately still NOT included: install-ai-herdr (Herdr stays
      # removed, standing decision: its installer curls
      # releases.herdr.dev and its theme/autostart bits are Omarchy-side),
      # install-windows-vm, install-preinstalls,
      # install-docker-dbs (Docker out), channel-*, mirror-*, keyring-*,
      # upgrade-* (Omarchy repo machinery, out of the shell-only Phase 1
      # scope), and windows-vm (Docker/KVM VM manager, needs Docker).
      # 2026-11-24 full Install/Remove restore (Devi: full menu back):
      # install-service-*, install-terminal-*, install-browser (+ its
      # chromium tree: install-chromium-*, install-video-decode,
      # install-camera, config/chromium-flags.conf, default/chromium/),
      # install-dev-env / remove-dev-env (mise, back in Phase 2) and
      # install/remove-dictation-* are listed now, with the bins the
      # menu patch step below keeps rows for. The menu patch still drops
      # every other install/remove row whose backing script is not in
      # the fork, so no dead row can be clicked.
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

copy_subsets() {
  step "Copying only the listed Phase 1 subsets (everything else is skipped by design)"
  info "Skipped: apps/GUI preinstalls, Limine/UKI, snapper/btrfs, Plymouth, LUKS scripts, Docker, Herdr (AI agents are options now, Herdr stays out), omarchy-upgrade-to-quattro, channel/keyring/mirror scripts, pacman guard hook, upstream migrations (migration runner mechanism only, no upstream migrations)"
  rm -rf "$FORK_OUT"
  mkdir -p "$FORK_OUT"

  # Whole Quickshell shell: bar, menu, dock, notifications, osd, lock, polkit, clipboard, background, services, panels
  # Note: there is no shell/plugins/launcher/ at this commit. Launcher code lives in menu/ and dock/.
  copy_subset "$OMARCHY_SRC/shell" "$FORK_OUT/shell" "shell/"

  # All Lua for Hyprland, and user Hyprland templates
  copy_subset "$OMARCHY_SRC/default/hypr" "$FORK_OUT/default/hypr" "default/hypr/"
  copy_subset "$OMARCHY_SRC/config/hypr" "$FORK_OUT/config/hypr" "config/hypr/"

  # Shell layout config: verified location is config/omarchy/shell.json
  if ! copy_optional_file "$OMARCHY_SRC/config/omarchy/shell.json" "$FORK_OUT/config/shell.json" "config/omarchy/shell.json"; then
    if ! copy_optional_file "$OMARCHY_SRC/config/shell.json" "$FORK_OUT/config/shell.json" "config/shell.json"; then
      copy_optional_file "$OMARCHY_SRC/default/shell.json" "$FORK_OUT/config/shell.json" "default/shell.json" || die "required subset missing in source: config/omarchy/shell.json"
    fi
  fi

  # Menu config, renamed to hexciri names
  mkdir -p "$FORK_OUT/default/hexciri"
  if ! copy_optional_file "$OMARCHY_SRC/default/omarchy/omarchy-menu.jsonc" "$FORK_OUT/default/hexciri/hexciri-menu.jsonc" "default/omarchy/omarchy-menu.jsonc"; then
    copy_optional_file "$OMARCHY_SRC/default/hexciri-menu.jsonc" "$FORK_OUT/default/hexciri/hexciri-menu.jsonc" "default/hexciri-menu.jsonc" || warn "omarchy-menu.jsonc not found in source, continuing without it"
  fi
  if ! copy_optional_file "$OMARCHY_SRC/default/omarchy/launcher.hides" "$FORK_OUT/default/hexciri/launcher.hides" "default/omarchy/launcher.hides"; then
    if ! copy_optional_file "$OMARCHY_SRC/default/launcher.hides" "$FORK_OUT/default/hexciri/launcher.hides" "default/launcher.hides"; then
      copy_optional_file "$OMARCHY_SRC/launcher.hides" "$FORK_OUT/default/hexciri/launcher.hides" "launcher.hides" || warn "launcher.hides not found in source, continuing without it"
    fi
  fi
  # Hyprland global shortcuts list: the shell registers one Hyprland global
  # shortcut per line (menu root/apps/theme, panels, audio, brightness, media
  # and notification IPC), and helpers.lua turns { menu = ... } / { panel = ... }
  # binds into hl.dsp.global("omarchy:<kind>.<target>") instead of spawning a
  # process per keypress. This file was NOT copied before, so every menu/panel
  # bind fell back to a command (hexciri-menu toggle root, hexciri-shell ...)
  # run by Hyprland exec, which does not reliably have /usr/share/hexciri/bin
  # on PATH. That is the most likely reason Super+Space and Super+Alt+Space
  # did nothing on the first live boot. Copying it makes those binds go
  # straight to the running shell with no process and no PATH involved.
  # The "omarchy:" global-shortcut prefix itself is deliberately NOT renamed:
  # helpers.lua and the shell QML both use it, so both sides still agree.
  if ! copy_optional_file "$OMARCHY_SRC/default/omarchy/shortcuts" "$FORK_OUT/default/hexciri/shortcuts" "default/omarchy/shortcuts"; then
    copy_optional_file "$OMARCHY_SRC/default/shortcuts" "$FORK_OUT/default/hexciri/shortcuts" "default/shortcuts" || warn "shortcuts not found in source, menu/panel binds fall back to commands (Super+Space may need PATH to work)."
  fi

  # All themes, colors.toml + shell.toml, verbatim except path renames applied later. 23 themes at pinned commit.
  copy_subset "$OMARCHY_SRC/themes" "$FORK_OUT/themes" "themes/"

  # i18n catalogs, required: the shell's I18n service reads
  # default/i18n/<code>/shell.json layered over English. Without this copy
  # every lookup returns the literal key, so the clock panel showed
  # "clock.monthYear" / "clock.weekShortSUN" instead of real dates.
  copy_subset "$OMARCHY_SRC/default/i18n" "$FORK_OUT/default/i18n" "default/i18n/"

  # Theme templates: theme-set-templates renders default/themed/*.tpl into
  # the staged theme (kitty.conf, tmux, obsidian, ghostty, ...). This copy
  # was missing, so theme-set generated NOTHING and no app got themed.
  copy_subset "$OMARCHY_SRC/default/themed" "$FORK_OUT/default/themed" "default/themed/"

  # Icon sets + ASCII logos, 2026-11-23 regression fix: hexciri-icons-list /
  # switcher / set and hexciri-theme-set-icons read $HEXCIRI_PATH/icons/
  # (upstream icons/ ships arcade, original, papercraft); hexciri-show-logo
  # cats $HEXCIRI_PATH/logo.txt and hexciri-branding-about reset copies
  # $HEXCIRI_PATH/icon.txt. None of these were copied before, so
  # Appearance > Icons had no sets to show and About's logo file was never
  # created. icon.txt is abstract block art, no text in it. logo.txt is
  # NOT neutral: upstream logo.txt is the OMARCHY block art, and
  # hexciri-show-logo cats it at the top of every hexciri update, so the
  # first full update showed OMARCHY. It is overwritten with HEXCIRI art
  # just below, Devi's exact art (see logo heredoc).
  copy_subset "$OMARCHY_SRC/icons" "$FORK_OUT/icons" "icons/"
  copy_optional_file "$OMARCHY_SRC/logo.txt" "$FORK_OUT/logo.txt" "logo.txt" || warn "logo.txt not found in source, hexciri-show-logo will fail."
  # 2026-11-24: replace the upstream OMARCHY art with HEXCIRI art in the
  # same block style. 2026-11-24 (2nd): Devi's exact art from
  # workspace/user/files/hexciriv2.md, copied verbatim by the patch
  # script (read from the file, never retyped). 2026-11-24 (3rd): v2 art,
  # more unique, less "omarchy clone". hexciri-branding-
  # screensaver copies this file too, so it gets the Hexciri art as well.
  cat > "$FORK_OUT/logo.txt" <<'HEXCIRI_LOGO_EOF'
 ▄  █ ▄███▄      ▄  ▄█▄    ▄█ █▄▄▄▄ ▄█ 
█   █ █▀   ▀ ▀▄   █ █▀ ▀▄  ██ █  ▄▀ ██ 
██▀▀█ ██▄▄     █ ▀  █   ▀  ██ █▀▀▌  ██ 
█   █ █▄   ▄▀ ▄ █   █▄  ▄▀ ▐█ █  █  ▐█ 
   █  ▀███▀  █   ▀▄ ▀███▀   ▐   █    ▐ 
  ▀           ▀                ▀
HEXCIRI_LOGO_EOF
  info "Wrote Hexciri logo.txt (HEXCIRI block art, replaces upstream OMARCHY art)"
  copy_optional_file "$OMARCHY_SRC/icon.txt" "$FORK_OUT/icon.txt" "icon.txt" || warn "icon.txt not found in source, About branding reset will fail."

  # Kitty config: upstream config/kitty/kitty.conf includes the staged theme
  # kitty.conf. Without this file Kitty never loads the theme colours.
  copy_subset "$OMARCHY_SRC/config/kitty" "$FORK_OUT/config/kitty" "config/kitty/"

  # Tmux config: hexciri-menu-tmux-keybindings (Learn > Tmux) falls back
  # to $HEXCIRI_PATH/config/tmux/tmux.conf when ~/.config/tmux/tmux.conf
  # is absent, and Super+Alt+Return opens tmux in Kitty. This copy was
  # missing, so Learn > Tmux died with "Tmux config not found" even
  # though tmux itself is in APP_PKGS (2026-11-24).
  copy_subset "$OMARCHY_SRC/config/tmux" "$FORK_OUT/config/tmux" "config/tmux/"

  # Terminal preference list: launch-terminal's fast path reads
  # xdg-terminals.list (kitty.desktop after the rename map) instead of
  # calling xdg-terminal-exec. Optional: falls back to xdg-terminal-exec.
  copy_optional_path "$OMARCHY_SRC/default/xdg-terminal-exec" "$FORK_OUT/default/xdg-terminal-exec" "default/xdg-terminal-exec/" || warn "default/xdg-terminal-exec/ not found in source, terminal launches fall back to xdg-terminal-exec."

  # SDDM greeter Hyprland config, renamed omarchy -> hexciri by the rename
  # step below (default/sddm/omarchy -> default/sddm/hexciri). The greeter
  # theme itself is NOT taken from here anymore: the SDDM theming step uses
  # Hexciri's own branding/sddm/ from the repo tree, because Omarchy's theme
  # ships Omarchy logos. This copy is kept for hyprland.lua only.
  # Optional: if upstream moves it, the SDDM theming step later warns and
  # continues with the EndeavourOS default theme instead of dying here.
  if ! copy_optional_path "$OMARCHY_SRC/default/sddm" "$FORK_OUT/default/sddm" "default/sddm/"; then
    warn "default/sddm/ not found in source, SDDM will keep the EndeavourOS default theme."
  fi

  # install/helpers: browser-policy.sh + as-root.sh, sourced by
  # hexciri-theme-set-browser via $HEXCIRI_PATH/install/helpers/. This copy
  # was missing, so every theme switch failed with
  # "hexciri-theme-set-browser failed": the source died before the policy
  # writer ever ran. Placement copies $FORK_OUT/install too (see below).
  copy_optional_path "$OMARCHY_SRC/install/helpers" "$FORK_OUT/install/helpers" "install/helpers/" || warn "install/helpers/ not found in source, theme-set-browser will fail on every theme switch."
  # etc/sudoers.d/omarchy-theme-browser: the passwordless rule for the
  # privileged browser-policy writer. rename_files renames it to
  # hexciri-theme-browser, rewrite_contents fixes its /usr/bin path (see
  # the PACKAGED_PATH rule below). Installed to /etc/sudoers.d by the
  # theme-browser step after placement, validated with visudo -cf.
  mkdir -p "$FORK_OUT/etc/sudoers.d"
  copy_optional_file "$OMARCHY_SRC/etc/sudoers.d/omarchy-theme-browser" "$FORK_OUT/etc/sudoers.d/omarchy-theme-browser" "etc/sudoers.d/omarchy-theme-browser" || warn "etc/sudoers.d/omarchy-theme-browser not found in source, theme-set-browser will fall back to pkexec and fail detached."
  # Browser + terminal desktop entries for the dock pins (see placement):
  # upstream applications/omarchy-browser.desktop + omarchy-terminal.desktop.
  # rename_files turns them into hexciri-*.desktop, rewrite_contents fixes
  # their Exec= lines to hexciri-launch-*. Only these two: the rest of
  # applications/ is Omarchy web apps (ChatGPT, Herdr, ...), out of scope.
  mkdir -p "$FORK_OUT/applications"
  copy_optional_file "$OMARCHY_SRC/applications/omarchy-browser.desktop" "$FORK_OUT/applications/omarchy-browser.desktop" "applications/omarchy-browser.desktop" || warn "applications/omarchy-browser.desktop not found in source, dock Browser pin will not resolve."
  copy_optional_file "$OMARCHY_SRC/applications/omarchy-terminal.desktop" "$FORK_OUT/applications/omarchy-terminal.desktop" "applications/omarchy-terminal.desktop" || warn "applications/omarchy-terminal.desktop not found in source, dock Terminal pin will not resolve."
  # The two systemd files hexciri-apply-lock installs when fingers are
  # enrolled (fprintd resume hook + stop-timeout override). Only these
  # two: default/systemd/ as a whole is device-specific sleep hooks and
  # services, out of scope.
  mkdir -p "$FORK_OUT/default/systemd/system-sleep" "$FORK_OUT/default/systemd/system/fprintd.service.d"
  copy_optional_file "$OMARCHY_SRC/default/systemd/system-sleep/fprintd-resume" "$FORK_OUT/default/systemd/system-sleep/fprintd-resume" "default/systemd/system-sleep/fprintd-resume" || warn "fprintd-resume hook not found in source, fingerprint resume may wedge fprintd after suspend."
  copy_optional_file "$OMARCHY_SRC/default/systemd/system/fprintd.service.d/10-stop-timeout.conf" "$FORK_OUT/default/systemd/system/fprintd.service.d/10-stop-timeout.conf" "default/systemd/system/fprintd.service.d/10-stop-timeout.conf" || warn "fprintd stop-timeout override not found in source."

  # Full Install/Remove restore (2026-11-24, Devi: full menu back):
  # install-browser's tree: config/chromium-flags.conf (copied to
  # ~/.config/<browser>-flags.conf by install-browser; the rename turns
  # its /usr/share/omarchy/default/chromium/extensions/ paths into
  # /usr/share/hexciri/...) + default/chromium/ whole (extensions the
  # flags file loads, native-messaging-hosts templates the chromium
  # copy-url/ytdlp installers fill in, policies browser-policy.sh
  # reads). 96K total. install-terminal's tree: config/alacritty +
  # config/ghostty + config/foot (kitty config already copied above) + the Alacritty
  # desktop entry it installs for alacritty. install-dictation-voxtype's
  # tree: default/voxtype/config.toml. Tailscale: the Taildrop receiver
  # unit install-service-tailscale enables; default/systemd/user/ as a
  # whole stays out, only this unit. default/games/vibes/ is deliberately
  # NOT copied: those are Omarchy-bundled games, and games-vibes-remove's
  # "comes with Omarchy" guard degrades gracefully without it (a game
  # under ~/Games/vibes is always removable then).
  copy_optional_file "$OMARCHY_SRC/config/chromium-flags.conf" "$FORK_OUT/config/chromium-flags.conf" "config/chromium-flags.conf" || warn "config/chromium-flags.conf not found in source, install-browser flags files load no extensions."
  copy_optional_path "$OMARCHY_SRC/default/chromium" "$FORK_OUT/default/chromium" "default/chromium/" || warn "default/chromium/ not found in source, install-browser extension flags point at nothing."
  copy_subset "$OMARCHY_SRC/config/alacritty" "$FORK_OUT/config/alacritty" "config/alacritty/"
  copy_subset "$OMARCHY_SRC/config/ghostty" "$FORK_OUT/config/ghostty" "config/ghostty/"
  copy_optional_file "$OMARCHY_SRC/default/alacritty/Alacritty.desktop" "$FORK_OUT/default/alacritty/Alacritty.desktop" "default/alacritty/Alacritty.desktop" || warn "default/alacritty/Alacritty.desktop not found in source, install-terminal alacritty installs without its desktop entry."
  # AI/Foot correction (2026-11-24, Devi: Foot is an option, Kitty stays
  # default): install-terminal foot copies config/foot when ~/.config/foot
  # is missing and installs applications/foot.desktop, exactly like
  # alacritty above. Upstream has no remove.terminal.* subtree, so Foot
  # removes via Remove > Package (pkg-remove, already restored).
  copy_subset "$OMARCHY_SRC/config/foot" "$FORK_OUT/config/foot" "config/foot/"
  copy_optional_file "$OMARCHY_SRC/applications/foot.desktop" "$FORK_OUT/applications/foot.desktop" "applications/foot.desktop" || warn "applications/foot.desktop not found in source, install-terminal foot installs without its desktop entry."
  copy_optional_path "$OMARCHY_SRC/default/voxtype" "$FORK_OUT/default/voxtype" "default/voxtype/" || warn "default/voxtype/ not found in source, install-dictation-voxtype has no config to install."
  mkdir -p "$FORK_OUT/default/systemd/user"
  copy_optional_file "$OMARCHY_SRC/default/systemd/user/omarchy-tailscale-receive.service" "$FORK_OUT/default/systemd/user/hexciri-tailscale-receive.service" "default/systemd/user/omarchy-tailscale-receive.service" || warn "default/systemd/user/omarchy-tailscale-receive.service not found in source, install-service-tailscale enables a unit that is never installed."

  # Bash env bootstrap and envs, renamed by the rename step below
  if ! copy_optional_path "$OMARCHY_SRC/default/bash/env-bootstrap" "$FORK_OUT/default/bash/env-bootstrap" "default/bash/env-bootstrap"; then
    warn "default/bash/env-bootstrap not found in source, continuing without it"
  fi
  if ! copy_optional_path "$OMARCHY_SRC/default/bash/envs" "$FORK_OUT/default/bash/envs" "default/bash/envs"; then
    warn "default/bash/envs not found in source, continuing without it"
  fi

  # Only the bin/ scripts the shell actually calls
  info "Copying allowed bin/ scripts only"
  mkdir -p "$FORK_OUT/bin"
  local copied_bin=0
  local skipped_bin=0
  local src_file base stripped dest_name
  for src_file in "$OMARCHY_SRC"/bin/*; do
    [ -e "$src_file" ] || continue
    [ -f "$src_file" ] || continue
    base="$(basename "$src_file")"
    stripped="${base#omarchy-}"
    stripped="${stripped#omarchy_}"
    if is_allowed_bin "$stripped"; then
      # Main dispatcher: bin/omarchy has no suffix, so the generic
      # hexciri-$stripped form would copy it to bin/hexciri-omarchy
      # (then rename_files would turn it into bin/hexciri-hexciri),
      # and bin/hexciri would not exist at all: verification dies
      # "missing bin: hexciri" and `hexciri plugin list` is not found.
      if [ "$base" = "omarchy" ]; then
        dest_name="hexciri"
      else
        dest_name="hexciri-$stripped"
      fi
      cp -a "$src_file" "$FORK_OUT/bin/$dest_name"
      copied_bin=$((copied_bin + 1))
      fork_detail "Copied bin: $base -> bin/$dest_name"
    else
      skipped_bin=$((skipped_bin + 1))
      fork_detail "Skipped bin (not called by shell): $base"
    fi
  done
  info "Bin copy done: $copied_bin copied, $skipped_bin skipped"
  if [ "$copied_bin" -eq 0 ]; then
    die "no allowed bin/ scripts found in source bin/, refusing to continue with an empty bin/"
  fi
  chmod +x "$FORK_OUT"/bin/* 2>/dev/null || true

  for banned in apps limine snapper plymouth docker; do
    if [ -e "$FORK_OUT/$banned" ]; then
      die "banned subset leaked into output: $FORK_OUT/$banned"
    fi
  done
  info "Subset copy complete"
}

rename_files() {
  step "Renaming files and directories: omarchy -> hexciri"
  python3 - "$FORK_OUT" >"${TMP_WORK:-/tmp}/rename.log" 2>&1 <<'PY'
import os
import sys

root = sys.argv[1]
renamed = 0
for dirpath, dirnames, filenames in os.walk(root, topdown=False):
    for name in filenames + dirnames:
        if "omarchy" in name.lower():
            old = os.path.join(dirpath, name)
            new_name = name.replace("omarchy", "hexciri").replace("Omarchy", "Hexciri").replace("OMARCHY", "HEXCIRI")
            new = os.path.join(dirpath, new_name)
            if old != new:
                os.rename(old, new)
                renamed += 1
                print("Renamed: %s -> %s" % (old, new))
print("Files and dirs renamed: %d" % renamed)
PY
  cat "${TMP_WORK:-/tmp}/rename.log" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  info "$(grep '^Files and dirs renamed:' "${TMP_WORK:-/tmp}/rename.log" | tail -1)"
  info "File and directory rename complete"
}

rewrite_contents() {
  step "Rewriting contents with rename map (Python byte replacement, Lua safe)"
  info "Lua safety: replacements are exact byte matches only, so \\\\ in Lua stays \\\\ and is never collapsed to \\"
  python3 - "$FORK_OUT" >"${TMP_WORK:-/tmp}/rewrite.log" 2>&1 <<'PY'
import os
import sys

root = sys.argv[1]

replacements = [
    (b"/usr/share/omarchy", b"/usr/share/hexciri"),
    (b"$HOME/.config/omarchy", b"$HOME/.config/hexciri"),
    (b"${HOME}/.config/omarchy", b"${HOME}/.config/hexciri"),
    (b"~/.config/omarchy", b"~/.config/hexciri"),
    (b"~/.local/state/omarchy", b"~/.local/state/hexciri"),
    (b"~/.local/share/omarchy", b"~/.local/share/hexciri"),
    (b".config/omarchy", b".config/hexciri"),
    (b".local/state/omarchy", b".local/state/hexciri"),
    (b".local/share/omarchy", b".local/share/hexciri"),
    (b"omarchy-shell", b"hexciri-shell"),
    (b"omarchy-theme-set", b"hexciri-theme-set"),
    (b"omarchy-launch-", b"hexciri-launch-"),
    # Lua table key value.omarchy in helpers.lua command_from(): the check
    # `if value.omarchy then` is followed by a space, so the "omarchy "
    # rule below renames it to value.hexciri, but the concatenation
    # `"omarchy-launch-" .. value.omarchy` is at end-of-line and matches
    # NO rule below, so it stayed value.omarchy (nil, bindings now use
    # the hexciri key) and Hyprland died at helpers.lua:110 with
    # "attempt to concatenate a nil value (field 'omarchy')", breaking
    # every { omarchy = ... } bind in applications.lua (browser, files,
    # editor, Spotify, tmux). Rename the field explicitly, before the
    # "omarchy " rule can split the two sides. paths.omarchy_path is
    # deliberately NOT touched by this rule (different field name).
    (b"value.omarchy", b"value.hexciri"),
    # Generic hyphen rule: autostart.lua calls omarchy-hyprland-monitor-watch,
    # omarchy-powerprofiles-init, omarchy-hyprland-software-rendering and
    # omarchy-provision-first-run, and none of those matched any rule above
    # (they are not omarchy-shell/-menu/-launch-/-theme-set), so they survived
    # the rename while bin/ renamed them to hexciri-*, and uwsm-app reported
    # "Command not found" at login. Safe where a bare omarchy catch-all is
    # not: Lua identifiers cannot contain hyphens, so _G.omarchy_default_bindings
    # and table keys like value.omarchy are untouched by this rule.
    (b"omarchy-", b"hexciri-"),
    # Fixed paths the generic hyphen rule gets wrong: these two start life
    # as /usr/bin/omarchy-*, which the rule above turns into
    # /usr/bin/hexciri-*, but Hexciri bins live in /usr/share/hexciri/bin,
    # never /usr/bin. Both must be fixed AFTER the generic rule runs.
    # theme-set-browser-policy: PACKAGED_PATH is the path the sudoers rule
    # names; a wrong path here means require_root execs a nonexistent file
    # and every theme switch reports hexciri-theme-set-browser failed.
    (b"/usr/bin/hexciri-theme-set-browser-policy", b"/usr/share/hexciri/bin/hexciri-theme-set-browser-policy"),
    # Fingerprint PAM clamshell gate: pam_exec needs a literal absolute
    # path, and the gate binary is hexciri-hw-laptop-closed in the fork bin.
    (b"/usr/bin/hexciri-hw-laptop-closed", b"/usr/share/hexciri/bin/hexciri-hw-laptop-closed"),
    # Fingerprint packages: libfprint-git is an AUR package Omarchy builds
    # with its own patches; the Framework 13 Goodix reader (27c6) is driven
    # by stock libfprint, so install the Arch extra package instead. The
    # script's own guard keeps a TOD-stack libfprint owner untouched.
    (b"packages=(libfprint-git fprintd usbutils)", b"packages=(libfprint fprintd usbutils)"),
    # File manager: Devi's default is Strata (GitHub release, installed by
    # bin/hexciri-strata-install), not Omarchy's Folio. Targeted to the
    # uwsm-app invocation only: window-class rules in windows.lua/system.lua
    # match the class name, and Strata's app ID was not verified, so a global
    # folio -> strata rename would break those rules.
    (b"-- folio", b"-- strata"),
    # Terminal: Devi chose Kitty over Omarchy's default Foot. There used
    # to be a GLOBAL foot.desktop -> kitty.desktop rule here; it rewrote
    # bin/hexciri-default-terminal so its getter returned "foot" for
    # kitty.desktop and its setter wrote kitty.desktop for foot, so the
    # settings menu always showed Foot and picking Kitty did nothing.
    # The rename now happens ONLY for hyprland-xdg-terminals.list, in the
    # per-file step below, and the repair pass after this map restores
    # the two corrupted lines if they survive in any form.
    # Menu trigger icon: shell/plugins/menu/BarWidget.qml draws text "\ue900"
    # in fontFamily "omarchy", the Omarchy logo glyph (U+E900) from Omarchy's
    # private-use icon font default/fonts/omarchy/omarchy.ttf, which v2 never
    # installs, so the trigger rendered blank / a white square. Default it to
    # the Arch logo from Nerd Fonts, nf-linux-archlinux U+F303, in the
    # JetBrains Mono Nerd Font the installer already ships
    # (ttf-jetbrains-mono-nerd). U+E900 is only the Omarchy logo (the other
    # omarchy-font glyphs are U+E901+ brand marks for menu entries), so this
    # replacement touches the logo and nothing else.
    (b"\\ue900", b"\\uf303"),
    # Literal U+E900 glyph: the menu jsonc stores the branding icon as an
    # actual UTF-8 U+E900 character, not the "\ue900" escape the QML uses,
    # so the escape rule above never matched it and the Branding row kept a
    # blank icon. Replace the literal bytes (EE A4 80) with the literal
    # Arch logo bytes (EF 8C 83, U+F303) too.
    (b"\xee\xa4\x80", b"\xef\x8c\x83"),
    (b'fontFamily: "omarchy"', b'fontFamily: "JetBrainsMono Nerd Font"'),
    # iconFont in the menu jsonc: same problem as fontFamily, for menu rows
    # (appearance.branding and the install/remove AI rows). Point it at the
    # Nerd Font too, so the row at least renders in a font that is installed.
    (b'"iconFont":"omarchy"', b'"iconFont":"JetBrainsMono Nerd Font"'),
    (b'"iconFont": "omarchy"', b'"iconFont": "JetBrainsMono Nerd Font"'),
    # Deliberately NOT renamed: the "omarchy:" Hyprland global-shortcut
    # prefix (hl.dsp.global("omarchy:menu.root") in helpers.lua, and the
    # shell QML that registers the same names). Both sides use it, so
    # renaming one side would break every global shortcut. It is an
    # internal namespace, not a file, path, or CLI name. Same for the
    # GlobalShortcut appid in shell.qml, restored to "omarchy" by the
    # repair pass below: Hyprland dispatch is appid:name, so appid
    # "hexciri" + dispatch "omarchy:..." matches nothing.
    (b"omarchy-menu", b"hexciri-menu"),
    (b"omarchy ", b"hexciri "),
    (b"omarchy.lua", b"hexciri.lua"),
    # Root cause of the Hyprland emergency mode on the first live boot:
    # config/hypr/hyprland.lua:17 does require("default.hypr.omarchy"), and
    # that trailing "omarchy" (before a closing quote, paren, or newline)
    # matched NONE of the rules above: "omarchy/" needs a slash, "omarchy."
    # needs a trailing dot, '"omarchy"' needs a quote before it. So the
    # require survived the rename while default/hypr/omarchy.lua had been
    # renamed to hexciri.lua, and Hyprland tripped emergency mode with
    # "module 'default.hypr.omarchy' not found". The "(28 more...)" in that
    # error is Hyprland truncating its package.path search list, not 28
    # more errors. These rules fix module names only, as string literals.
    # Deliberately NOT a blind omarchy -> hexciri catch-all: Lua globals
    # like _G.omarchy_default_bindings and table keys like value.omarchy
    # are user-facing API that the shipped config and helpers both still
    # use under the omarchy name, and renaming only one side of them
    # would break bindings. Module names are the only thing renamed here.
    (b"default.hypr.omarchy", b"default.hypr.hexciri"),
    (b"omarchy.current.theme", b"hexciri.current.theme"),
    (b'omarchy"', b'hexciri"'),
    (b"omarchy'", b"hexciri'"),
    (b"omarchy)", b"hexciri)"),
    (b"Name=Omarchy", b"Name=Hexciri"),
    (b"Author=Omarchy", b"Author=Hexciri"),
    # Capital Omarchy in user-facing strings only (tooltip "Pending Omarchy
    # Updates", manifest name/description, CLI help). Code identifiers use
    # lowercase omarchy and are handled by the rules above; the deliberate
    # non-renames ("omarchy:" prefix, value.omarchy) are lowercase too.
    (b"Omarchy", b"Hexciri"),
    (b"omarchy/", b"hexciri/"),
    (b'"omarchy"', b'"hexciri"'),
    (b"'omarchy'", b"'hexciri'"),
    (b"OMARCHY_PATH", b"HEXCIRI_PATH"),
    (b"OMARCHY_", b"HEXCIRI_"),
    (b"omarchy.bar", b"hexciri.bar"),
    (b"omarchy.menu", b"hexciri.menu"),
    (b"omarchy.workspaces", b"hexciri.workspaces"),
    (b"omarchy.clock", b"hexciri.clock"),
    (b"omarchy.power", b"hexciri.power"),
    (b"omarchy.audio", b"hexciri.audio"),
    (b"omarchy.network", b"hexciri.network"),
    (b"omarchy.bluetooth", b"hexciri.bluetooth"),
    (b"omarchy.weather", b"hexciri.weather"),
    (b"omarchy.notifications", b"hexciri.notifications"),
    (b"omarchy.launcher", b"hexciri.launcher"),
    (b"omarchy.lock", b"hexciri.lock"),
    (b"omarchy.osd", b"hexciri.osd"),
    (b"omarchy.clipboard", b"hexciri.clipboard"),
    (b"omarchy.background", b"hexciri.background"),
    (b"omarchy.", b"hexciri."),
]

skip_exts = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".ttf", ".otf", ".woff", ".woff2", ".mp4", ".zip", ".gz"}
changed_files = 0
total_files = 0
for dirpath, dirnames, filenames in os.walk(root):
    for name in filenames:
        path = os.path.join(dirpath, name)
        ext = os.path.splitext(name)[1].lower()
        if ext in skip_exts:
            continue
        with open(path, "rb") as f:
            data = f.read()
        total_files += 1
        if b"\x00" in data:
            continue
        new_data = data
        for old, new in replacements:
            if old in new_data:
                new_data = new_data.replace(old, new)
        # Terminal list ONLY: Devi chose Kitty over Foot, and this list
        # names foot.desktop; rename it here and nowhere else, so
        # launch-terminal's fast path opens Kitty. See the comment where
        # the global rule used to be: it corrupted default-terminal.
        if name == "hyprland-xdg-terminals.list":
            new_data = new_data.replace(b"foot.desktop", b"kitty.desktop")
        if new_data != data:
            with open(path, "wb") as f:
                f.write(new_data)
            changed_files += 1
# Repair pass, runs after the generic rules above:
# manifest.json files carry an "omarchy" metadata key (capabilities,
# clonedFrom). The generic '"omarchy"' rule renamed that key to "hexciri"
# in the JSON, while the QML reads (manifest.omarchy) were only
# half-renamed (manifest.omarchy -> manifest.hexciri only where a ")"
# followed), so trustedCapabilities() always got null and lock/polkit
# lost their capabilities, and listPlugins lost its metadata. The
# "omarchy" key is an internal API key, like the "omarchy:" global
# shortcut prefix: restore it on both sides, JSON and QML.
repaired = 0
for dirpath, dirnames, filenames in os.walk(root):
    for name in filenames:
        path = os.path.join(dirpath, name)
        if name == "manifest.json":
            with open(path, "rb") as f:
                data = f.read()
            new_data = data.replace(b'"hexciri": {', b'"omarchy": {')
            if new_data != data:
                with open(path, "wb") as f:
                    f.write(new_data)
                repaired += 1
        elif name.endswith((".qml", ".js")):
            with open(path, "rb") as f:
                data = f.read()
            if b"\x00" in data:
                continue
            new_data = data.replace(b"manifest.hexciri", b"manifest.omarchy")
            new_data = new_data.replace(b"candidateManifest.hexciri", b"candidateManifest.omarchy")
            new_data = new_data.replace(b"plugins[id].hexciri", b"plugins[id].omarchy")
            if new_data != data:
                with open(path, "wb") as f:
                    f.write(new_data)
                repaired += 1
print("Manifest repair pass: %d files repaired" % repaired)
# Defence in depth for the helpers.lua:110 split (see value.omarchy rule
# above): if any Lua file still reads value.omarchy, its check was renamed
# to value.hexciri while its concatenation was not, and Hyprland dies
# concatenating nil. paths.omarchy_path is a different field and is not
# touched here.
for dirpath, dirnames, filenames in os.walk(root):
    for name in filenames:
        if not name.endswith(".lua"):
            continue
        path = os.path.join(dirpath, name)
        with open(path, "rb") as f:
            data = f.read()
        if b"\x00" in data:
            continue
        new_data = data.replace(b"value.omarchy", b"value.hexciri")
        if new_data != data:
            with open(path, "wb") as f:
                f.write(new_data)
            repaired += 1
            print("Lua repair pass: %s value.omarchy -> value.hexciri" % path)
# GlobalShortcut appid repair, 2026-11-23: Super+Space (apps), Super+Alt+Space
# (menu) and Super+K (cheatsheet, { menu = "learn.keybindings" }) were ALL dead
# after reboot, while browser / file manager / Spotify binds worked. Those
# three are { menu = ... } / { ipc = ... } binds, which helpers.lua dispatches
# as hl.dsp.global("omarchy:" .. name), and gestures.lua does the same for the
# 3-finger swipe down ("omarchy:menu.root"). The { hexciri = ... } launch binds
# use hl.dsp.exec_cmd("hexciri-launch-...") instead, so they were unaffected.
# Quickshell docs: bind = <mods>, <key>, global, <appid>:<name>. The shell
# registers that appid in shell.qml, GlobalShortcut { appid: "omarchy" }.
# The generic '"omarchy"' rename rule turned it into appid: "hexciri", while
# helpers.lua deliberately keeps "omarchy:" (see the comment above that rule),
# so Hyprland dispatched omarchy:menu.root / omarchy:ipc.hexciri.dock.apps
# to a shortcut registered as hexciri:menu.root / hexciri:ipc.hexciri.dock.apps
# and nothing happened, silently, no error, no popup. Restore appid "omarchy":
# it is an internal Wayland namespace, like the "omarchy:" prefix, not a file,
# path, or CLI name. Proved by simulation against upstream 94a8c3c.
_shell_qml = root + "/shell/shell.qml"
with open(_shell_qml, "rb") as f:
    _sq = f.read()
if b'appid: "hexciri"' in _sq:
    _sq = _sq.replace(b'appid: "hexciri"', b'appid: "omarchy"', 1)
    with open(_shell_qml, "wb") as f:
        f.write(_sq)
    repaired += 1
    print("GlobalShortcut repair: shell.qml appid hexciri -> omarchy (Hyprland global dispatch is appid:name)")
elif b'appid: "omarchy"' in _sq:
    print("GlobalShortcut appid already omarchy, skipping")
else:
    print("WARN: GlobalShortcut appid not found in shell.qml, appid repair NOT applied")
# Default terminal repair, 2026-11-23: the old global foot.desktop ->
# kitty.desktop rule rewrote bin/hexciri-default-terminal so its getter
# returned "foot" for kitty.desktop (first arm, the real kitty arm below
# it unreachable) and its setter wrote kitty.desktop when foot was
# chosen. The settings menu therefore always showed Foot and picking
# Kitty changed nothing. The rule is now scoped to the terminals list
# only; this repair restores the two corrupted lines in case they
# survive in any form.
_dt = root + "/bin/hexciri-default-terminal"
with open(_dt, "rb") as f:
    _dtb = f.read()
_dt_new = _dtb.replace(b'  kitty.desktop) echo "foot" ;;', b'  foot.desktop) echo "foot" ;;')
_dt_new = _dt_new.replace(b'foot) terminal="foot"; desktop_id="kitty.desktop";', b'foot) terminal="foot"; desktop_id="foot.desktop";')
if _dt_new != _dtb:
    with open(_dt, "wb") as f:
        f.write(_dt_new)
    repaired += 1
    print("Default-terminal repair: foot.desktop restored in hexciri-default-terminal getter/setter")
print("Content rewrite: %d files scanned, %d files changed" % (total_files, changed_files))
PY
  cat "${TMP_WORK:-/tmp}/rewrite.log" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  grep -E 'WARN|Content rewrite:' "${TMP_WORK:-/tmp}/rewrite.log" | while IFS= read -r _rw; do info "$_rw"; done
  info "Content rewrite complete"
  fork_detail "Renames applied: /usr/share/omarchy -> /usr/share/hexciri, ~/.config/omarchy -> ~/.config/hexciri, ~/.local/state/omarchy -> ~/.local/state/hexciri, ~/.local/share/omarchy -> ~/.local/share/hexciri, OMARCHY_PATH -> HEXCIRI_PATH, omarchy.bar etc -> hexciri.bar etc, omarchy-shell -> hexciri-shell, omarchy-theme-set -> hexciri-theme-set, omarchy-launch-* -> hexciri-launch-*, default/hypr/omarchy.lua -> default/hypr/hexciri.lua, config/hypr/hyprland.lua env fallback updated by the same map, omarchy-* commands -> hexciri-* (generic hyphen rule), folio -> strata (launch-files only), foot.desktop -> kitty.desktop, menu trigger Omarchy logo glyph -> Arch Nerd Font glyph U+F303"
}

generate_compat() {
  step "Generating compatibility alias files (no file named omarchy is created)"
  mkdir -p "$FORK_OUT/default/hypr" "$FORK_OUT/bin"

  cat > "$FORK_OUT/default/hypr/hexciri-compat.lua" <<'EOF'
-- hexciri-compat.lua
-- Compatibility layer for Hexiri 2.0 Phase 1.
-- Legacy paths /usr/share/omarchy and ~/.config/omarchy resolve to /usr/share/hexciri and ~/.config/hexciri.
-- This alias table is the compatibility layer. A breaking rename with no alias would break plugin support,
-- including upstream Omarchy plugins and Nyxiri pizza.dirty.* plugins, so keep this table.
-- Plugin ids below are the built-in ids. Nyxiri ids (pizza.dirty.*) are not renamed and pass through unchanged.
local aliases = {
  ["omarchy.bar"] = "hexciri.bar",
  ["omarchy.menu"] = "hexciri.menu",
  ["omarchy.workspaces"] = "hexciri.workspaces",
  ["omarchy.clock"] = "hexciri.clock",
  ["omarchy.power"] = "hexciri.power",
  ["omarchy.audio"] = "hexciri.audio",
  ["omarchy.network"] = "hexciri.network",
  ["omarchy.bluetooth"] = "hexciri.bluetooth",
  ["omarchy.weather"] = "hexciri.weather",
  ["omarchy.notifications"] = "hexciri.notifications",
  ["omarchy.launcher"] = "hexciri.launcher",
  ["omarchy.lock"] = "hexciri.lock",
  ["omarchy.osd"] = "hexciri.osd",
  ["omarchy.clipboard"] = "hexciri.clipboard",
  ["omarchy.background"] = "hexciri.background",
  ["omarchy-shell"] = "hexciri-shell",
}

local function resolve_plugin(id)
  return aliases[id] or id
end

local function resolve_shell(name)
  if name == "omarchy-shell" then
    return "hexciri-shell"
  end
  return name
end

return {
  aliases = aliases,
  resolve_plugin = resolve_plugin,
  resolve_shell = resolve_shell,
}
EOF

  cat > "$FORK_OUT/bin/hexciri-compat.sh" <<'EOF'
#!/usr/bin/env bash
# hexciri-compat.sh
# Compatibility layer for Hexiri 2.0 Phase 1. Source this file from hexciri-launch-shell and env-bootstrap.
# Legacy paths /usr/share/omarchy and ~/.config/omarchy resolve to /usr/share/hexciri and ~/.config/hexciri.
# This alias table is the compatibility layer. A breaking rename with no alias would break plugin support,
# including upstream Omarchy plugins and Nyxiri pizza.dirty.* plugins, so keep this table.
# OMARCHY_PATH below is a runtime alias variable set to the same value as HEXCIRI_PATH, not a file.
# Do not create a file named omarchy as a shim.
if [ -z "${HEXCIRI_PATH:-}" ]; then
  HEXCIRI_PATH="/usr/share/hexciri"
fi
export HEXCIRI_PATH
export OMARCHY_PATH="$HEXCIRI_PATH"

# PATH for the shell process itself: hexciri-launch-shell sources this file,
# so Quickshell and everything it spawns (bar trigger, menu rows via
# Util.execDetached, panel Processes) find hexciri-* even when the uwsm
# session env did not carry /usr/share/hexciri/bin. Idempotent.
case ":$PATH:" in
  *:/usr/share/hexciri/bin:*) ;;
  *) export PATH="/usr/share/hexciri/bin:$PATH" ;;
esac

declare -A HEXCIRI_PLUGIN_ALIASES=(
  [omarchy.bar]=hexciri.bar
  [omarchy.menu]=hexciri.menu
  [omarchy.workspaces]=hexciri.workspaces
  [omarchy.clock]=hexciri.clock
  [omarchy.power]=hexciri.power
  [omarchy.audio]=hexciri.audio
  [omarchy.network]=hexciri.network
  [omarchy.bluetooth]=hexciri.bluetooth
  [omarchy.weather]=hexciri.weather
  [omarchy.notifications]=hexciri.notifications
  [omarchy.launcher]=hexciri.launcher
  [omarchy.lock]=hexciri.lock
  [omarchy.osd]=hexciri.osd
  [omarchy.clipboard]=hexciri.clipboard
  [omarchy.background]=hexciri.background
  [omarchy-shell]=hexciri-shell
)

hexciri_resolve_plugin() {
  local id="$1"
  printf '%s\n' "${HEXCIRI_PLUGIN_ALIASES[$id]:-$id}"
}

hexciri_resolve_shell() {
  if [ "${1:-}" = "omarchy-shell" ]; then
    printf '%s\n' "hexciri-shell"
  else
    printf '%s\n' "${1:-}"
  fi
}
EOF
  chmod +x "$FORK_OUT/bin/hexciri-compat.sh"
  info "Generated: default/hypr/hexciri-compat.lua"
  info "Generated: bin/hexciri-compat.sh"
}

verify_no_omarchy_files() {
  step "Verifying no file under the fork output is named omarchy"
  local bad
  bad="$(find "$FORK_OUT" -iname '*omarchy*' -print || true)"
  if [ -n "$bad" ]; then
    printf 'ERROR: files or dirs still named omarchy remain:\n%s\n' "$bad" >&2
    exit 1
  fi
  info "PASS: no file or dir named omarchy under $FORK_OUT"
}

verify_no_omarchy_paths() {
  step "Verifying no legacy install paths remain outside alias map comments"
  local bad_paths compat_bad non_comment
  bad_paths="$(grep -R -n -I -e '/usr/share/omarchy' -e '\.config/omarchy' -e '\.local/state/omarchy' -e '\.local/share/omarchy' "$FORK_OUT" --exclude='hexciri-compat.*' || true)"
  if [ -n "$bad_paths" ]; then
    printf 'ERROR: legacy Omarchy paths remain outside alias files:\n%s\n' "$bad_paths" >&2
    exit 1
  fi
  compat_bad="$(grep -R -n -I -e '/usr/share/omarchy' -e '\.config/omarchy' -e '\.local/state/omarchy' -e '\.local/share/omarchy' "$FORK_OUT" --include='hexciri-compat.*' || true)"
  if [ -n "$compat_bad" ]; then
    non_comment="$(printf '%s\n' "$compat_bad" | grep -v -E ':[[:space:]]*(#|--)' || true)"
    if [ -n "$non_comment" ]; then
      printf 'ERROR: legacy Omarchy paths in alias files outside comments:\n%s\n' "$non_comment" >&2
      exit 1
    fi
    info "Legacy paths found only inside alias map comments, allowed"
  fi
  info "PASS: no /usr/share/omarchy, ~/.config/omarchy, ~/.local/state/omarchy, or ~/.local/share/omarchy paths remain outside alias comments"
}

verify_no_omarchy_lua_modules() {
  step "Verifying no Lua file still requires the renamed default.hypr.omarchy module"
  local bad_mods
  bad_mods="$(grep -R -n -I -e 'default\.hypr\.omarchy' -e 'hypr\.omarchy["'"'"')]' "$FORK_OUT" --include='*.lua' || true)"
  if [ -n "$bad_mods" ]; then
    printf 'ERROR: Lua files still require the renamed omarchy module (this tripped Hyprland emergency mode on the first live boot):\n%s\n' "$bad_mods" >&2
    exit 1
  fi
  info "PASS: no Lua file requires default.hypr.omarchy"
}

copy_subsets
rename_files
rewrite_contents
generate_compat
verify_no_omarchy_files
verify_no_omarchy_paths
verify_no_omarchy_lua_modules

step "Fork summary"
fork_detail "Fork output: $FORK_OUT"
info "Fork: $(find "$FORK_OUT" -type f | wc -l | tr -d ' ') files, $(find "$FORK_OUT" -type d | wc -l | tr -d ' ') dirs, $(find "$FORK_OUT/themes" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ') themes, $(find "$FORK_OUT/bin" -type f 2>/dev/null | wc -l | tr -d ' ') bin scripts (Omarchy ${PINNED_SHA:-unknown}, renamed omarchy -> hexciri; full file list: ${FORK_LOG:-/tmp/hexciri-install-fork.log})"
find "$FORK_OUT" -mindepth 1 -maxdepth 2 -print | sort >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true

fi # end upstream fork guard: download/copy/rename/rewrite only

# Save the upstream (pre-patch) fork, so a patch-only change can
# re-apply patches to this tree instead of re-forking Omarchy.
if [ "${SKIP_UPSTREAM:-0}" = "0" ] && [ -n "${UP_FP:-}" ] && [ -n "${FORK_CACHE_DIR:-}" ]; then
  rm -rf "$FORK_CACHE_DIR/upstream-out"
  mkdir -p "$FORK_CACHE_DIR"
  # Verify the copy before trusting it: a failed cp -a must not leave a
  # partial cache behind with a valid fingerprint (sim8, 2026-11-24).
  # cp -a's exit status is NOT the authority: it fails (EPERM) when it
  # cannot preserve ownership, even though the content was copied fine.
  # Content + file count decide; a genuinely partial copy fails those.
  cp -a "$FORK_OUT" "$FORK_CACHE_DIR/upstream-out" 2>/dev/null || true
  if bootstrap_ok "$FORK_CACHE_DIR/upstream-out/default/hypr/bootstrap.lua" && hyprlua_ok "$FORK_CACHE_DIR/upstream-out/default/hypr/hexciri.lua" && [ "$(find "$FORK_OUT" -type f 2>/dev/null | wc -l | tr -d ' ')" = "$(find "$FORK_CACHE_DIR/upstream-out" -type f 2>/dev/null | wc -l | tr -d ' ')" ]; then
    printf '%s\n' "$UP_FP" > "$FORK_CACHE_DIR/upstream-fingerprint"
    fork_detail "Upstream fork cache saved: $FORK_CACHE_DIR/upstream-out"
  else
    warn "Upstream fork cache copy failed or incomplete, dropping the partial cache (next run full re-forks instead of trusting it)"
    rm -rf "$FORK_CACHE_DIR/upstream-out" "$FORK_CACHE_DIR/upstream-fingerprint"
  fi
fi
# Emergency-mode guard, 2026-11-24: fail fast if the fork lost
# bootstrap.lua, before patches run and before placement wipes the
# last good /usr/share/hexciri. Hyprland dofiles this file first;
# without it the next boot trips emergency mode with no binds.
if [ "${SKIP_PATCHES:-0}" = "0" ] && ! bootstrap_ok "$FORK_OUT/default/hypr/bootstrap.lua" || [ "${SKIP_PATCHES:-0}" = "0" ] && ! hyprlua_ok "$FORK_OUT/default/hypr/hexciri.lua"; then
  die "fork lost default/hypr/bootstrap.lua or hexciri.lua (missing, empty or truncated; Hyprland dofiles bootstrap first, then requires hexciri.lua at hyprland.lua:17, without either the next boot trips emergency mode). Refusing to continue with a broken fork."
fi

# Patch guard: compat wiring + all fork patches run on the upstream
# tree (fresh, or restored from the upstream cache). They never run on
# an already-patched tree, so whole-file rewrites stay idempotent.
if [ "${SKIP_PATCHES:-0}" = "0" ]; then

# --- Apply fork patches (v2/patches/) ---
# The fork patches used to live inline here (~3000 lines). They moved to
# v2/patches/ on 2026-11-24 (Devi: "shouldn't all patches have been in a
# /patches on GH, be cleaner?"): one file per patch, applied in MANIFEST
# order by v2/patches/apply.sh, each patch a standalone script taking
# FORK_OUT. Behavior is identical, only the location changed; the runner
# dies naming the failing patch, so the installer never continues onto
# a half-patched fork. PATCHES_DIR override is for sims/tests only.
PATCHES_DIR="${HEXCIRI_PATCHES_DIR:-$INSTALLER_DIR/patches}"
# apply.sh is invoked via bash, never exec'd, so -f is the right test,
# not -x: github push-files lands repo files mode 644 (no exec bit),
# and a fresh git clone has apply.sh 644 too. -x died on every update
# with "not in the installer tree" even though the patches dir was
# pulled fine (2026-11-24, Devi 16:54 MST, laptop).
if [ -f "$PATCHES_DIR/apply.sh" ]; then
  FORK_OUT="$FORK_OUT" HEXCIRI_PATH="$HEXCIRI_PATH" HEXCIRI_REPO_ROOT="$HEXCIRI_REPO_ROOT" INSTALLER_DIR="$INSTALLER_DIR" FORK_LOG="$FORK_LOG" _patch_log="$_patch_log" bash "$PATCHES_DIR/apply.sh" "$FORK_OUT" || die "fork patches failed (v2/patches/apply.sh names the failing patch above)"
else
  die "v2/patches/apply.sh missing from the installer tree ($PATCHES_DIR), cannot apply fork patches"
fi

# Save the fully patched fork for the next re-run (fork cache,
# 2026-11-24). Only when patches actually ran (SKIP_PATCHES=0) and
# the fingerprints were computed (a real install, not sim7, which
# sources only the fork block and has no PATCH_FP).
if [ "${SKIP_PATCHES:-0}" = "0" ] && [ -n "${PATCH_FP:-}" ] && [ -n "${FORK_CACHE_DIR:-}" ]; then
  mkdir -p "$FORK_CACHE_DIR"
  rm -rf "$FORK_CACHE_DIR/fork-out"
  # Verify the copy before trusting it: sim8 2026-11-24 showed a failed
  # cp -a still printing "Fork cache saved" and writing the fingerprint,
  # so the next update restored a partial tree. Only write the
  # fingerprint when the saved tree is complete and bootstrap.lua is valid.
  # cp -a's exit status is NOT the authority (ownership EPERM can fail
  # it after a good copy); content + file count decide.
  cp -a "$FORK_OUT" "$FORK_CACHE_DIR/fork-out" 2>/dev/null || true
  if bootstrap_ok "$FORK_CACHE_DIR/fork-out/default/hypr/bootstrap.lua" && hyprlua_ok "$FORK_CACHE_DIR/fork-out/default/hypr/hexciri.lua" && [ "$(find "$FORK_OUT" -type f 2>/dev/null | wc -l | tr -d ' ')" = "$(find "$FORK_CACHE_DIR/fork-out" -type f 2>/dev/null | wc -l | tr -d ' ')" ]; then
    printf '%s\n' "$PATCH_FP" > "$FORK_CACHE_DIR/patch-fingerprint"
    [ -n "${FORK_FP:-}" ] && printf '%s\n' "$FORK_FP" > "$FORK_CACHE_DIR/fork-fingerprint"
    info "Fork cache saved: $FORK_CACHE_DIR/fork-out (reused on the next update unless the fork changes)"
  else
    warn "Fork cache copy failed or incomplete, dropping the partial cache and its fingerprint (next run re-applies patches instead of trusting it)"
    rm -rf "$FORK_CACHE_DIR/fork-out" "$FORK_CACHE_DIR/patch-fingerprint" "$FORK_CACHE_DIR/fork-fingerprint"
  fi
fi

fi # end patch guard: compat wiring + all fork patches

# --- mise + Hexciri tools config (Phase 2, 2026-11-24) ---
# mise was out of scope in the Phase 1 base; reinstall it so the rest of the
# Omarchy scripts work. /etc/mise/conf.d/hexciri-tools.toml is the trimmed
# upstream tools config: node, uv, gh, lazy, no AI agent CLIs, no Herdr.
step "Installing mise + Hexciri tools config (/etc/mise/conf.d/hexciri-tools.toml)"
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-tools.toml" ]; then
  sudo install -Dm644 "$HEXCIRI_REPO_ROOT/v2/hexciri-tools.toml" /etc/mise/conf.d/hexciri-tools.toml && info "  mise tools config installed: /etc/mise/conf.d/hexciri-tools.toml (node, uv, gh, lazy; no AI agents, no Herdr)" || warn "  could not install /etc/mise/conf.d/hexciri-tools.toml, mise tools config missing"
else
  warn "  v2/hexciri-tools.toml not in the installer tree, mise tools config not installed"
fi
if command -v mise >/dev/null 2>&1; then
  MISE_OFFLINE=true MISE_LOG_LEVEL=error mise reshim --system 2>/dev/null || warn "  mise reshim --system failed, lazy shims may be stale"
  MISE_OFFLINE=true MISE_LOG_LEVEL=error mise reshim 2>/dev/null || warn "  mise reshim failed"
  info "  mise: $(mise --version 2>/dev/null || echo present)"
else
  warn "  mise not installed, Omarchy scripts that call mise will fail (pacman: mise)"
fi

# --- THPM + steam-adwaita (Phase 2, 2026-11-24, Devi: THPM in the theme hook) ---
# THPM (Theme Hook Plugin Manager, OldJobobo/thpm) was kicked off AUR:
# install from a GitHub source checkout, NOT yay/pacman. Source install
# is a private user install: python venv at ~/.local/share/thpm/runtime,
# launcher ~/.local/bin/thpm, `thpm install --no-ui` registers its hook
# at ~/.config/omarchy/hooks/theme-set.d/90-thpm. Hexciri's hexciri-hook
# reads ~/.config/hexciri/hooks/theme-set.d/ instead, so this step
# bridges that hook file across (hook 20-hexciri-thpm runs
# `thpm hook-run theme-set` directly as a fallback). THPM reads the
# active theme from ~/.local/state/omarchy/current/theme, which the
# Strata theme hook symlinks to Hexciri's live theme files on every
# switch, before 90-thpm runs (10- before 90-). Integrations are all
# disabled by default in THPM; only steam is enabled here, and only
# when Steam is actually installed.
# Best-effort, never dies: a THPM failure must not break the install,
# the theme hook skips quietly when thpm is absent.
step "Installing THPM (GitHub source, not AUR) + steam-adwaita checkout"
export PATH="$HOME/.local/bin:$PATH"
# Compat alias for THPM (sim7, 2026-11-24: thpm install fails without
# it). THPM hardcodes the `omarchy` CLI (src/thpm/omarchy.py:
# run(["omarchy", ...]) + capabilities() via `omarchy commands
# --json`, REQUIRED_ROUTES "omarchy hook", "omarchy hook install",
# "omarchy theme refresh", "omarchy shell", "omarchy plugin",
# "omarchy menu"). Hexciri renamed the CLI to hexciri, so THPM's
# capability check fails and install.sh rolls the runtime back.
# This shim is the same class of accepted exception as the
# GlobalShortcut appid staying "omarchy" and the helpers.lua
# "omarchy:" dispatch prefix: third-party code that names omarchy,
# bridged at runtime. It lives in /usr/local/bin (default PATH
# everywhere, including the theme-set hook environment), NOT in
# /usr/share/hexciri/bin, where the placement scan dies on any file
# named omarchy. `commands --json` translates route names back to
# omarchy so THPM's six required routes match (verified: the fork's
# `hexciri commands --json` lists all six as hexciri routes).
if [ ! -x /usr/local/bin/omarchy ]; then
  sudo tee /usr/local/bin/omarchy >/dev/null <<'OMARCHY_SHIM_EOF'
#!/bin/bash
# Hexciri compat alias for THPM: THPM hardcodes the omarchy CLI.
# Forwards to hexciri, translating route names in commands --json.
if [ "${1:-}" = "commands" ] && [ "${2:-}" = "--json" ]; then
  hexciri commands --json | sed 's/"hexciri /"omarchy /g'
  exit "${PIPESTATUS[0]}"
fi
exec hexciri "$@"
OMARCHY_SHIM_EOF
  sudo chmod +x /usr/local/bin/omarchy 2>/dev/null && info "  THPM compat alias installed: /usr/local/bin/omarchy -> hexciri (THPM hardcodes the omarchy CLI)" || warn "  could not install /usr/local/bin/omarchy, thpm install will fail its capability check"
fi
THPM_SRC="$HOME/.local/opt/thpm"
THPM_NEED_INSTALL=0
if command -v git >/dev/null 2>&1; then
  if [ -d "$THPM_SRC/.git" ]; then
    git -C "$THPM_SRC" fetch --quiet origin 2>/dev/null && git -C "$THPM_SRC" pull --ff-only --quiet 2>/dev/null && info "  THPM source updated: $THPM_SRC" || warn "  THPM source pull failed, keeping existing checkout at $THPM_SRC"
  else
    git clone --quiet https://github.com/OldJobobo/thpm.git "$THPM_SRC" 2>/dev/null && info "  THPM source cloned: $THPM_SRC" || warn "  THPM source clone failed, THPM will not be installed (theme hook skips it)"
  fi
else
  warn "  git not found, THPM source install skipped"
fi
if [ -x "$THPM_SRC/install.sh" ]; then
  if ! command -v thpm >/dev/null 2>&1; then THPM_NEED_INSTALL=1; fi
  if [ "$THPM_NEED_INSTALL" = "1" ]; then
    (cd "$THPM_SRC" && ./install.sh --no-ui >/tmp/hexciri-thpm-install.log 2>&1) && info "  THPM installed: $(thpm --version 2>/dev/null || echo thpm) (source, --no-ui, launcher ~/.local/bin/thpm)" || warn "  THPM source install failed (see /tmp/hexciri-thpm-install.log), theme hook will skip THPM"
  else
    info "  THPM already installed: $(thpm --version 2>/dev/null || echo thpm), skipping source reinstall"
  fi
fi
# steam-adwaita checkout: THPM's steam integration (and v1's 40-steam.sh)
# install the active palette through it. Clone once, pull on re-run.
STEAM_ADWAITA="$HOME/.local/share/steam-adwaita"
if command -v git >/dev/null 2>&1; then
  if [ -d "$STEAM_ADWAITA/.git" ]; then
    git -C "$STEAM_ADWAITA" pull --ff-only --quiet 2>/dev/null || true
  elif [ ! -d "$STEAM_ADWAITA" ]; then
    git clone --quiet https://github.com/tkashkin/Adwaita-for-Steam "$STEAM_ADWAITA" 2>/dev/null && info "  steam-adwaita checkout cloned: $STEAM_ADWAITA" || warn "  steam-adwaita clone failed, THPM steam integration stays unavailable (thpm report steam)"
  fi
fi
# Bridge THPM's own hook into Hexciri's hook dir, and enable steam.
if command -v thpm >/dev/null 2>&1; then
  if [ -f "$HOME/.config/omarchy/hooks/theme-set.d/90-thpm" ]; then
    mkdir -p "$HOME/.config/hexciri/hooks/theme-set.d"
    ln -sfn "$HOME/.config/omarchy/hooks/theme-set.d/90-thpm" "$HOME/.config/hexciri/hooks/theme-set.d/90-thpm" && info "  THPM hook bridged: ~/.config/hexciri/hooks/theme-set.d/90-thpm -> omarchy hook dir" || warn "  could not bridge THPM 90-thpm hook, hook 20-hexciri-thpm still runs thpm on theme switch"
  fi
  info "  THPM steam integration is enabled after the theme is applied (theme-hook step below), not here: no theme is staged yet"
fi
unset THPM_SRC THPM_NEED_INSTALL STEAM_ADWAITA

# --- Place the forked tree to its install targets ---
# sudo is used ONLY for the /usr/share and /etc steps below. Everything else
# runs as the normal user.

step "Placing forked tree: /usr/share/hexciri (sudo), ~/.config, ~/.local/state"

# Pause Hyprland auto-reload BEFORE the tree is replaced (2026-11-24):
# rm -rf + cp -a fires inotify on every tracked Lua file and Hyprland
# reloads mid-copy into emergency mode. The guard (upstream's fix,
# never wired in Hexciri) disables autoreload until resume.
hypr_guard_pause

# Pre-placement binds guard (2026-11-24, Devi: Super+Space apps and
# Super+Alt+Space menu both died after the 2cdc33c7 update): that update
# replaced /usr/share/hexciri, then placement verification died on
# config/tmux/tmux.conf, so the update aborted with a new, unverified
# tree live, Hyprland reloaded on it by the guard resume, and the shell
# never restarted. Both chords go through GlobalShortcuts, so a reload
# onto a bad tree (or a shell that never re-registers them) kills both
# at once while plain command binds keep working. Check the whole chain
# in the FORK, before anything is replaced: a broken fork dies here
# with the last good tree still live, never after rm -rf.
# Moved here 2026-11-24 (noise fix): it used to sit before the Place
# header, inside system_fingerprint()'s range, so this one check line
# moved the system fingerprint and forced a full installer on every
# update after 6e48f01. It now sits after the Place header, outside
# every fingerprint range, so a check can never move a fingerprint.
binds_chain_ok "$FORK_OUT" || die "binds chain broken in fork (Super+Space apps / Super+Alt+Space menu would not register; see above). Refusing to place a broken fork over the working tree."

sudo rm -rf "$HEXCIRI_PATH"
sudo mkdir -p "$HEXCIRI_PATH"
sudo cp -a "$FORK_OUT/shell" "$FORK_OUT/default" "$FORK_OUT/themes" "$FORK_OUT/bin" "$FORK_OUT/install" "$FORK_OUT/icons" "$FORK_OUT/config" "$FORK_OUT/applications" "$HEXCIRI_PATH/"
# config/ was missing from the placement copy (2026-11-24): the Learn
# fix copied config/tmux into the fork and verified
# $HEXCIRI_PATH/config/tmux/tmux.conf, but placement never copied
# config/ at all, so that check died on every update. Same for
# chromium-flags.conf / alacritty / ghostty, checked right after it.
# FORK_OUT/config is already curated (copy_subsets only), no
# omarchy-named files, no foot/herdr/obsidian clutter.
# applications/ was missing from the placement copy (2026-11-24, Devi:
# update died at "missing: applications/foot.desktop"): the 81356136
# verification checks $HEXCIRI_PATH/applications/foot.desktop and
# install-terminal foot copies it from there at runtime, but placement
# only ever put the fork's applications/*.desktop files in
# ~/.local/share/applications/ as user entries, never in the placed
# tree, so the check died on every update since. Same fix as config/
# in the tmux placement fix above. FORK_OUT/applications is already
# curated (copy_subsets copies only omarchy-browser, omarchy-terminal
# and foot .desktop files), no Omarchy web-app clutter.
# icons/ is required (copy_subset dies if upstream lacks it), but
# logo.txt / icon.txt are optional in copy_subsets (warn only), so
# copy them only when present: a missing file in the cp line above
# would fail the whole placement under set -e, while the verification
# below dies with the clearer "missing: logo.txt / icon.txt" error.
for _txt in logo.txt icon.txt; do
  [ -f "$FORK_OUT/$_txt" ] && sudo cp -a "$FORK_OUT/$_txt" "$HEXCIRI_PATH/"
done
unset _txt
sudo chmod +x "$HEXCIRI_PATH"/bin/* 2>/dev/null || true
# Installer tree sha marker for hexciri-update-hexciri: it re-runs this
# installer only when the installer tree (install.sh + v2/patches/)
# changed. installer_tree_sha() covers both, so a patch-only change
# is not missed.
installer_tree_sha | sudo tee "$HEXCIRI_PATH/.installer-sha" >/dev/null && info "Wrote installer sha marker /usr/share/hexciri/.installer-sha (hexciri update re-runs the installer only when this changes)" || warn "could not write installer sha marker, hexciri update will re-run the installer every time"
[ -n "${FORK_FP:-}" ] && printf '%s\n' "$FORK_FP" | sudo tee "$HEXCIRI_PATH/.fork-fingerprint" >/dev/null || true
[ -n "${UP_FP:-}" ] && printf '%s\n' "$UP_FP" | sudo tee "$HEXCIRI_PATH/.upstream-fingerprint" >/dev/null || true
[ -n "${PATCH_FP:-}" ] && printf '%s\n' "$PATCH_FP" | sudo tee "$HEXCIRI_PATH/.patch-fingerprint" >/dev/null || true
printf '%s\n' "$(provision_fingerprint)" | sudo tee "$HEXCIRI_PATH/.provision-fingerprint" >/dev/null || true
printf '%s\n' "$(system_fingerprint)" | sudo tee "$HEXCIRI_PATH/.system-fingerprint" >/dev/null || true
info "Installed: $HEXCIRI_PATH/shell, $HEXCIRI_PATH/default, $HEXCIRI_PATH/themes, $HEXCIRI_PATH/bin, $HEXCIRI_PATH/install (browser-policy helpers), $HEXCIRI_PATH/icons, $HEXCIRI_PATH/config, $HEXCIRI_PATH/logo.txt, $HEXCIRI_PATH/icon.txt"

mkdir -p "$HOME/.config/hypr" "$HOME/.config/hexciri" \
  "$HOME/.local/state/hexciri/current" "$HOME/.local/state/hexciri/toggles/hypr" \
  "$HOME/.local/state/hexciri/migrations" "$HOME/.local/share/hexciri" \
  "$HOME/.config/hexciri/plugins" "$HOME/.config/hexciri/themes" "$HOME/.config/hexciri/hooks" \
  "$HOME/.local/bin"

place_user_file() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ ! -e "$dest" ]; then
    cp -a "$src" "$dest"
    info "Placed: $dest"
    return 0
  fi
  if cmp -s "$src" "$dest"; then
    info "Kept: $dest (already current)"
    return 0
  fi
  # Re-run: NEVER overwrite a user file. Save the upstream version next
  # to it so a fix can be merged by hand, and keep the user's file.
  # This is the shell.json / hyprland.lua / kitty.conf reset fix.
  if [ "${IS_RERUN:-0}" = "1" ]; then
    cp -a "$src" "$dest.hexciri.new"
    info "Kept your $dest (re-run, upstream version saved to $dest.hexciri.new)"
    # Safety migration only: an old hyprland.lua still requiring
    # default.hypr.omarchy trips Hyprland emergency mode at boot.
    # Fix that one line in place, touch nothing else in the file.
    if [ "$(basename "$dest")" = "hyprland.lua" ] && grep -q 'default\.hypr\.omarchy' "$dest"; then
      sed -i 's/default\.hypr\.omarchy/default.hypr.hexciri/g' "$dest"
      info "Migrated $dest: default.hypr.omarchy -> default.hypr.hexciri (emergency-mode fix, rest of file kept)"
    fi
    return 0
  fi
  # Fresh install with a pre-existing file: back it up, then place.
  cp -a "$dest" "$dest.hexciri.bak"
  info "Backed up existing $dest to $dest.hexciri.bak"
  cp -a "$src" "$dest"
  info "Placed: $dest"
}

# User Hyprland templates: hyprland.lua, bindings.lua, monitors.lua, input.lua,
# looknfeel.lua, autostart.lua, hyprsunset.conf, xdph.conf
for hypr_file in "$FORK_OUT"/config/hypr/*; do
  [ -e "$hypr_file" ] || continue
  place_user_file "$hypr_file" "$HOME/.config/hypr/$(basename "$hypr_file")"
done

# Shell layout config
place_user_file "$FORK_OUT/config/shell.json" "$HOME/.config/hexciri/shell.json"

# Hyprland 0.57 trap: a stray hyprland.conf is ignored on 0.57, move it aside.
if [ "${HYPR_VERSION:-}" = "0.57" ] && [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
  mv "$HOME/.config/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf.hexciri.bak"
  info "Moved stray hyprland.conf to hyprland.conf.hexciri.bak (Hyprland 0.57 is Lua only)."
fi

# Bin scripts on PATH: symlink the installed hexciri-* scripts into ~/.local/bin
for bin_file in "$HEXCIRI_PATH"/bin/hexciri-*; do
  [ -e "$bin_file" ] || continue
  ln -sf "$bin_file" "$HOME/.local/bin/$(basename "$bin_file")"
done
info "Linked: $HEXCIRI_PATH/bin/hexciri-* into ~/.local/bin/"
# Bare dispatcher, 2026-11-23: the glob above is hexciri-*, which never
# matches the bare `hexciri` binary itself, so ~/.local/bin/hexciri was
# never linked and `hexciri plugin list` was "command not found" in every
# terminal whose /usr/local/bin link had also failed (sudo timestamp).
ln -sf "$HEXCIRI_PATH/bin/hexciri" "$HOME/.local/bin/hexciri"
info "Linked: ~/.local/bin/hexciri (bare dispatcher, the hexciri-* glob never matches it)"

# Browser + terminal desktop entries: upstream applications/ ships
# omarchy-browser.desktop and omarchy-terminal.desktop, renamed to
# hexciri-*.desktop by the fork. They are the default-browser / default-
# terminal launchers (and the dock's stand-ins for WebBrowser /
# TerminalEmulator windows), so they are placed even though they are NOT
# dock pins: the pinned list is brave-origin / kitty directly, and pinning
# these wrappers too would duplicate both. Plus foot.desktop (2026-11-24):
# install-terminal foot installs it as the Foot desktop entry, so it is
# placed as a user entry here too. Only these three are placed: the other
# applications/*.desktop files are Omarchy web apps (ChatGPT, Herdr,
# Discord, ...) and AI/out-of-scope entries.
mkdir -p "$HOME/.local/share/applications"
for desk_file in "$FORK_OUT"/applications/*.desktop; do
  [ -e "$desk_file" ] || continue
  place_user_file "$desk_file" "$HOME/.local/share/applications/$(basename "$desk_file")"
  # NoDisplay on the placed wrappers, 2026-11-23: without it the Super+Space
  # app grid shows Browser + Terminal wrapper entries next to Brave Origin
  # + Kitty, which are already pinned. The dock stand-in logic does not
  # need these entries visible, and hexciri-launch-browser / terminal exec
  # the default browser / terminal directly, not via the .desktop file.
  if ! grep -q '^NoDisplay=' "$HOME/.local/share/applications/$(basename "$desk_file")"; then
    printf 'NoDisplay=true\n' >> "$HOME/.local/share/applications/$(basename "$desk_file")"
  fi
  info "Placed desktop entry: $HOME/.local/share/applications/$(basename "$desk_file") (NoDisplay, wrapper only)"
done

# hexciri CLI on PATH everywhere, not just login shells: /usr/local/bin is
# on the default PATH for login and non-login shells alike, and Kitty runs
# bash non-login, so profile.d alone left `hexciri plugin list` as
# "command not found" in a terminal. Also append ~/.local/bin and
# /usr/share/hexciri/bin to the interactive shell rc files, so the
# hexciri-* symlinks work there too.
if [ -x "$HEXCIRI_PATH/bin/hexciri" ]; then
  sudo ln -sf "$HEXCIRI_PATH/bin/hexciri" /usr/local/bin/hexciri 2>/dev/null && info "Linked: /usr/local/bin/hexciri" || warn "could not link /usr/local/bin/hexciri, hexciri CLI needs ~/.local/bin on PATH"
fi
if [ -x /usr/local/bin/hexciri ]; then
  info "Verified: /usr/local/bin/hexciri"
else
  warn "could not link /usr/local/bin/hexciri (sudo timestamp may have expired), hexciri CLI relies on ~/.local/bin on PATH"
fi
if [ -f "$HOME/.bashrc" ] && ! grep -q 'hexciri/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# Hexciri 2.0: hexciri CLI and helpers on PATH for interactive shells\ncase ":$PATH:" in\n  *:/usr/share/hexciri/bin:*) ;;\n  *) export PATH="/usr/share/hexciri/bin:$HOME/.local/bin:$PATH" ;;\nesac\n' >> "$HOME/.bashrc"
  info "Appended Hexciri PATH to ~/.bashrc"
fi
if [ -d "$HOME/.config/fish" ]; then
  mkdir -p "$HOME/.config/fish/conf.d"
  if ! grep -q 'hexciri/bin' "$HOME/.config/fish/conf.d/hexciri.fish" 2>/dev/null; then
    printf '# Hexciri 2.0: hexciri CLI and helpers on PATH\nif not contains /usr/share/hexciri/bin $PATH\n  set -gx PATH /usr/share/hexciri/bin $HOME/.local/bin $PATH\nend\n' > "$HOME/.config/fish/conf.d/hexciri.fish"
    info "Wrote: ~/.config/fish/conf.d/hexciri.fish (Hexciri PATH)"
  fi
fi

# Terminal preference list: launch-terminal's fast path reads
# ~/.config/xdg-terminals.list (and hyprland-xdg-terminals.list) first and
# opens kitty.desktop from it, instead of calling xdg-terminal-exec.
# Without these files every terminal launch falls through to xdg-terminal-exec.
if [ -f "$HEXCIRI_PATH/default/xdg-terminal-exec/hyprland-xdg-terminals.list" ]; then
  mkdir -p "$HOME/.config/xdg-terminal-exec"
  # User file, not code: place_user_file keeps it on a re-run (upstream
  # saved as .hexciri.new) instead of cp -a overwriting it every run.
  place_user_file "$HEXCIRI_PATH/default/xdg-terminal-exec/hyprland-xdg-terminals.list" "$HOME/.config/xdg-terminal-exec/hyprland-xdg-terminals.list"
  place_user_file "$HEXCIRI_PATH/default/xdg-terminal-exec/hyprland-xdg-terminals.list" "$HOME/.config/xdg-terminals.list"
  info "Placed: ~/.config/xdg-terminals.list and ~/.config/xdg-terminal-exec/hyprland-xdg-terminals.list (kitty.desktop)"
else
  warn "xdg-terminals.list not found in fork, terminal launches fall back to xdg-terminal-exec."
fi

# Kitty config: upstream config/kitty/kitty.conf includes the staged theme
# kitty.conf (~/.local/state/hexciri/current/theme/kitty.conf). It was never
# placed, so Kitty loaded no theme at all. Place it, set the font to the
# Nerd Font the installer ships (the upstream line is commented out, which
# left fastfetch reading the fc-match fallback Noto Sans).
if [ -f "$FORK_OUT/config/kitty/kitty.conf" ]; then
  # Font fix only when the file was actually placed/changed: on a
  # re-run place_user_file keeps the user's file, and re-applying the
  # font sed/append here would mutate a kept file every run.
  _kitty_before="$(sha256sum "$HOME/.config/kitty/kitty.conf" 2>/dev/null | cut -d' ' -f1 || echo none)"
  place_user_file "$FORK_OUT/config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  _kitty_after="$(sha256sum "$HOME/.config/kitty/kitty.conf" 2>/dev/null | cut -d' ' -f1 || echo none)"
  if [ "$_kitty_before" = "$_kitty_after" ] && [ "$_kitty_before" != "none" ]; then
    info "Kept your ~/.config/kitty/kitty.conf font setting (re-run, file unchanged)"
  elif grep -q '^# font_family' "$HOME/.config/kitty/kitty.conf"; then
    sed -i 's/^# font_family .*/font_family JetBrainsMono Nerd Font/' "$HOME/.config/kitty/kitty.conf"
  elif ! grep -q '^font_family' "$HOME/.config/kitty/kitty.conf"; then
    printf 'font_family JetBrainsMono Nerd Font\n' >> "$HOME/.config/kitty/kitty.conf"
  fi
  unset _kitty_before _kitty_after
  info "Placed: ~/.config/kitty/kitty.conf (includes the staged theme kitty.conf, font JetBrainsMono Nerd Font)"
else
  warn "config/kitty/kitty.conf not found in fork, Kitty will not load the theme colours."
fi

# --- Repair font-set fonts.conf (2026-11-24, Maple Mono NF) ---
# A fonts.conf written by the old hexciri-font-set has a single match block
# testing family == monospace. Upstream Omarchy's
# default/fontconfig/conf.avail/50-omarchy.conf (leftover in
# /etc/fonts/conf.d/ from the Omarchy install) assigns monospace to
# JetBrainsMono Nerd Font before this file is read, so that test never
# matches and fc-match monospace keeps returning JetBrainsMono: the menu
# never shows the chosen font as current. The fixed font-set writes a
# second match block for JetBrainsMono Nerd Font. Rewrite an existing
# font-set-shaped file (prepend_first + monospace test, no second block
# yet) with the fixed template, keeping the family the user already
# chose. Hand-written fonts.conf files (no prepend_first) are untouched.
# Fresh installs no-op (no file yet).
_fc_file="$HOME/.config/fontconfig/fonts.conf"
if [ -f "$_fc_file" ] && grep -q 'prepend_first' "$_fc_file" && grep -q '<string>monospace</string>' "$_fc_file" && ! grep -q 'Hexciri font-set second match' "$_fc_file"; then
  _fc_family="$(python3 - "$_fc_file" <<'PYEOF' 2>/dev/null
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'<edit[^>]*mode="prepend_first"[^>]*>\s*<string>([^<]+)</string>', src)
print(m.group(1).strip() if m else "")
PYEOF
)"
  if [ -n "$_fc_family" ]; then
    cat >"$_fc_file" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Hexciri font-set second match: catches the system-assigned monospace default (see hexciri-font-set) -->
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$_fc_family</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="family" qual="any">
      <string>JetBrainsMono Nerd Font</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$_fc_family</string>
    </edit>
  </match>
</fontconfig>
XML
    _fc_now="$(fc-match monospace -f '%{family}\n' 2>/dev/null | head -n1 | cut -d, -f1 || true)"
    if [ "$_fc_now" = "$_fc_family" ]; then
      info "Repaired ~/.config/fontconfig/fonts.conf (font-set second match block): fc-match monospace now returns $_fc_family"
    else
      warn "Repaired ~/.config/fontconfig/fonts.conf, but fc-match monospace still returns '${_fc_now:-unknown}' instead of $_fc_family: check /etc/fonts/conf.d/ for another monospace assign rule"
    fi
    unset _fc_now
  else
    warn "Could not read the chosen family from ~/.config/fontconfig/fonts.conf, leaving it alone (pick the font again in Appearance > Font)"
  fi
  unset _fc_family
fi
unset _fc_file
# --- end Maple Mono NF fonts.conf repair ---

# Tmux config: upstream config/tmux/tmux.conf is the fallback
# hexciri-menu-tmux-keybindings reads, but tmux itself only loads
# ~/.config/tmux/tmux.conf on start. Place it like kitty.conf above,
# so Super+Alt+Return actually runs with the Hexciri config, not
# tmux defaults. place_user_file keeps the user's file on a re-run.
if [ -f "$FORK_OUT/config/tmux/tmux.conf" ]; then
  place_user_file "$FORK_OUT/config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  info "Placed: ~/.config/tmux/tmux.conf (Hexciri tmux config)"
else
  warn "config/tmux/tmux.conf not found in fork, tmux will run with defaults and Learn > Tmux falls back to nothing."
fi

# Env files: HEXCIRI_PATH and PATH, for logins and uwsm sessions (sudo steps)
TMP_PROFILE="$(mktemp)"
cat > "$TMP_PROFILE" <<'EOF'
# Hexiri 2.0: HEXCIRI_PATH, with OMARCHY_PATH as a runtime alias, not a file.
export HEXCIRI_PATH="/usr/share/hexciri"
export OMARCHY_PATH="$HEXCIRI_PATH"
case ":$PATH:" in
  *:/usr/share/hexciri/bin:*) ;;
  *) export PATH="/usr/share/hexciri/bin:$PATH" ;;
esac
# ~/.local/bin holds Strata (bin/hexciri-strata-install puts it there) and
# the ~/.local/bin/hexciri-* symlinks, so it belongs on PATH too.
case ":$PATH:" in
  *:"$HOME"/.local/bin:*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
# mise lazy shims live here (upstream env-bootstrap already adds this dir to
# the interactive PATH; profile.d adds it for logins and uwsm sessions too).
case ":$PATH:" in
  *:"$HOME"/.local/share/mise/shims:*) ;;
  *) export PATH="$HOME/.local/share/mise/shims:$PATH" ;;
esac
EOF
sudo install -Dm644 "$TMP_PROFILE" /etc/profile.d/hexciri.sh
rm -f "$TMP_PROFILE"
info "Installed: /etc/profile.d/hexciri.sh"

# PATH for the uwsm session itself: /etc/profile.d is only sourced by login
# shells, and Hyprland exec (Super+Space apps, Super+Alt+Space menu) runs
# with the compositor's environment. Bake the install-time PATH in literally
# so hexciri-* is findable there even when profile.d is not sourced.
TMP_UWSM="$(mktemp)"
{
  printf 'HEXCIRI_PATH=/usr/share/hexciri\n'
  printf 'OMARCHY_PATH=/usr/share/hexciri\n'
  printf 'PATH=/usr/share/hexciri/bin:%s/.local/bin:%s/.local/share/mise/shims:%s\n' "$HOME" "$HOME" "$PATH"
} > "$TMP_UWSM"
sudo install -Dm644 "$TMP_UWSM" /usr/share/uwsm/env.d/10-hexciri
rm -f "$TMP_UWSM"
info "Installed: /usr/share/uwsm/env.d/10-hexciri"

# --- Verify placement ---

step "Verifying placement"
[ -x "$HEXCIRI_PATH/bin/hexciri-launch-shell" ] || die "missing: $HEXCIRI_PATH/bin/hexciri-launch-shell"
[ -f "$HEXCIRI_PATH/shell/shell.qml" ] || die "missing: $HEXCIRI_PATH/shell/shell.qml"
hyprlua_ok "$HEXCIRI_PATH/default/hypr/hexciri.lua" || die "missing or corrupt: $HEXCIRI_PATH/default/hypr/hexciri.lua (empty/truncated, or no helpers require; Hyprland requires it at hyprland.lua:17, without it the next boot trips emergency mode with no binds)"
[ -x "$HEXCIRI_PATH/bin/hexciri-restart-hyprctl" ] || die "missing: $HEXCIRI_PATH/bin/hexciri-restart-hyprctl (the installer reloads Hyprland after placement, 2026-11-24)" 
[ -f "$HEXCIRI_PATH/default/hypr/hexciri-compat.lua" ] || die "missing: $HEXCIRI_PATH/default/hypr/hexciri-compat.lua"
bootstrap_ok "$HEXCIRI_PATH/default/hypr/bootstrap.lua" || die "missing or corrupt: $HEXCIRI_PATH/default/hypr/bootstrap.lua (empty/truncated; Hyprland dofiles it first, without it the next boot trips emergency mode with no binds)"
[ -f "$HEXCIRI_PATH/default/hypr/bindings/hexciri.lua" ] || die "missing: $HEXCIRI_PATH/default/hypr/bindings/hexciri.lua (Hexciri custom binds, monocle cycle / Brave incognito / Messenger / screen record)"
grep -q 'require("default.hypr.bindings.hexciri")' "$HEXCIRI_PATH/default/hypr/hexciri.lua" || die "placed hexciri.lua does not require default.hypr.bindings.hexciri (the custom binds file is never executed, Super+Ctrl+S Settings / Super+Shift+S web search / Super+Shift+C calculator will not register; 2026-11-24)"
binds_chain_ok "$HEXCIRI_PATH" || die "binds chain broken in placed tree (Super+Space apps / Super+Alt+Space menu will not register; the fork passed the pre-placement guard, so placement itself lost a file)"
[ -f "$HEXCIRI_PATH/default/hypr/apps/hexciri.lua" ] || die "missing: $HEXCIRI_PATH/default/hypr/apps/hexciri.lua (Hexciri custom window rules, TUI float / mpv+imv opacity)"
[ -f "$HEXCIRI_PATH/bin/hexciri-compat.sh" ] || die "missing: $HEXCIRI_PATH/bin/hexciri-compat.sh"
[ -f "$HOME/.config/hypr/hyprland.lua" ] || die "missing: $HOME/.config/hypr/hyprland.lua"
if grep -q 'default\.hypr\.omarchy' "$HOME/.config/hypr/hyprland.lua"; then
  printf 'ERROR: placed ~/.config/hypr/hyprland.lua still requires default.hypr.omarchy, this trips Hyprland emergency mode at boot\n' >&2
  exit 1
fi
grep -q 'default\.hypr\.hexciri' "$HOME/.config/hypr/hyprland.lua" || die "placed ~/.config/hypr/hyprland.lua does not require default.hypr.hexciri"
info "Verified: placed hyprland.lua requires default.hypr.hexciri, not default.hypr.omarchy"
[ -f "$HOME/.config/hexciri/shell.json" ] || die "missing: $HOME/.config/hexciri/shell.json"
[ -d "$HEXCIRI_PATH/themes" ] || die "missing: $HEXCIRI_PATH/themes"
THEME_COUNT="$(find "$HEXCIRI_PATH/themes" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
[ "$THEME_COUNT" -ge 1 ] || die "no themes found under $HEXCIRI_PATH/themes"
info "Themes installed: $THEME_COUNT"
grep -q 'hexciri-compat' "$HEXCIRI_PATH/default/hypr/hexciri.lua" || die "compat require missing from installed default/hypr/hexciri.lua"
# Boot-path test (2026-11-24, Devi: hyprctl reload fixed emergency mode,
# the file was present): placement verified existence, never what
# Hyprland itself sees. Reproduce the exact require: dofile bootstrap
# (sets package.path), then search default.hypr.hexciri in it.
hypr_searchpath_ok || die "hyprland lua searchpath: default.hypr.hexciri does not resolve after dofile bootstrap.lua (see above; Hyprland will trip emergency mode at boot, run: hyprctl reload)"
grep -q 'default/hypr/bootstrap.lua' "$HOME/.config/hypr/hyprland.lua" || die "placed ~/.config/hypr/hyprland.lua does not dofile default/hypr/bootstrap.lua (package.path is never set, requires fail)"
grep -q '/usr/share/omarchy' "$HOME/.config/hypr/hyprland.lua" && die "placed ~/.config/hypr/hyprland.lua still references /usr/share/omarchy in a dofile line"
grep -q 'hexciri-compat.sh' "$HEXCIRI_PATH/bin/hexciri-launch-shell" || die "compat source missing from installed bin/hexciri-launch-shell"
if [ -f "$HEXCIRI_PATH/default/bash/env-bootstrap" ]; then
  grep -q 'hexciri-compat.sh' "$HEXCIRI_PATH/default/bash/env-bootstrap" || die "compat source missing from installed default/bash/env-bootstrap"
  info "Verified: compat source present in env-bootstrap"
else
  warn "Installed env-bootstrap not found, skipping that compat check. Profile and uwsm env files still set HEXCIRI_PATH."
fi
bash -n "$HEXCIRI_PATH/bin/hexciri-launch-shell" || die "bash -n failed on installed hexciri-launch-shell"
bash -n "$HEXCIRI_PATH/bin/hexciri-compat.sh" || die "bash -n failed on installed hexciri-compat.sh"
PLACED_BAD="$(find "$HEXCIRI_PATH" "$HOME/.config/hexciri" -iname '*omarchy*' -print 2>/dev/null || true)"
if [ -n "$PLACED_BAD" ]; then
  printf 'ERROR: files or dirs named omarchy remain in the placed tree:\n%s\n' "$PLACED_BAD" >&2
  exit 1
fi
info "PASS: no file or dir named omarchy under $HEXCIRI_PATH or ~/.config/hexciri"

# No leftover omarchy-* command references in the placed Hyprland Lua: the
# first live boot showed autostart calling omarchy-hyprland-monitor-watch
# after the rename, because no rule matched omarchy-*. Warn, do not die:
# a comment mentioning an omarchy-* command is harmless, a real call is not.
# Dinner audit: scan QML and the menu jsonc too, not just Lua. The QML
# menu trigger and menu rows call hexciri-* commands the same way.
# The compat alias map in hexciri-compat.lua intentionally names omarchy-*
# commands (["omarchy-shell"] = "hexciri-shell"), so it is excluded here;
# matches go to the fork detail log, screen gets one summary line only
# (2026-11-24, Devi: 90% of the update output is spam).
LEFTOVER_OMARCHY_CMDS="$(grep -rInE 'omarchy-[a-z0-9]+' "$HEXCIRI_PATH/default/hypr" "$HOME/.config/hypr" "$HEXCIRI_PATH/shell" "$HEXCIRI_PATH/default/hexciri" 2>/dev/null | grep -v 'omarchy:' | grep -v 'hexciri-compat.lua' || true)"
if [ -n "$LEFTOVER_OMARCHY_CMDS" ]; then
  _om_count="$(printf '%s\n' "$LEFTOVER_OMARCHY_CMDS" | wc -l | tr -d ' ')"
  printf '%s\n' "$LEFTOVER_OMARCHY_CMDS" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  warn "omarchy-* references remain in placed Hyprland Lua / shell / menu: $_om_count (full list: ${FORK_LOG:-/tmp/hexciri-install-fork.log})"
else
  info "PASS: no omarchy-* command references in placed Hyprland Lua / shell / menu"
fi
unset LEFTOVER_OMARCHY_CMDS

# Every hexciri-* command the forked tree tries to run must exist in the
# installed bin/ or on PATH, or login shows "App failure, Command not found"
# popups from uwsm-app. Dinner audit: this used to scan autostart.lua only,
# which is how the capture-*, system-*, hyprland-window-* and menu helper
# gaps survived. Scan every placed Lua, QML and jsonc file now, so a missing
# bin script is caught here at install time instead of as a popup at login.
# herdr is deliberately excluded: autostart starts it via systemd-run and a
# missing herdr fails silently, it is out of Phase 1 scope. install-* /
# install-*/remove-* are NOT excluded any more (2026-11-24): the Install /
# Remove menu rows are back, so their bins must exist like any other.
if [ -d "$HEXCIRI_PATH" ]; then
  _scan_present=0; _scan_missing=0
  fork_detail "command scan: per-command detail lives here, screen shows one summary line only (2026-11-24, Devi: 90% of the update output is spam)"
  for _cmd in $(grep -rIhoE 'hexciri-[a-z0-9-]+' "$HEXCIRI_PATH/default" "$HEXCIRI_PATH/shell" "$HEXCIRI_PATH/bin" "$HOME/.config/hypr" 2>/dev/null | sort -u); do
    # Trailing-dash tokens are string fragments from dynamic
    # concatenations ("hexciri-agent-" .. x in helpers.lua), not commands.
    case "$_cmd" in *- ) continue ;; esac
    case "$_cmd" in
      hexciri-channel-* | hexciri-mirror-* | hexciri-keyring-* | hexciri-upgrade-*) continue ;;
      hexciri-compat) continue ;;
      # Not commands, so do not warn for them: hexciri-weather is a CLI
      # group (its subcommands are weather-icon/location/status),
      # hexciri-tzupdate and hexciri-wheel are sudoers filenames in
      # comments, hexciri-webapp-handler bare is a regex pattern in the
      # menu jsonc (real handlers are -hey/-zoom), hexciri-windows-vm
      # is the Docker/KVM VM manager, out of Phase 1 scope.
      # Scan false positives, 2026-11-23: the grep token also matches
      # lock filenames (theme-set-retint.lock), package names in a
      # comment (themes-intros/loops, Omarchy-repo packages, not Arch),
      # a runtime dir (theme-sync; the real toggle is
      # toggle-theme-sync), temp-file suffixes (.hexciri-tmp), a dynamic
      # concatenation ("hexciri-toggle-" .. toggle in helpers.lua:249),
      # and a modprobe conf filename (hexciri-toprow.conf; the real
      # command is device-keyboard-toprow). None is a bin, so there is
      # nothing to add to is_allowed_bin for them.
      hexciri-weather | hexciri-tzupdate | hexciri-wheel | hexciri-webapp-handler | hexciri-windows-vm) continue ;;
      hexciri-theme-set-retint | hexciri-themes-intros | hexciri-themes-loops | hexciri-theme-sync | hexciri-tmp | hexciri-toggle- | hexciri-toprow) continue ;;
      # lifecycle-dispatch is deliberately not copied: it is a no-op on x86
      # (upstream docs/lifecycle-dispatch.md, only Apple Silicon registers
      # a package), and its callers guard it with command -v.
      hexciri-lifecycle-dispatch) continue ;;
      # More filename false positives, 2026-11-24: a log filename
      # (/tmp/hexciri-battlenet-installer.log) and a browser policy JSON
      # filename (hexciri-extensions.json), neither is a command. Phase 2
      # adds two more: hexciri-tools is the mise config filename
      # (/etc/mise/conf.d/hexciri-tools.toml), hexciri-nyx is the GitHub
      # codeload tarball top dir, neither is a command.
      hexciri-battlenet-installer | hexciri-extensions | hexciri-tools | hexciri-nyx) continue ;;
    esac
    if [ -x "$HEXCIRI_PATH/bin/$_cmd" ] || command -v "$_cmd" >/dev/null 2>&1; then
      _scan_present=$((_scan_present + 1))
      fork_detail "  forked-tree command present: $_cmd"
    else
      _scan_missing=$((_scan_missing + 1))
      fork_detail "  forked tree calls $_cmd but it is not installed"
    fi
  done
  unset _cmd
  if [ "$_scan_missing" -gt 0 ]; then
    warn "command scan: $_scan_present present, $_scan_missing called-but-not-installed (full list: ${FORK_LOG:-/tmp/hexciri-install-fork.log}; install/remove rows are verified separately by the menu audit)"
  else
    info "command scan: $_scan_present present, 0 missing"
  fi
  unset _scan_present _scan_missing
fi
# Hyprland global shortcuts: without this file every menu/panel bind falls
# back to a spawned command, which is how Super+Space died on the first boot.
[ -f "$HEXCIRI_PATH/default/hexciri/shortcuts" ] || die "missing: default/hexciri/shortcuts, every menu/panel bind is dead without it"
[ -f "$HEXCIRI_PATH/default/i18n/en/shell.json" ] || die "missing: default/i18n/en/shell.json, clock popup shows literal keys"
[ -d "$HEXCIRI_PATH/default/themed" ] || die "missing: default/themed, theme-set-templates generates nothing"
# Super+Space (apps) and Super+Alt+Space (menu) go through the shortcuts file twice: the shell QML reads it
# to register Hyprland global shortcuts, and helpers.lua reads it to decide
# whether a bind dispatches globally or spawns a command. If either reader
# points at a path that does not exist, every menu/panel bind is silently
# dead. Fail the install here instead of at first keypress.
for _reader in "$HEXCIRI_PATH/shell/shell.qml" "$HEXCIRI_PATH/default/hypr/helpers.lua"; do
  _spath="$(grep -o '/default/[^"]*shortcuts' "$_reader" 2>/dev/null | head -1 || true)"
  if [ -n "$_spath" ] && [ ! -f "$HEXCIRI_PATH$_spath" ]; then
    die "shortcuts path in $_reader does not exist: $HEXCIRI_PATH$_spath"
  fi
done
unset _reader _spath

# Global-shortcut appid agreement: Hyprland dispatch is appid:name.
# helpers.lua + gestures.lua dispatch "omarchy:menu.root" etc., so the shell
# must register GlobalShortcut appid "omarchy", not "hexciri". A mismatch
# silently kills every menu / panel / ipc bind (Super+Space apps,
# Super+Alt+Space menu, Super+K cheatsheet) while launch binds still work.
grep -q 'appid: "omarchy"' "$HEXCIRI_PATH/shell/shell.qml" || die "GlobalShortcut appid is not omarchy in installed shell.qml, menu/apps/cheatsheet global shortcuts will match nothing"
grep -q 'dsp.global("omarchy:"' "$HEXCIRI_PATH/default/hypr/helpers.lua" || die "helpers.lua does not dispatch omarchy: global shortcuts, menu/apps/cheatsheet will match nothing"
info "PASS: GlobalShortcut appid omarchy agrees with helpers.lua omarchy: dispatch"

# Menu / dock / terminal / file manager essentials: Super+Space, Super+Alt+Space,
# Super+Return and Super+Shift+F all go through these.
for _bin in hexciri hexciri-menu hexciri-shell hexciri-launch-terminal hexciri-launch-files hexciri-launch-files-cwd hexciri-done hexciri-restart-terminal hexciri-update hexciri-update-hexciri hexciri-update-system-pkgs hexciri-update-mise hexciri-mise-install hexciri-mise-default-tools hexciri-update-available; do
  [ -x "$HEXCIRI_PATH/bin/$_bin" ] || die "missing bin (Super+Space apps / Super+Alt+Space menu / update will fail): $_bin"
done
unset _bin
# Menu audit 2026-11-23: every bin a kept menu row / panel calls must exist.
# Bare "system" (not system-*) was the System power rows' failure, "dock"
# the Appearance > Dock rows', "dns" the Setup > Network > DNS rows',
# "state" is called by hexciri-system itself, monitor-state + display-
# text-size feed the display panel's scale, network-* feeds the network
# panel, apply-lock writes the lock PAM file, setup-* are the Setup
# wizards, pkg-add/pkg-missing are their pacman primitives.
for _bin in hexciri-system hexciri-dock hexciri-dns hexciri-state hexciri-setup-git hexciri-setup-hostname hexciri-setup-keyboard hexciri-setup-input hexciri-setup-security-fingerprint hexciri-setup-security-fido2 hexciri-setup-security-sshd hexciri-setup-security-ssh-agent hexciri-sudo-passwordless hexciri-security-functions hexciri-apply-lock hexciri-pkg-add hexciri-pkg-missing hexciri-monitor-state hexciri-display-text-size hexciri-network-status hexciri-network-band hexciri-network-wifi-connected hexciri-network-captive-portal hexciri-network-password hexciri-network-qr hexciri-network-speedtest hexciri-region hexciri-font-list hexciri-font-current hexciri-font-set hexciri-font-maple-cn-present hexciri-show-logo hexciri-show-done hexciri-file-select hexciri-input-method hexciri-git-url-check hexciri-disk-speedtest hexciri-kernel hexciri-language hexciri-locale-session hexciri-locale-generate hexciri-refresh-shell hexciri-refresh-tmux hexciri-refresh-hyprsunset hexciri-refresh-applications hexciri-refresh-config hexciri-device-touchpad hexciri-device-touchscreen hexciri-theme-set-browser-policy hexciri-toggle hexciri-dictation hexciri-default-dictation hexciri-theme-ansi; do
  [ -x "$HEXCIRI_PATH/bin/$_bin" ] || die "missing bin (menu audit 2026-11-23, a kept menu row or panel calls it): $_bin"
done
unset _bin
[ -f "$HEXCIRI_PATH/install/helpers/browser-policy.sh" ] || die "missing: install/helpers/browser-policy.sh, theme-set-browser fails on every theme switch"
[ -f "$HEXCIRI_PATH/install/helpers/as-root.sh" ] || die "missing: install/helpers/as-root.sh, theme-set-browser fails on every theme switch"
[ -f "$FORK_OUT/etc/sudoers.d/hexciri-theme-browser" ] || die "missing: fork etc/sudoers.d/hexciri-theme-browser, theme-set-browser falls back to pkexec"
grep -q '/usr/share/hexciri/bin/hexciri-theme-set-browser-policy' "$FORK_OUT/etc/sudoers.d/hexciri-theme-browser" || die "sudoers hexciri-theme-browser does not name /usr/share/hexciri/bin/hexciri-theme-set-browser-policy"
grep -q 'HEXCIRI_PATH="/usr/share/hexciri"' "$HEXCIRI_PATH/bin/hexciri-shell" || die "hexciri-shell does not default HEXCIRI_PATH, bar trigger and menu Apps click depend on session env"
grep -q '/usr/share/hexciri/bin/hexciri-shell shell toggle hexciri.menu' "$HEXCIRI_PATH/shell/plugins/menu/BarWidget.qml" || die "bar trigger does not call hexciri-shell by absolute path"
grep -q '/usr/share/hexciri/bin/hexciri-shell hexciri.dock apps' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu apps row does not call hexciri-shell by absolute path"
grep -q 'signal pressed(int button, int modifiers)' "$HEXCIRI_PATH/shell/Ui/WidgetButton.qml" || die "WidgetButton does not forward click modifiers, Shift+right-click settings cannot be told from plain right-click (2026-11-24)"
grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$HEXCIRI_PATH/bin/hexciri-theme-bg-install" || die "theme-bg-install still calls folio, Install > Style > Background opens nothing (folio is not installed in Hexciri v2; 2026-11-24)"
# Learn menu rework 2026-11-24: tmux config must be in the fork (Learn >
# Tmux falls back to it), new Learn rows must be present.
[ -f "$HEXCIRI_PATH/config/tmux/tmux.conf" ] || die "missing: config/tmux/tmux.conf, Learn > Tmux dies with 'Tmux config not found' (2026-11-24)"
for _lrow in '"learn.zed"' '"learn.fish"' '"learn.kitty"' '"learn.quickshell"' '"learn.tmux-keybindings"'; do
  grep -q "$_lrow" "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "Learn row missing from hexciri-menu.jsonc: $_lrow (2026-11-24)"
done
unset _lrow
grep -q 'strata "$@"' "$HEXCIRI_PATH/bin/hexciri-launch-files" || die "launch-files drops its path argument, background folder opens at Strata home instead of the theme backgrounds folder (2026-11-24)"
# Full Install/Remove restore 2026-11-24: every restored row's backing bin
# must be in the fork, plus the data files those bins read at runtime.
for _bin in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-remove-service-1password hexciri-remove-service-dropbox hexciri-remove-service-microsoft hexciri-remove-service-ssh-agent hexciri-remove-service-tailscale hexciri-remove-security-fido2 hexciri-remove-security-sshd hexciri-install-dictation-hex hexciri-install-dictation-superwhisper hexciri-install-dictation-voxtype hexciri-remove-dictation-hex hexciri-remove-dictation-superwhisper hexciri-remove-dictation-voxtype hexciri-install-gaming-xbox-cloud hexciri-install-gaming-xbox-controllers hexciri-remove-gaming-battlenet hexciri-remove-gaming-heroic hexciri-remove-gaming-lutris hexciri-remove-gaming-moonlight hexciri-remove-gaming-xbox-cloud hexciri-remove-gaming-xbox-controllers hexciri-games-retro-install hexciri-games-retro-cores hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-vibes-launch hexciri-games-vibes-copy hexciri-install-chromium-copy-url hexciri-install-chromium-ytdlp hexciri-install-video-decode hexciri-install-camera hexciri-pkg-aur-add hexciri-chromium-add-feature hexciri-chromium-copy-url-host hexciri-chromium-ytdlp-host hexciri-tailscale-receive hexciri-tailscale-send hexciri-install-ai-chatgpt hexciri-install-ai-claude hexciri-install-ai-hermes hexciri-install-ai-openclaw hexciri-install-ai-t3-code hexciri-remove-ai-amp hexciri-remove-ai-antigravity hexciri-remove-ai-chatgpt hexciri-remove-ai-claude hexciri-remove-ai-grok-bot hexciri-remove-ai-hermes hexciri-remove-ai-lm-studio hexciri-remove-ai-ollama hexciri-remove-ai-openclaw hexciri-remove-ai-perplexity hexciri-remove-ai-t3-code hexciri-install-hermes-cli hexciri-install-openclaw-cli hexciri-install-t3code-app hexciri-openclaw-onboard hexciri-launch-openclaw; do
  [ -x "$HEXCIRI_PATH/bin/$_bin" ] || die "missing bin (full Install/Remove restore 2026-11-24, a restored menu row calls it): $_bin"
done
unset _bin
[ -f "$HEXCIRI_PATH/config/chromium-flags.conf" ] || die "missing: config/chromium-flags.conf, install-browser writes flags files Chromium cannot load extensions from"
[ -f "$HEXCIRI_PATH/default/chromium/extensions/copy-url/manifest.json" ] || die "missing: default/chromium/extensions/copy-url, install-browser flags file loads an extension that is not installed"
[ -f "$HEXCIRI_PATH/default/chromium/native-messaging-hosts/com.hexciri.copy_url.json" ] || die "missing: default/chromium/native-messaging-hosts/com.hexciri.copy_url.json, install-chromium-copy-url has no template to fill in"
[ -f "$HEXCIRI_PATH/default/chromium/native-messaging-hosts/com.hexciri.ytdlp.json" ] || die "missing: default/chromium/native-messaging-hosts/com.hexciri.ytdlp.json, install-chromium-ytdlp has no template to fill in"
[ -f "$HEXCIRI_PATH/config/alacritty/alacritty.toml" ] || die "missing: config/alacritty/alacritty.toml, install-terminal alacritty has no config to install"
[ -f "$HEXCIRI_PATH/config/ghostty/config" ] || die "missing: config/ghostty/config, install-terminal ghostty has no config to install"
[ -f "$HEXCIRI_PATH/default/alacritty/Alacritty.desktop" ] || die "missing: default/alacritty/Alacritty.desktop, install-terminal alacritty installs without its desktop entry"
[ -f "$HEXCIRI_PATH/config/foot/foot.ini" ] || die "missing: config/foot/foot.ini, install-terminal foot has no config to install"
[ -f "$HEXCIRI_PATH/applications/foot.desktop" ] || die "missing: applications/foot.desktop, install-terminal foot installs without its desktop entry"
# Install > Terminal is four rows (2026-11-24, Devi: alacritty, kitty,
# ghostty, foot, not just two): the placed install-terminal must map
# every one to a desktop entry, or its row installs the package and
# then copies nothing. Ghostty needs no custom desktop file (it uses
# the shipped com.mitchellh.ghostty.desktop id); the other three copy
# theirs from the placed tree, which is why applications/ is placed.
for _term in alacritty foot ghostty kitty; do
  grep -q "^$_term) desktop_id=" "$HEXCIRI_PATH/bin/hexciri-install-terminal" || die "install-terminal has no desktop entry for $_term, Install > Terminal > $_term installs a terminal with no desktop entry"
done
unset _term
# Herdr stays out (2026-11-24 correction): no Herdr bin in the fork, no
# Herdr row in the menu. The Learn > Herdr keybindings row is already
# dead-listed below; this is the Install > AI Herdr row + bin.
[ -x "$HEXCIRI_PATH/bin/hexciri-install-ai-herdr" ] && die "herdr bin in fork, Herdr stays out (2026-11-24 correction)"
grep -q '"install.ai.herdr"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" && die "install.ai.herdr row present, Herdr stays out (2026-11-24 correction)"
# Foot is an option, Kitty stays default: the default-terminal getter
# must still report kitty for kitty.desktop (checked below), and the
# trim must not remove a user-installed Foot. The trim list lives in
# this installer, not the fork, so sim24 checks it on the patched file.
[ -f "$HEXCIRI_PATH/default/voxtype/config.toml" ] || die "missing: default/voxtype/config.toml, install-dictation-voxtype has no config to install"
[ -f "$HEXCIRI_PATH/default/systemd/user/hexciri-tailscale-receive.service" ] || die "missing: default/systemd/user/hexciri-tailscale-receive.service, install-service-tailscale enables a unit that is never installed"
grep -q 'ExecStart=/usr/share/hexciri/bin/hexciri-tailscale-receive' "$HEXCIRI_PATH/default/systemd/user/hexciri-tailscale-receive.service" || die "tailscale unit ExecStart is not /usr/share/hexciri/bin/hexciri-tailscale-receive, the Taildrop receiver never starts"
grep -q 'default/systemd/user/hexciri-tailscale-receive.service' "$HEXCIRI_PATH/bin/hexciri-install-service-tailscale" || die "install-service-tailscale does not install the Taildrop unit before enabling it"
grep -q 'rm -f ~/.config/systemd/user/hexciri-tailscale-receive.service' "$HEXCIRI_PATH/bin/hexciri-remove-service-tailscale" || die "remove-service-tailscale does not remove the Taildrop unit file"
for _row in '"install.browser"' '"install.terminal"' '"install.terminal.alacritty"' '"install.terminal.kitty"' '"install.terminal.ghostty"' '"install.terminal.foot"' '"install.ai"' '"install.ai.amp"' '"install.ai.antigravity"' '"install.ai.chatgpt"' '"install.ai.claude"' '"install.ai.grok-bot"' '"install.ai.hermes"' '"install.ai.lm-studio"' '"install.ai.ollama"' '"install.ai.openclaw"' '"install.ai.perplexity"' '"install.ai.t3-code"' '"install.editor"' '"install.service"' '"install.development"' '"install.gaming.vibes"' '"install.gaming.xbox-cloud"' '"install.gaming.retro-launcher"' '"remove.ai"' '"remove.ai.amp"' '"remove.ai.antigravity"' '"remove.ai.chatgpt"' '"remove.ai.claude"' '"remove.ai.grok-bot"' '"remove.ai.hermes"' '"remove.ai.lm-studio"' '"remove.ai.ollama"' '"remove.ai.openclaw"' '"remove.ai.perplexity"' '"remove.ai.t3-code"' '"remove.service"' '"remove.development"' '"remove.dictation"' '"remove.security.fido2"' '"remove.security.sshd"' '"remove.gaming.battlenet"' '"remove.gaming.heroic"' '"remove.gaming.lutris"' '"remove.gaming.moonlight"' '"remove.gaming.vibes"' '"setup.default.terminal.foot"'; do
  grep -q "$_row" "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "restored menu row missing from hexciri-menu.jsonc: $_row"
done
unset _row
# No hard defaults in the restored rows: folio and nautilus are not
# installed in Hexciri v2, so no restored row or bin may call them.
grep -q 'folio' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" && die "restored menu still references folio, which is not installed in Hexciri v2"
for _rb in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-retro-install hexciri-install-ai-chatgpt hexciri-install-ai-claude hexciri-install-ai-hermes hexciri-install-ai-openclaw hexciri-install-ai-t3-code hexciri-remove-ai-amp hexciri-remove-ai-antigravity hexciri-remove-ai-chatgpt hexciri-remove-ai-claude hexciri-remove-ai-grok-bot hexciri-remove-ai-hermes hexciri-remove-ai-lm-studio hexciri-remove-ai-ollama hexciri-remove-ai-openclaw hexciri-remove-ai-perplexity hexciri-remove-ai-t3-code hexciri-install-hermes-cli hexciri-install-openclaw-cli hexciri-install-t3code-app hexciri-launch-openclaw hexciri-openclaw-onboard; do
  grep -qE '(^|[^a-z-])folio([^a-z-]|$)' "$HEXCIRI_PATH/bin/$_rb" && die "restored bin $_rb still calls folio, which is not installed in Hexciri v2"
done
unset _rb
# Dead menu rows must be gone from the forked jsonc, not just uncallable.
# NOTE 2026-11-24: '"install.' / '"remove.' must NOT be in this list.
# b0eed823 restored Install/Remove (26 install.* + 20 remove.* rows, all
# with backing bins, verified in sim6), and the broad patterns matched the
# first restored row and killed the install with
#   ERROR: dead menu row still present in hexciri-menu.jsonc: "install.
# Only the subtrees the menu audit actually drops are dead here: the
# _drop_prefix / _drop_exact sets in the menu patch above (Herdr, windows,
# preinstalls, factory-reset, sudoless-docker, docker-dbs, emacs).
# The full restore 2026-11-24 took services, development, terminals,
# browsers and dictation OUT of this list, and the AI/Foot correction
# took AI (except Herdr) and install.terminal.foot out too: those rows
# are live now.
for _dead in '"install.ai.herdr"' '"install.windows"' '"install.preinstalls"' '"install.development.docker-dbs"' '"install.editor.emacs"' '"remove.windows"' '"remove.preinstalls"' '"remove.factory-reset"' '"remove.security.sudoless-docker"' '"update.channel' '"update.omarchy"' '"system.screensaver"' '"learn.herdr-keybindings"' '"learn.neovim"' '"learn.community"' '"setup.default.editor.neovim"' '"setup.security.sudoless-docker"' '"appearance.unlock"'; do
  if grep -q "$_dead" "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc"; then
    die "dead menu row still present in hexciri-menu.jsonc: $_dead"
  fi
done
unset _dead
# Real dead-row invariant: every kept install./remove. row's action must
# name bins that exist in $HEXCIRI_PATH/bin. A row whose action calls a
# missing bin is dead even if its key looks live; a header row (no
# action) is kept only while it has kept children, which the menu patch
# already enforces. This is the check the broad grep patterns were
# standing in for, and it passes on the restored Install/Remove rows.
python3 - "$HEXCIRI_PATH" <<'PYEOF' || die "dead install/remove menu row: an action calls a bin that is not installed (see above)"
import os, re, sys
root = sys.argv[1]
menu = root + "/default/hexciri/hexciri-menu.jsonc"
bin_dir = root + "/bin"
have = set(os.listdir(bin_dir)) if os.path.isdir(bin_dir) else set()
dead = []
with open(menu) as f:
    for line in f:
        m = re.match(r'\s*"((?:install|remove)(?:\.[^"]+)?)"\s*:', line)
        if not m:
            continue
        a = re.search(r'"action"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
        if not a:
            continue
        toks = re.findall(r'hexciri-[a-z0-9-]+', a.group(1))
        missing = [t for t in toks if t not in have]
        if missing:
            dead.append("%s calls missing %s" % (m.group(1), ",".join(missing)))
if dead:
    for d in dead:
        print("  dead menu row: " + d)
    sys.exit(1)
print("  install/remove menu rows: all actions resolve to installed bins")
PYEOF
# Regression verification, 2026-11-23: socat is hexciri-shell's IPC
# transport (menu Apps, bar trigger, theme-set applyTheme, lock, background
# picker all go through it); icons/ feeds Appearance > Icons and
# theme-set-icons; logo.txt / icon.txt feed show-logo and About branding;
# default-terminal must report foot for foot.desktop, or the settings menu
# shows Foot when Kitty is the default.
command -v socat >/dev/null 2>&1 || die "socat not installed, hexciri-shell IPC (menu Apps, bar trigger, theme-set applyTheme, lock, background picker) fails without it"
[ -d "$HEXCIRI_PATH/icons" ] || die "missing: icons/, Appearance > Icons has no sets and theme-set-icons draws nothing"
# Image-picker runtime deps (2026-11-23): hexciri-menu-images draws every
# image-picker thumbnail with vipsthumbnail (libvips) and ffmpegthumbnailer
# for videos, and hexciri-icons-preview draws set previews with rsvg-convert
# (librsvg). All three are runtime invariants; without them the picker
# opens with zero rows and Appearance > Icons loads nothing.
for _pickdep in vipsthumbnail ffmpegthumbnailer rsvg-convert; do
  command -v "$_pickdep" >/dev/null 2>&1 || die "missing: $_pickdep, image picker (Appearance > Icons, background picker) draws no thumbnails without it"
done
unset _pickdep
# icons-list must actually list the three built-in sets, not just have the
# directory present: run it for real. A list that prints only Original
# means the fork path is wrong and the switcher has nothing to offer.
_icons_list="$(HEXCIRI_PATH="$HEXCIRI_PATH" "$HEXCIRI_PATH/bin/hexciri-icons-list" 2>/dev/null || true)"
for _set in Arcade Original Papercraft; do
  printf '%s\n' "$_icons_list" | grep -qx "$_set" || die "hexciri-icons-list does not list $_set (got: $_icons_list), Appearance > Icons will load nothing"
  [ -f "$HEXCIRI_PATH/icons/$(printf '%s' "$_set" | tr '[:upper:]' '[:lower:]')/preview.png" ] || warn "icons/$_set has no preview.png, the picker draws it instead (needs rsvg-convert)"
done
unset _icons_list _set
[ -f "$HEXCIRI_PATH/logo.txt" ] || die "missing: logo.txt, hexciri-show-logo fails"
[ -f "$HEXCIRI_PATH/icon.txt" ] || die "missing: icon.txt, About branding reset fails"
grep -q 'foot.desktop) echo "foot"' "$HEXCIRI_PATH/bin/hexciri-default-terminal" || die "hexciri-default-terminal getter still corrupted, settings show Foot for Kitty"
grep -q 'kitty.desktop) echo "kitty"' "$HEXCIRI_PATH/bin/hexciri-default-terminal" || die "hexciri-default-terminal getter has no kitty arm"
[ -L "$HOME/.local/bin/hexciri" ] || die "missing symlink ~/.local/bin/hexciri, hexciri will be command not found in terminals"
bash -lc 'command -v hexciri' >/dev/null 2>&1 || warn "hexciri not on PATH in a fresh login shell, check ~/.bashrc / fish conf.d PATH lines"
grep -q '"update.hexciri"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu Update > Hexciri row missing (Phase 2 update)"
grep -q '"settings".*hexciri-launch-settings' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" && die "menu Settings row still present in hexciri-menu.jsonc (removed 2026-11-24, Settings opens via Super+Ctrl+S / launcher only)"
grep -q '"install.style.font.maple"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu Install > Style > Font > Maple Mono CN row missing (2026-11-24)"
grep -q 'hexciri-font-maple-cn-present' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu Maple Mono CN row does not use hexciri-font-maple-cn-present as its disabled check (reinstall fix 2026-11-24)"
grep -q '<string>JetBrainsMono Nerd Font</string>' "$HEXCIRI_PATH/bin/hexciri-font-set" || die "hexciri-font-set missing the system-default second match block (Maple Mono NF fix 2026-11-24)"
grep -q 'fc-list :spacing=90' "$HEXCIRI_PATH/bin/hexciri-font-list" || die "hexciri-font-list missing the dual-width (spacing 90) query (PR #16025)"
grep '"update.hexciri"' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" | grep -q 'hexciri-update' || die "menu Update > Hexciri row does not call hexciri-update"
grep -q 'eos-update --aur' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs does not call eos-update --aur"
grep -q 'hexciri-update-hexciri' "$HEXCIRI_PATH/bin/hexciri-update" || die "hexciri-update does not call hexciri-update-hexciri"
grep -q 'hexciri-update-pkg-prune' "$HEXCIRI_PATH/bin/hexciri-update" || die "hexciri-update does not call hexciri-update-pkg-prune (Prune package cache, dropped with the snapshot step 2026-11-24)"
grep -q 'paccache -rk2' "$HEXCIRI_PATH/bin/hexciri-update-pkg-prune" || die "hexciri-update-pkg-prune does not run paccache -rk2"
grep -q 'No orphaned packages' "$HEXCIRI_PATH/bin/hexciri-update-orphan-pkgs" || die "hexciri-update-orphan-pkgs has no section when there are no orphans"
grep -q 'All tools are up to date' "$HEXCIRI_PATH/bin/hexciri-update-mise" || die "hexciri-update-mise has no quiet one-line status"
grep -q 'Packages not in AUR: thpm' "$HEXCIRI_PATH/bin/hexciri-update-aur-pkgs" || die "hexciri-update-aur-pkgs does not suppress the thpm AUR warning"
grep -q 'Updating Hexciri' "$HEXCIRI_PATH/bin/hexciri-update-hexciri" || die "hexciri-update-hexciri has no themed Updating Hexciri header"
grep -q 'Hexciri installer sha: installed' "$HEXCIRI_PATH/bin/hexciri-update-hexciri" && die "hexciri-update-hexciri still prints full installer shas on screen"
grep -q 'Hexciri nyx synced with git' "$HEXCIRI_PATH/bin/hexciri-update-hexciri" && die "hexciri-update-hexciri still prints the noisy git sync line"
grep -q 'Hexciri is up to date' "$HEXCIRI_PATH/bin/hexciri-update-hexciri" || die "hexciri-update-hexciri has no short up-to-date status line"
grep -q 'HEXCIRI_UPDATE_UNATTENDED=1' "$HEXCIRI_PATH/bin/hexciri-update" || die "hexciri-update does not go unattended after the start confirm (yay inside eos-update would prompt [Y/n])"
grep -q 'System packages are up to date' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs has no quiet up-to-date status line"
grep -q 'AUR packages are up to date' "$HEXCIRI_PATH/bin/hexciri-update-aur-pkgs" || die "hexciri-update-aur-pkgs has no quiet up-to-date status line"
for _sp in hexciri-update-pkg-prune hexciri-update-orphan-pkgs hexciri-update-mise hexciri-update-aur-pkgs hexciri-update-restart; do grep -qx 'echo' "$HEXCIRI_PATH/bin/$_sp" && die "$_sp still prints a bare blank line (update section spacing, 2026-11-24: the header's leading newline is the only separator)"; done
grep -q '_restart_needs_blank' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart has no conditional top blank (update section spacing, 2026-11-24)"
grep -q 'Hyprland config reloaded (hyprctl reload)' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not reload Hyprland after the shell restart (emergency mode returns after every update, 2026-11-24)"
grep -q 'hexciri-shell hexciri.system-update refresh' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not refresh the system-update widget after an update (stock icon stays on up to 6h, 2026-11-24)"
grep -q 'GlobalShortcuts registered' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not re-register GlobalShortcuts after the last Hyprland reload (Super+Space / Super+Alt+Space stay dead after an update, 2026-11-24)"
grep -q 'timeout 10 git -C "$_checkout" fetch --quiet' "$HEXCIRI_PATH/bin/hexciri-update-available" || die "hexciri-update-available does not fetch before counting git behind (stale ref keeps the update icon on, 2026-11-24)"
grep -q 'connect-timeout 10 --retry 1' "$HEXCIRI_PATH/bin/hexciri-update-aur-pkgs" || die "hexciri-update-aur-pkgs still probes the AUR with a 30s x3 curl (up to ~99s before yay starts, 2026-11-24)"
grep -q 'already updated by eos-update --aur, skipping' "$HEXCIRI_PATH/bin/hexciri-update-aur-pkgs" && die "hexciri-update-aur-pkgs still prints the noisy skipping line"
[ -x "$HEXCIRI_PATH/bin/hexciri-pkg-aur-accessible" ] || die "hexciri-pkg-aur-accessible missing from fork (hexciri-update-aur-pkgs calls it, 2026-11-24 live log: command not found)"
grep -q 'HEXCIRI_UPDATE_REEXECED' "$HEXCIRI_PATH/bin/hexciri-update" || die "hexciri-update does not skip the second confirm on a self-update re-exec"
grep -q '_upgraded' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs does not count real upgrades (it claimed updated (1) after nothing to do)"
grep -q 'mirror DB lag' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs still claims up to date when checkupdates counted updates pacman skipped (zxing-cpp 3.2.0-1, 2026-11-24)"
grep -q 'hexciri-update-pacman -Syy' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs has no forced re-sync retry for the checkupdates/pacman DB race (zxing-cpp, 2026-11-24)"
grep -q 'endeavouros repo not found' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs has no endeavouros-repo check (EOS pkgs must still update via pacman)"
[ -f "$HEXCIRI_PATH/.fork-fingerprint" ] || die "fork fingerprint missing, hexciri update cannot tell if the fork changed"
[ -f "$HEXCIRI_PATH/.patch-fingerprint" ] || die "patch fingerprint missing, hexciri update cannot tell if the fork patches changed"
[ -f "$HEXCIRI_PATH/.provision-fingerprint" ] || die "provision fingerprint missing, hexciri update cannot tell if the system-config steps changed"
[ -f "$HEXCIRI_PATH/.system-fingerprint" ] || die "system fingerprint missing, hexciri update cannot tell if the provisioning steps changed"
grep -q 'upstream_fingerprint' "$INSTALLER_DIR/install.sh" || die "installer has no fork cache (upstream_fingerprint missing)"
grep -q 'patch_fingerprint' "$INSTALLER_DIR/install.sh" || die "installer has no fork cache (patch_fingerprint missing)"
grep -q 'provision_fingerprint' "$INSTALLER_DIR/install.sh" || die "installer has no provision fingerprint (provision_fingerprint missing)"
grep -q 'system_fingerprint' "$INSTALLER_DIR/install.sh" || die "installer has no system fingerprint (system_fingerprint missing)"
grep -q 'hexciri-snapshot create' "$HEXCIRI_PATH/bin/hexciri-update" && die "hexciri-update still calls the snapshot step (dropped 2026-11-24)"
grep -q 'dracut' "$HEXCIRI_PATH/bin/hexciri-update-analyze-logs" || die "hexciri-update-analyze-logs has no dracut scan"
grep -q 'hexciri-theme-ansi green' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "update headers are not theme-matched (no hexciri-theme-ansi call in hexciri-update-system-pkgs)"
grep -q 'hexciri-theme-ansi green' "$HEXCIRI_PATH/bin/hexciri-show-logo" || die "show-logo is not theme-matched (no hexciri-theme-ansi call)"
grep -q "printf '.*hexciri-theme-ansi" "$HEXCIRI_PATH/bin/hexciri-show-done" && die "hexciri-show-done still has a literal \$(hexciri-theme-ansi ...) inside single quotes, it prints literally instead of colouring"
head -1 "$HEXCIRI_PATH/logo.txt" | grep -q '▄███▄' || die "logo.txt is not the HEXCIRI v2 art (Devi's art, first line has ▄███▄)"
grep -q '^ILoveCandy' /etc/pacman.conf || warn "  pacman bars: ILoveCandy NOT set in /etc/pacman.conf, pacman shows the plain bar"
[ -f "$HEXCIRI_PATH/.installer-sha" ] || die "installer sha marker missing, hexciri-update-hexciri cannot tell if the installer changed"
[ -f /etc/mise/conf.d/hexciri-tools.toml ] || warn "  mise tools config missing at /etc/mise/conf.d/hexciri-tools.toml (node/uv/gh lazy declarations)"
info "PASS: menu audit verified (dead rows gone, audit bins present, shell IPC paths absolute)"
info "PASS: update pipeline verified (Update > Hexciri row live, eos-update --aur engine, no snapshot, Hexciri self-update wired, mise tools config present)"
# Dock pinned list (Devi 2026-11-23): Strata, Spotify, Brave Origin, Zed,
# Kitty. hexciri-browser / hexciri-terminal are deliberately NOT pinned,
# they are wrappers for Brave Origin / Kitty and would duplicate them.
for _pin in io.github.lgse.Strata spotify brave-origin dev.zed.Zed kitty; do
  if ! grep -q "\"$_pin\"" "$HOME/.config/hexciri/shell.json"; then
    if [ "${IS_RERUN:-0}" = "1" ]; then
      warn "dock pinned list missing $_pin in ~/.config/hexciri/shell.json (re-run, your dock kept, not fatal)"
    else
      die "dock pinned list missing $_pin in ~/.config/hexciri/shell.json"
    fi
  fi
done
unset _pin
for _dead_pin in folio omacalc omawrite hype monologue cliamp hexciri-browser hexciri-terminal; do
  if grep -q "\"$_dead_pin\"" "$HOME/.config/hexciri/shell.json"; then
    if [ "${IS_RERUN:-0}" = "1" ]; then
      warn "dock pinned list still contains dead/duplicate pin $_dead_pin (re-run, your dock kept, not fatal)"
    else
      die "dock pinned list still contains dead/duplicate pin $_dead_pin"
    fi
  fi
done
unset _dead_pin
info "PASS: dock pinned list checked (Strata, Spotify, Brave Origin, Zed, Kitty)"
[ -f "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" ] || die "missing: default/hexciri/hexciri-menu.jsonc, Super+Alt+Space menu has no routes"
# The menu jsonc must PARSE, not just exist (2026-11-24, Devi: whole
# menu empty after update): the cf3bb1a maple row had bare double quotes
# inside its action string, so MenuModel.js JSON.parse failed on the whole
# file and a fresh shell showed nothingHere. Grep row checks cannot see
# this; parse it exactly like the shell does (full-line // comments +
# trailing commas stripped) and require the 9 root entries.
python3 - "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" <<'PYEOF' || die "hexciri-menu.jsonc does not parse, Super+Alt+Space menu would be empty (see above)"
import json, re, sys
raw = open(sys.argv[1]).read()
stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
try:
    d = json.loads(stripped)
except Exception as e:
    print("menu jsonc parse error: %s" % e)
    sys.exit(1)
for r in ('apps', 'appearance', 'trigger', 'setup', 'install', 'remove', 'update', 'learn', 'system'):
    if r not in d:
        print("menu jsonc missing root entry: %s" % r)
        sys.exit(1)
print("menu jsonc parses: %d entries" % len(d))
PYEOF
if ! grep -rl 'hexciri.menu' "$HEXCIRI_PATH/shell/plugins" --include='manifest.json' >/dev/null 2>&1; then
  warn "no plugin manifest registers hexciri.menu, Super+Alt+Space menu will do nothing"
fi
if ! grep -rl 'hexciri.dock' "$HEXCIRI_PATH/shell/plugins" --include='manifest.json' >/dev/null 2>&1; then
  warn "no plugin manifest registers hexciri.dock, Super+Space apps will do nothing"
fi
info "PASS: placement verified"

fi # end fork + placement guard (minimal re-apply: skipped in provision-only mode)
# Minimal re-apply: system-config steps (browser sudoers, lock PAM,
# SDDM fingerprint/keyring, locale, boot timeout, theme, GTK, EOS
# icon, speedtest, SDDM theme, Strata) run in full mode and in
# --re-apply-provision mode. --re-apply (fork patch) skips them: none
# of their inputs changed, and the staged theme / PAM state is already
# correct for the unchanged theme. Settings, Nyxiri, theme hooks and
# theme-link below are patch-covered, so they run in --re-apply too.
if [ "${REAPPLY:-0}" != "1" ]; then
# --- Browser policy for theme-set-browser + lock PAM ---
# Two post-placement fixes, both best-effort except the sudoers validation:
#  1. hexciri-theme-set-browser failed on every theme switch for four
#     stacked reasons, all fixed here: install/helpers/ was never copied
#     (copy_subsets now copies it), the privileged writer's PACKAGED_PATH
#     still pointed at /usr/bin (rewrite rule now points it at
#     /usr/share/hexciri/bin), the passwordless sudoers rule was never
#     installed (installed below, validated with visudo -cf), and
#     /etc/brave/policies/managed did not exist (the writer only touches
#     dirs that exist, so Brave Origin never got a color.json). The writer
#     runs detached with no TTY, so without the sudoers rule require_root
#     falls through to pkexec and fails silently.
#  2. System > Lock did nothing: the lock plugin needs
#     /etc/pam.d/hexciri-lock-password to exist (passwordPamConfigured is
#     false until it loads, and lock returns "missing-pam"). Omarchy's
#     package installs it; the fork never did. hexciri-apply-lock writes
#     it (plus the fingerprint PAM file when fingers are enrolled).

step "Installing browser-policy sudoers + Brave policy dir (theme-set-browser)"
if [ -f "$FORK_OUT/etc/sudoers.d/hexciri-theme-browser" ]; then
  TMP_SUDOERS="$(mktemp)"
  cp -a "$FORK_OUT/etc/sudoers.d/hexciri-theme-browser" "$TMP_SUDOERS"
  if visudo -cf "$TMP_SUDOERS" >/dev/null 2>&1; then
    sudo install -Dm440 "$TMP_SUDOERS" /etc/sudoers.d/hexciri-theme-browser && info "Installed: /etc/sudoers.d/hexciri-theme-browser (passwordless browser-policy write)" || warn "could not install /etc/sudoers.d/hexciri-theme-browser, theme switch falls back to pkexec"
  else
    warn "sudoers hexciri-theme-browser failed visudo -cf, NOT installed (theme switch falls back to pkexec)"
  fi
  rm -f "$TMP_SUDOERS"
else
  warn "fork etc/sudoers.d/hexciri-theme-browser not found, theme switch falls back to pkexec"
fi
if command -v brave-origin >/dev/null 2>&1; then
  sudo install -d -m 0755 -o root -g root /etc/brave /etc/brave/policies /etc/brave/policies/managed 2>/dev/null && info "Created: /etc/brave/policies/managed (Brave Origin theme color.json goes here)" || warn "could not create /etc/brave/policies/managed, theme-set-browser will skip Brave Origin"
else
  warn "Brave Origin not installed yet, /etc/brave/policies/managed not created (theme-set-browser skips Brave until it is)"
fi

step "Configuring lock screen PAM (System > Lock)"
if [ -x "$HEXCIRI_PATH/bin/hexciri-apply-lock" ]; then
  if sudo "$HEXCIRI_PATH/bin/hexciri-apply-lock" 2>/dev/null; then
    info "Lock PAM configured: /etc/pam.d/hexciri-lock-password"
  else
    warn "hexciri-apply-lock failed (not fatal), System > Lock may return missing-pam until it runs. Run by hand: sudo hexciri-apply-lock"
  fi
else
  warn "hexciri-apply-lock not found, System > Lock will return missing-pam"
fi
[ -f /etc/pam.d/hexciri-lock-password ] || warn "Lock PAM file /etc/pam.d/hexciri-lock-password still missing after apply-lock, System > Lock will return missing-pam until it exists. Run by hand: sudo hexciri-apply-lock"
# --- SDDM fingerprint (login unlock, 2026-11-23) ---
# hexciri_has_fingerprint_reader / hexciri_finger_enrolled (2026-11-24,
# Devi desktop dokoz, no reader: SDDM password login failed while the same
# password worked at a tty, same as Hexciri v1 on vanilla Arch). Fingerprint
# setup must only happen when a reader is actually detected, and a machine
# with no reader must have any stray fingerprint lines stripped, not left
# alone: pam_fprintd in /etc/pam.d/sddm makes SDDM demand a touch it can
# never get, so password login fails at the greeter only. The sysfs USB
# probe (forked hexciri-hw-fingerprint) works before fprintd is installed;
# fprintd-list's exit status is the fallback for non-USB readers (Touch ID
# behind a Secure Enclave): exit 0 means a device answered, non-zero means
# "No devices available".
hexciri_has_fingerprint_reader() {
  if [ -x "$HEXCIRI_PATH/bin/hexciri-hw-fingerprint" ]; then
    "$HEXCIRI_PATH/bin/hexciri-hw-fingerprint" 2>/dev/null && return 0
  fi
  if command -v fprintd-list >/dev/null 2>&1; then
    /usr/bin/fprintd-list "$USER" >/dev/null 2>&1 && return 0
  fi
  return 1
}
hexciri_finger_enrolled() {
  command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'
}
# Fingerprint works for sudo because setup-security-fingerprint writes
# /etc/pam.d/sudo and /etc/pam.d/polkit-1, but it never touched SDDM:
# upstream only configures sudo, polkit and the lock screen, so the login
# screen always asked for a password. SDDM authenticates the user through
# /etc/pam.d/sddm (sddm-greeter is the greeter's own service, not the
# login), so add fingerprint lines there, only when a finger is actually
# enrolled. The order is the fix (2026-11-24, ArchWiki SDDM fingerprint):
# pam_unix FIRST, so a correct password logs in at once and fingerprint
# is never asked for after it; only an empty/wrong password falls through
# to the clamshell gate and then pam_fprintd (press Enter on an empty
# password field to touch the reader). The old Hexciri order (gate +
# pam_fprintd first) demanded a fingerprint AFTER a correct password.
# Repair first: strip any earlier Hexciri SDDM lines, so a rerun fixes a
# machine that already has the broken order instead of skipping it.
# Idempotent, best-effort: without a detected reader (or without an
# enrolled finger) the step strips any stray fingerprint lines instead of
# adding any, so a re-run repairs a no-reader machine.
step "Configuring SDDM fingerprint (login unlock)"
if hexciri_has_fingerprint_reader && hexciri_finger_enrolled; then
  if [ -f /etc/pam.d/sddm ]; then
    _sddm_tmp="$(mktemp)"
    sudo sed -e '/pam_fprintd\.so/d' -e '/hexciri-hw-laptop-closed/d' -e '/try_first_pass likeauth nullok/d' /etc/pam.d/sddm > "$_sddm_tmp" 2>/dev/null || cp /etc/pam.d/sddm "$_sddm_tmp"
    _sddm_out="$(mktemp)"
    # pam_unix success=2 skips the gate line and pam_fprintd; with no gate
    # it skips one line instead.
    _sddm_skip=2
    _sddm_gate=""
    if [ -x "$HEXCIRI_PATH/bin/hexciri-hw-laptop-closed" ]; then
      _sddm_gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/share/hexciri/bin/hexciri-hw-laptop-closed"
    else
      _sddm_skip=1
    fi
    {
      printf '%s\n' "auth      [success=${_sddm_skip} new_authtok_reqd=${_sddm_skip} default=ignore] pam_unix.so try_first_pass likeauth nullok"
      [ -n "$_sddm_gate" ] && printf '%s\n' "$_sddm_gate"
      printf 'auth      sufficient pam_fprintd.so\n'
      cat "$_sddm_tmp"
    } > "$_sddm_out"
    if sudo install -Dm644 "$_sddm_out" /etc/pam.d/sddm; then
      info "SDDM fingerprint: pam_unix first, then gate + pam_fprintd in /etc/pam.d/sddm (password alone logs in, empty-password Enter uses the reader)"
    else
      warn "could not write /etc/pam.d/sddm, SDDM login stays password-only"
    fi
    rm -f "$_sddm_tmp" "$_sddm_out"
    unset _sddm_tmp _sddm_out _sddm_skip _sddm_gate
  else
    warn "/etc/pam.d/sddm not found, SDDM login stays password-only"
  fi
else
  # Repair, not "left alone": no reader, or a reader with nothing enrolled.
  # Any Hexciri fingerprint lines already in /etc/pam.d/sddm (earlier run,
  # manual Setup > Security > Fingerprint, stale order) demand a touch
  # SDDM can never get on this machine, so password login fails at the
  # greeter while the same password works at a tty. Strip them; the stock
  # password stack (auth include system-login and friends) stays in the
  # file underneath, untouched by these patterns.
  if [ -f /etc/pam.d/sddm ] && grep -Eq 'pam_fprintd\.so|hexciri-hw-laptop-closed|try_first_pass likeauth nullok' /etc/pam.d/sddm; then
    _sddm_tmp="$(mktemp)"
    if sudo sed -e '/pam_fprintd\.so/d' -e '/hexciri-hw-laptop-closed/d' -e '/try_first_pass likeauth nullok/d' /etc/pam.d/sddm > "$_sddm_tmp" 2>/dev/null && sudo install -Dm644 "$_sddm_tmp" /etc/pam.d/sddm; then
      info "No fingerprint reader detected, SDDM fingerprint lines stripped from /etc/pam.d/sddm (password-only login restored)"
    else
      warn "could not strip SDDM fingerprint lines from /etc/pam.d/sddm, password login may still fail (strip them by hand: sudo sed -i -e '/pam_fprintd\.so/d' -e '/hexciri-hw-laptop-closed/d' -e '/try_first_pass likeauth nullok/d' /etc/pam.d/sddm)"
    fi
    rm -f "$_sddm_tmp"
    unset _sddm_tmp
  else
    info "No fingerprint reader detected, /etc/pam.d/sddm left alone (password-only login)"
  fi
  if [ -f /usr/share/sddm/themes/hexciri/theme.conf ] && grep -q '^Fingerprint=' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null; then
    sudo sed -i '/^Fingerprint=/d' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null && info "SDDM theme Fingerprint flag removed (no reader)" || true
  fi
fi
# --- SDDM keyring auto-unlock (Brave password prompt, 2026-11-24) ---
# Root cause: gnome-keyring was installed (CORE_PKGS) and Seahorse with
# it, but nothing ever unlocked the keyring at login. Brave Origin stores
# its "Brave Safe Storage" key in the Login keyring via libsecret /
# Secret Service, and with the keyring locked it prompts for the keyring
# password on every launch. SDDM is the login manager, so the unlock
# belongs in /etc/pam.d/sddm (ArchWiki GNOME/Keyring: auth line at the
# end of the auth section, session line at the end of the session
# section). pam_gnome_keyring.so auto_start starts the daemon and
# unlocks the Login keyring with the login password, so Brave finds it
# already unlocked. No --password-store flag, no plaintext storage:
# Brave keeps using gnome-libsecret, it just stops being locked.
# Placement matters vs the fingerprint block above: the fingerprint
# pam_unix line has success=2, skipping the next two lines (gate +
# pam_fprintd). The keyring auth line goes after the LAST auth line in
# the file, never between pam_unix and pam_fprintd, so a password login
# still reaches it. Idempotent: earlier keyring lines are stripped
# first, so a re-run repairs a half-done file instead of duplicating.
# Two limits, by design: (1) a fingerprint login carries no password,
# so the keyring stays locked and Brave prompts once that session;
# log in with the password to unlock it. (2) the Login keyring password
# must match the login password. If Brave already created a Login
# keyring with a different password, PAM cannot unlock it: open
# Seahorse, right-click Login, Change Password, set it to the login
# password. Do NOT delete login.keyring, that destroys the stored
# secrets (including Brave's Safe Storage key).
# Also syncs future password changes: password optional
# pam_gnome_keyring.so in /etc/pam.d/passwd.
step "Configuring SDDM keyring auto-unlock (Brave password prompt)"
if [ -f /usr/lib/security/pam_gnome_keyring.so ] || command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if [ -f /etc/pam.d/sddm ]; then
    _kr_tmp="$(mktemp)"
    sudo sed -e '/pam_gnome_keyring\.so/d' /etc/pam.d/sddm > "$_kr_tmp" 2>/dev/null || cp /etc/pam.d/sddm "$_kr_tmp"
    python3 - "$_kr_tmp" <<'KEYRING_PYEOF'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
auth = "auth        optional    pam_gnome_keyring.so"
sess = "session     optional    pam_gnome_keyring.so auto_start"
def last_idx(kind):
    idx = -1
    for i, l in enumerate(lines):
        s = l.strip()
        if s and not s.startswith("#") and s.split()[0] == kind:
            idx = i
    return idx
ai = last_idx("auth")
if ai >= 0:
    lines.insert(ai + 1, auth)
else:
    lines.insert(0, auth)
si = last_idx("session")
if si >= 0:
    lines.insert(si + 1, sess)
else:
    lines.append(sess)
open(p, "w").write("\n".join(lines) + "\n")
KEYRING_PYEOF
    if sudo install -Dm644 "$_kr_tmp" /etc/pam.d/sddm; then
      info "SDDM keyring: pam_gnome_keyring.so in /etc/pam.d/sddm (auth + session auto_start, Brave launches with no keyring prompt)"
    else
      warn "could not write /etc/pam.d/sddm, Brave will keep asking for the keyring password on launch"
    fi
    rm -f "$_kr_tmp"
    unset _kr_tmp
  else
    warn "/etc/pam.d/sddm not found, keyring auto-unlock not configured (Brave will keep asking for the keyring password)"
  fi
  if [ -f /etc/pam.d/passwd ] && ! grep -q 'pam_gnome_keyring\.so' /etc/pam.d/passwd; then
    _kr_pw_tmp="$(mktemp)"
    cp /etc/pam.d/passwd "$_kr_pw_tmp" 2>/dev/null || sudo cat /etc/pam.d/passwd > "$_kr_pw_tmp" 2>/dev/null || true
    printf '%s\n' "password    optional    pam_gnome_keyring.so" >> "$_kr_pw_tmp"
    if sudo install -Dm644 "$_kr_pw_tmp" /etc/pam.d/passwd; then
      info "Keyring password sync: pam_gnome_keyring.so in /etc/pam.d/passwd (changing the login password updates the keyring password)"
    else
      warn "could not write /etc/pam.d/passwd, keyring password will not follow login password changes"
    fi
    rm -f "$_kr_pw_tmp"
    unset _kr_pw_tmp
  fi
else
  warn "gnome-keyring not installed, keyring auto-unlock skipped (Brave will keep asking for the keyring password)"
fi
# --- UTF-8 locale (System > About awk warning, 2026-11-23) ---
# fastfetch renders multibyte glyphs: with no UTF-8 locale on the system
# the About output can warn "Invalid multibyte data detected". EOS no-DE
# does not guarantee en_US.UTF-8 is generated, so generate it if no
# UTF-8 locale exists at all. Best-effort: a missing locale only affects
# About rendering, never the install.
if ! locale -a 2>/dev/null | grep -qi '\.utf-8$\|\.utf8$'; then
  if grep -q '^#en_US.UTF-8' /etc/locale.gen 2>/dev/null; then
    if sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && sudo locale-gen en_US.UTF-8 2>/dev/null; then
      info "Generated locale: en_US.UTF-8 (fastfetch / About needs a UTF-8 locale)"
    else
      warn "locale-gen en_US.UTF-8 failed, About may warn about multibyte data"
    fi
  elif grep -q '^en_US.UTF-8' /etc/locale.gen 2>/dev/null; then
    # Already enabled in locale.gen but never generated (fresh no-DE install):
    # locale -a has no UTF-8 locale, so generate it without editing the file.
    if sudo locale-gen en_US.UTF-8 2>/dev/null; then
      info "Generated locale: en_US.UTF-8 (was enabled but not generated)"
    else
      warn "locale-gen en_US.UTF-8 failed, About may warn about multibyte data"
    fi
  else
    warn "no UTF-8 locale and /etc/locale.gen has no en_US.UTF-8 line to enable, About fitting may warn about multibyte data"
  fi
fi
# System > About is a floating fastfetch now (2026-11-24): the old
# launch-about measured the logo with wc/awk, remembered the size in
# about.fit, and kept breaking, so the fit logic is gone. Delete the stale
# fit and the old about.txt logo, and repoint the installed fastfetch
# config's logo at the fork's icon.txt (upstream ASCII art, already placed
# at /usr/share/hexciri/icon.txt), since the config's logo source was
# ~/.config/hexciri/branding/about.txt and nothing creates that any more.
rm -f "$HOME/.local/state/hexciri/windows/about.fit" "$HOME/.config/hexciri/branding/about.txt" 2>/dev/null || true
if [ -f /etc/fastfetch/config.jsonc ] && grep -q 'config/hexciri/branding/about.txt' /etc/fastfetch/config.jsonc 2>/dev/null; then
  if sudo sed -i 's|~/.config/hexciri/branding/about.txt|/usr/share/hexciri/icon.txt|' /etc/fastfetch/config.jsonc; then
    info "About logo: fastfetch config logo repointed to /usr/share/hexciri/icon.txt (about.txt is gone)"
  else
    warn "could not repoint the fastfetch logo, About may render with a blank logo column"
  fi
elif [ -f /etc/fastfetch/config.jsonc ]; then
  info "About logo: fastfetch config already points at /usr/share/hexciri/icon.txt"
else
  warn "no /etc/fastfetch/config.jsonc, About logo repoint skipped"
fi

# --- systemd-boot menu timeout: 1s (2026-11-24, fixed 2026-11-24) ---
# EOS no-DE installs systemd-boot; its loader.conf defaults to timeout 5.
# Editing loader.conf alone did NOT change it live (still 5s after the
# 2b92c50 run): loader.conf timeout is overridden by the EFI variable
# LoaderConfigTimeout, which systemd-boot writes when the timeout is
# changed in the boot menu (t/T keys) and which bootctl manages
# (loader.conf(5), bootctl(1) set-timeout). So set BOTH: every loader.conf
# on the system, and the EFI variable with `bootctl set-timeout 1`.
# The ESP path comes from bootctl itself first (authoritative, not a
# guess), then the /efi, /boot, /boot/efi fallbacks; a commented-out
# #timeout line is replaced too, and duplicate timeout lines all become 1.
# Best-effort, never fatal: a GRUB machine has no loader.conf and no
# bootctl timeout to set, and a non-UEFI boot has no EFI variable.
step "Setting systemd-boot menu timeout to 1s"
_boot_esp=""
if command -v bootctl >/dev/null 2>&1; then
  _boot_esp="$(bootctl --print-esp-path 2>/dev/null || true)"
fi
_boot_cands=""
[ -n "$_boot_esp" ] && [ -d "$_boot_esp/loader" ] && _boot_cands="$_boot_esp/loader/loader.conf"
for _cand in /efi/loader/loader.conf /boot/loader/loader.conf /boot/efi/loader/loader.conf; do
  case " $_boot_cands " in *" $_cand "*) ;; *) _boot_cands="$_boot_cands $_cand";; esac
done
_boot_found=0
for _boot_loader in $_boot_cands; do
  [ -f "$_boot_loader" ] || continue
  _boot_found=1
  info "systemd-boot loader.conf: $_boot_loader (timeout lines before: $(grep -E '^[[:space:]]*#?[[:space:]]*timeout[[:space:]]' "$_boot_loader" 2>/dev/null | tr '\n' ' ' || true))"
  if grep -q '^timeout 1$' "$_boot_loader" 2>/dev/null; then
    info "systemd-boot timeout: already 1s in $_boot_loader (kept)"
  elif grep -qE '^[[:space:]]*#?[[:space:]]*timeout[[:space:]]' "$_boot_loader" 2>/dev/null; then
    sudo sed -i -E 's|^[[:space:]]*#?[[:space:]]*timeout[[:space:]].*|timeout 1|' "$_boot_loader" && info "systemd-boot timeout: 1s in $_boot_loader"
  else
    printf 'timeout 1\n' | sudo tee -a "$_boot_loader" >/dev/null && info "systemd-boot timeout: 1s appended to $_boot_loader"
  fi
  grep -q '^timeout 1$' "$_boot_loader" 2>/dev/null && info "systemd-boot timeout verified in $_boot_loader" || warn "systemd-boot timeout is not 1s in $_boot_loader"
done
if [ "$_boot_found" -eq 0 ] && [ ! -d /sys/firmware/efi ]; then warn "no systemd-boot loader.conf found and no EFI firmware, boot timeout cannot be set (GRUB or other bootloader?)"; elif [ "$_boot_found" -eq 0 ]; then info "no systemd-boot loader.conf found (/efi, /boot, /boot/efi), the EFI variable below controls the timeout on this layout"; fi
# EFI variable overrides loader.conf: read it before, set it, read it back.
_boot_efi_before=""
_boot_efi_var=/sys/firmware/efi/efivars/LoaderConfigTimeout-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
[ -r "$_boot_efi_var" ] && _boot_efi_before="$(tail -c +5 "$_boot_efi_var" 2>/dev/null | tr -d '\0')"
if [ -n "$_boot_efi_before" ]; then
  info "systemd-boot EFI timeout before: LoaderConfigTimeout=$_boot_efi_before (this EFI variable overrides loader.conf)"
else
  info "systemd-boot EFI timeout before: no LoaderConfigTimeout variable set"
fi
if [ -d /sys/firmware/efi ] && command -v bootctl >/dev/null 2>&1; then
  if sudo bootctl set-timeout 1 2>/dev/null; then
    info "systemd-boot EFI timeout: bootctl set-timeout 1 done (LoaderConfigTimeout=1)"
  else
    warn "bootctl set-timeout 1 failed, the EFI variable may still override loader.conf (check: bootctl status; /sys/firmware/efi/efivars/LoaderConfigTimeout-*)"
  fi
  _boot_efi_after=""
  [ -r "$_boot_efi_var" ] && _boot_efi_after="$(tail -c +5 "$_boot_efi_var" 2>/dev/null | tr -d '\0')"
  if [ "$_boot_efi_after" = "1" ]; then
    info "systemd-boot EFI timeout verified: LoaderConfigTimeout=1"
  elif [ -n "$_boot_efi_after" ]; then
    warn "systemd-boot EFI timeout is still LoaderConfigTimeout=$_boot_efi_after, not 1 (loader.conf alone will not fix this)"
  else
    warn "systemd-boot EFI timeout: LoaderConfigTimeout variable not readable after set-timeout, verify with: bootctl status"
  fi
else
  warn "not an EFI boot or no bootctl, EFI timeout variable left alone (loader.conf is the only control here)"
fi
unset _boot_esp _boot_cands _boot_found _boot_loader _cand _boot_efi_before _boot_efi_after _boot_efi_var

# --- Apply a default theme, like v1 does its theme sync ---
# v1 finishes with a theme applied, not just themes installed. Pick the
# first theme dir, so no theme name is guessed. Best-effort, never fatal:
# if theme-set cannot run before a login, the stock bar still starts and
# the user can set a theme after reboot.

# --- Apply a theme: CURRENT theme on a re-run, default only on fresh ---
# This was the theme reset: every re-run applied the FIRST theme dir
# alphabetically, wiping the user's chosen theme, staged colors.toml,
# GTK mode and SDDM background. On a re-run, re-applying the current
# theme regenerates the staged files from the same theme (safe, and
# needed after the /usr/share tree was replaced), without changing it.
# Fresh install: no current theme yet, pick the first dir as before.
step "Applying theme"
DEFAULT_THEME=""
THEME_DIRS=("$HEXCIRI_PATH"/themes/*/)
if [ "${#THEME_DIRS[@]}" -ge 1 ] && [ -d "${THEME_DIRS[0]}" ]; then
  DEFAULT_THEME="$(basename "${THEME_DIRS[0]}")"
fi
APPLY_THEME="$DEFAULT_THEME"
if [ "${IS_RERUN:-0}" = "1" ]; then
  if _cur="$(current_theme_name)"; then
    APPLY_THEME="$_cur"
    info "Re-run: keeping your theme: $APPLY_THEME (not the default $DEFAULT_THEME)"
  else
    info "Re-run: no current theme found, falling back to default: $DEFAULT_THEME"
  fi
else
  info "Default theme: $DEFAULT_THEME"
fi
unset _cur
# APPLY_THEME is deliberately NOT unset: the SDDM step below reads it as
# the applied (current on re-run, default on fresh) theme for its background.
# Skip the re-apply when the staged theme already matches: theme-set
# regenerates staged files, and running it on every re-run is how a
# hand-tweaked staged file (or a theme switch made after install) got
# stomped. Only re-apply when the theme changed or the staged files
# are missing/different.
_theme_skip=0
if [ "${IS_RERUN:-0}" = "1" ] && [ -n "$APPLY_THEME" ] && [ -f "$HOME/.local/state/hexciri/current/theme.name" ] && [ "$(cat "$HOME/.local/state/hexciri/current/theme.name" 2>/dev/null | tr -d '[:space:]')" = "$APPLY_THEME" ] && cmp -s "$HEXCIRI_PATH/themes/$APPLY_THEME/colors.toml" "$HOME/.local/state/hexciri/current/theme/colors.toml" 2>/dev/null; then
  _theme_skip=1
fi
if [ "$_theme_skip" = "1" ]; then
  info "Theme already applied: $APPLY_THEME (staged files match, skipping re-apply)"
elif [ -n "$APPLY_THEME" ]; then
  if [ -x "$HEXCIRI_PATH/bin/hexciri-theme-set" ]; then
    if "$HEXCIRI_PATH/bin/hexciri-theme-set" "$APPLY_THEME"; then
      info "Theme applied: $APPLY_THEME"
    else
      warn "hexciri-theme-set $APPLY_THEME failed, not fatal. Set a theme after reboot: hexciri-theme-set <theme>"
    fi
  else
    warn "hexciri-theme-set not found, skipping theme apply. Set a theme after reboot."
  fi
else
  warn "No themes found to apply, skipping theme apply."
fi
unset _theme_skip

# --- GTK settings + portal FileChooser (LocalSend file picker, 2026-11-23, fixed 2026-11-24) ---
# The picker is the xdg-desktop-portal FileChooser dialog, served out of
# process by xdg-desktop-portal-gtk (GTK4 on Arch). bb4df7f wrote
# gtk-theme-name=Adwaita-dark into ~/.config/gtk-3.0/settings.ini and
# ~/.config/gtk-4.0/settings.ini and pinned FileChooser=gtk, and the picker
# still came up light with white-on-white ghost text (screenshot 22:58).
# Two stacked causes, both in ~/.config (Devi's theory, confirmed):
# 1. "Adwaita-dark" is not a theme name, in GTK3 or GTK4. Adwaita is compiled
#    in and its dark form is a VARIANT, selected by
#    gtk-application-prefer-dark-theme (GTK3) / color-scheme prefer-dark
#    (GTK4), never by naming Adwaita-dark. Naming it makes GTK look for a
#    stylesheet that does not exist and fall back to light Adwaita, while
#    prefer-dark still flips the foreground light, which is exactly light
#    background + light text. The theme name is Adwaita in both files now;
#    dark comes from prefer-dark / color-scheme.
# 2. On Wayland GTK reads the theme from dconf (org.gnome.desktop.interface),
#    through the settings portal, NOT from settings.ini. The installer runs
#    from tty3 with no DBus session, so the old gsettings block was skipped
#    and dconf stayed at its defaults (Adwaita light, prefer-light), and
#    theme-set-gnome exits before doing anything when there is no bus, so a
#    theme switch never wrote settings.ini either. gsettings is now set
#    through dbus-run-session when there is no live bus (it writes the dconf
#    database persistently), and the forked theme-set-gnome writes both
#    settings.ini files on every theme switch, so the picker stays dark.
step "Writing GTK settings + portal FileChooser (LocalSend picker theming)"
_gtk_mode="$(HEXCIRI_PATH="$HEXCIRI_PATH" "$HEXCIRI_PATH/bin/hexciri-theme-color" --file "$HOME/.local/state/hexciri/current/theme/colors.toml" mode 2>/dev/null || echo dark)"
if [[ "$_gtk_mode" == "light" ]]; then _gtk_dark="false"; _gtk_scheme="prefer-light"; else _gtk_dark="true"; _gtk_scheme="prefer-dark"; fi
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
for _gtk_ver in 3.0 4.0; do
  _gtk_file="$HOME/.config/gtk-$_gtk_ver/settings.ini"
  _gtk_font="Noto Sans 11"; _gtk_theme="Adwaita"; _gtk_icon="Adwaita"
  if [ -f "$_gtk_file" ]; then
    _gtk_font="$(grep -m1 '^gtk-font-name=' "$_gtk_file" 2>/dev/null | cut -d= -f2- || true)"; [ -n "$_gtk_font" ] || _gtk_font="Noto Sans 11"
    _gtk_theme="$(grep -m1 '^gtk-theme-name=' "$_gtk_file" 2>/dev/null | cut -d= -f2- || true)"; [ -n "$_gtk_theme" ] || _gtk_theme="Adwaita"
    _gtk_icon="$(grep -m1 '^gtk-icon-theme-name=' "$_gtk_file" 2>/dev/null | cut -d= -f2- || true)"; [ -n "$_gtk_icon" ] || _gtk_icon="Adwaita"
    [ "$_gtk_theme" = "Adwaita-dark" ] && _gtk_theme="Adwaita"
  fi
  if [ -f "$_gtk_file" ] && grep -q "^gtk-theme-name=$_gtk_theme$" "$_gtk_file" && grep -q "^gtk-application-prefer-dark-theme=$_gtk_dark$" "$_gtk_file"; then
    info "GTK settings: already correct in $_gtk_file (kept your font/theme)"
  else
    cat > "$_gtk_file" <<GTK_EOF
[Settings]
gtk-theme-name=$_gtk_theme
gtk-icon-theme-name=$_gtk_icon
gtk-application-prefer-dark-theme=$_gtk_dark
gtk-font-name=$_gtk_font
GTK_EOF
  fi
done
unset _gtk_ver _gtk_file _gtk_font _gtk_theme _gtk_icon
info "GTK settings: theme=Adwaita (dark=$_gtk_dark) in gtk-3.0/gtk-4.0 settings.ini (Adwaita-dark is not a theme name, dark comes from prefer-dark)"
_gtk_set() {
  if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme "$_gtk_scheme" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "Adwaita" 2>/dev/null || true
  elif command -v dbus-run-session >/dev/null 2>&1; then
    dbus-run-session -- gsettings set org.gnome.desktop.interface gtk-theme "Adwaita" 2>/dev/null || true
    dbus-run-session -- gsettings set org.gnome.desktop.interface color-scheme "$_gtk_scheme" 2>/dev/null || true
    dbus-run-session -- gsettings set org.gnome.desktop.interface icon-theme "Adwaita" 2>/dev/null || true
  else
    warn "no DBus session and no dbus-run-session, dconf GTK theme not set (settings.ini only)"
  fi
}
_gtk_set
unset -f _gtk_set
mkdir -p "$HOME/.config/xdg-desktop-portal"
if [ -f "$HOME/.config/xdg-desktop-portal/portals.conf" ] && grep -q '^org.freedesktop.impl.portal.FileChooser=gtk$' "$HOME/.config/xdg-desktop-portal/portals.conf"; then
  info "Portal config: already FileChooser=gtk (kept)"
else
  cat > "$HOME/.config/xdg-desktop-portal/portals.conf" <<PORTAL_EOF
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Secret=gnome-keyring
PORTAL_EOF
  info "Portal config: FileChooser=gtk in ~/.config/xdg-desktop-portal/portals.conf"
fi
systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gtk.service 2>/dev/null || systemctl --user try-restart xdg-desktop-portal-gtk.service 2>/dev/null || true
unset _gtk_mode _gtk_dark _gtk_scheme

# --- EOS update icon (Terminal=true launch, 2026-11-23) ---
# The eos-update grid icon is /usr/share/applications/eos-update.desktop
# from eos-bash-shared: Exec=eos-update, Terminal=true. Terminal=true
# entries launch through xdg-terminal-exec, and under the Quickshell grid
# that path silently does nothing. eos-update itself never calls
# hexciri-update (Devi's theory checked: it is EOS's own pacman/yay
# updater; hexciri-update exists in the fork, it is just not reworked for
# EOS yet in Phase 2), so the fix is a user override that launches it in
# Kitty directly, with --hold so a failure stays visible instead of a
# window that flashes and closes.
step "Fixing EOS update icon (Kitty override for eos-update)"
if command -v eos-update >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/share/applications"
  # Keep the icon EOS ships: the old override's Icon=eos-update was invented
  # (no such icon exists), so the grid showed a blank. Read the Icon from
  # the EOS desktop file when it exists (added to eos-bash-shared in 23.8-1),
  # else the EndeavourOS icon, else the standard freedesktop update icon.
  _eos_icon=""
  if [ -f /usr/share/applications/eos-update.desktop ]; then
    _eos_icon="$(grep -m1 '^Icon=' /usr/share/applications/eos-update.desktop 2>/dev/null | cut -d= -f2- || true)"
  fi
  if [ -z "$_eos_icon" ] && [ -f /usr/share/pixmaps/endeavouros-icon.png ]; then
    _eos_icon="endeavouros-icon"
  fi
  [ -n "$_eos_icon" ] || _eos_icon="system-software-update"
  _eos_new="$(mktemp)"
  cat > "$_eos_new" <<EOS_EOF
[Desktop Entry]
Type=Application
Name=EOS Update
Comment=Update EndeavourOS packages (pacman + AUR) in Kitty
Icon=$_eos_icon
Exec=kitty --hold -e eos-update --yay
Terminal=false
Categories=System;
EOS_EOF
  if [ -f "$HOME/.local/share/applications/eos-update.desktop" ] && cmp -s "$_eos_new" "$HOME/.local/share/applications/eos-update.desktop"; then
    info "EOS update icon: already correct (kept)"
  elif [ -f "$HOME/.local/share/applications/eos-update.desktop" ] && [ "${IS_RERUN:-0}" = "1" ]; then
    cp -a "$_eos_new" "$HOME/.local/share/applications/eos-update.desktop.hexciri.new"
    info "EOS update icon: kept your override (new version saved to eos-update.desktop.hexciri.new)"
  else
    cp -a "$_eos_new" "$HOME/.local/share/applications/eos-update.desktop"
  fi
  rm -f "$_eos_new"
  unset _eos_icon _eos_new
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  info "EOS update icon: override launches kitty --hold -e eos-update --yay"
else
  warn "eos-update not found, EOS update icon left as-is (install eos-bash-shared)"
fi

# --- Speed test client (Super+Alt+Space > Speed Test > Network, 2026-11-24) ---
# hexciri-network-speedtest execs ${HEXCIRI_SPEEDTEST_BINARY:-/usr/lib/hexciri/speedtest}
# and upstream ships that client as the omarchy-speedtest package from their
# own repo, which Hexciri deliberately does not use. Without the binary the
# panel shows speedtest.failed. Ship Hexciri's own curl-based client instead
# (v2/hexciri-speedtest-client): it prints live Mbps numbers, one per line,
# which is the panel's protocol, against public test endpoints.
step "Installing Hexciri speed test client (/usr/lib/hexciri/speedtest)"
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-speedtest-client" ]; then
  if sudo install -Dm755 "$HEXCIRI_REPO_ROOT/v2/hexciri-speedtest-client" /usr/lib/hexciri/speedtest; then
    info "Speed test client installed: /usr/lib/hexciri/speedtest (curl-based, Cloudflare/Tele2 endpoints)"
  else
    warn "could not install /usr/lib/hexciri/speedtest, Speed Test > Network will show speedtest.failed"
  fi
else
  warn "v2/hexciri-speedtest-client not in the installer tree, Speed Test > Network will show speedtest.failed"
fi

# --- Theme SDDM with the currently applied theme ---
# The EndeavourOS default SDDM theme is ugly as all hell, and the installer
# previously never touched SDDM theming at all: it only enabled the service.
# The theme comes from Hexciri's own branding/sddm/ in the repo tree (the
# Hexciri emblem logo, Name=Hexciri), NOT from Omarchy's default/sddm/omarchy/:
# that theme ships Omarchy's logo.png wordmark, and the last live boot showed
# Omarchy logos at the login screen. The greeter compositor config still comes
# from the Omarchy fork ($HEXCIRI_PATH/default/sddm/hyprland.lua).
# The applied theme's background colour is written into the SDDM theme's
# theme.conf (Background=), because branding Main.qml reads its colours from
# theme.conf (root.bgColor), not from a literal colour in the QML: the old
# sed recolor of Main.qml could not work here. Colour is read from the
# theme's colors.toml, never a guessed theme name: DEFAULT_THEME above is
# the first theme dir, and theme-set will already have staged it at
# ~/.local/state/hexciri/current.
# Best-effort, never fatal: if the SDDM theme source is missing, SDDM
# keeps the EndeavourOS default and login still works. Runs from tty,
# no GUI needed. DisplayServer is deliberately NOT forced to Wayland
# here: SDDM already logs Devi in, and the theme works under either
# greeter compositor.

step "Theming SDDM with the current theme"
SDDM_SRC=""
if [ -d "$HEXCIRI_REPO_ROOT/branding/sddm" ]; then
  SDDM_SRC="$HEXCIRI_REPO_ROOT/branding/sddm"
  info "SDDM theme source: Hexciri branding/sddm/ from the installer tree"
elif [ -d "$HEXCIRI_PATH/default/sddm/hexciri" ]; then
  warn "branding/sddm/ not found in the installer tree, falling back to the forked Omarchy SDDM theme (may still show Omarchy logos)."
  SDDM_SRC="$HEXCIRI_PATH/default/sddm/hexciri"
fi
if [ -n "$SDDM_SRC" ]; then
  sudo mkdir -p /usr/share/sddm/themes || warn "could not create /usr/share/sddm/themes, SDDM theming skipped."
  if [ -d /usr/share/sddm/themes ]; then
    sudo rm -rf /usr/share/sddm/themes/hexciri
    if sudo cp -a "$SDDM_SRC" /usr/share/sddm/themes/hexciri; then
      info "Installed SDDM theme: /usr/share/sddm/themes/hexciri"
    else
      warn "could not copy SDDM theme to /usr/share/sddm/themes/hexciri, keeping the EndeavourOS default theme."
    fi
  fi
  if [ -f "$HEXCIRI_PATH/default/sddm/hyprland.lua" ]; then
    if [ -f /usr/share/sddm/hyprland.lua ] && ! cmp -s "$HEXCIRI_PATH/default/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua; then
      sudo cp -a /usr/share/sddm/hyprland.lua /usr/share/sddm/hyprland.lua.hexciri.bak 2>/dev/null || true
      info "Backed up existing /usr/share/sddm/hyprland.lua to /usr/share/sddm/hyprland.lua.hexciri.bak"
    fi
    sudo cp -a "$HEXCIRI_PATH/default/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua 2>/dev/null && info "Installed SDDM greeter Hyprland config: /usr/share/sddm/hyprland.lua" || warn "could not install /usr/share/sddm/hyprland.lua, SDDM greeter keeps its existing config."
  fi
  TMP_SDDM_THEME="$(mktemp)"
  printf '[Theme]\nCurrent=hexciri\n[Users]\nRememberLastUser=true\nRememberLastSession=true\n' > "$TMP_SDDM_THEME"
  sudo install -Dm644 "$TMP_SDDM_THEME" /etc/sddm.conf.d/20-hexciri-theme.conf 2>/dev/null && info "SDDM theme selected: Current=hexciri (/etc/sddm.conf.d/20-hexciri-theme.conf)" || warn "could not write /etc/sddm.conf.d/20-hexciri-theme.conf, SDDM keeps its current theme."
  rm -f "$TMP_SDDM_THEME"
  # Write the applied theme's background colour into the SDDM theme's
  # theme.conf (Background=): branding Main.qml reads root.bgColor from
  # config, so a sed recolor of Main.qml cannot work here.
  SDDM_BG=""
  for _colors in "$HOME/.local/state/hexciri/current/theme/colors.toml" "$HEXCIRI_PATH/themes/${APPLY_THEME:-${DEFAULT_THEME:-}}/colors.toml"; do
    if [ -f "$_colors" ]; then
      SDDM_BG="$(grep -m1 -E '^[[:space:]]*background[[:space:]]*=' "$_colors" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || true)"
      [ -n "$SDDM_BG" ] && break
    fi
  done
  unset _colors
  if [[ "$SDDM_BG" =~ ^#[0-9a-fA-F]{6}$ ]] && [ -f /usr/share/sddm/themes/hexciri/theme.conf ] && grep -q "^Background=$SDDM_BG$" /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null; then
    info "SDDM theme background already $SDDM_BG (kept)"
  elif [[ "$SDDM_BG" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    TMP_SDDM_CONF="$(mktemp)"
    printf '[General]\nBackground=%s\n' "$SDDM_BG" > "$TMP_SDDM_CONF"
    # The greeter shows "touch the reader or enter your password" only when
    # Fingerprint=true is in theme.conf (branding Main.qml reads
    # config.Fingerprint). Only when a finger is actually enrolled.
    if hexciri_has_fingerprint_reader && hexciri_finger_enrolled; then
      printf 'Fingerprint=true\n' >> "$TMP_SDDM_CONF"
    fi
    if sudo install -Dm644 "$TMP_SDDM_CONF" /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null; then
      info "SDDM theme background set to the current theme background: $SDDM_BG"
    else
      warn "could not write SDDM theme.conf, it keeps its packaged background colour."
    fi
    rm -f "$TMP_SDDM_CONF"
  else
    warn "could not read a background colour from the applied theme colors.toml, SDDM keeps its packaged background colour."
  fi
  unset SDDM_BG
  # Seed SDDM's last-user state (2026-11-24, empty-username login):
  # SDDM only writes /var/lib/sddm/state.conf [Last] User on a
  # successful login, so a fresh install has no last user and the
  # greeter (no username field) used to submit "" to PAM. The QML
  # fallback to the first user in the model is the real fix; seeding
  # here is belt-and-braces so lastUser is already correct on the
  # first boot, and it is never overwritten when a last user exists.
  if [ ! -s /var/lib/sddm/state.conf ] || ! grep -q '^User=' /var/lib/sddm/state.conf 2>/dev/null; then
    _sddm_state="$(mktemp)"
    printf '[Last]\nUser=%s\nSession=/usr/share/wayland-sessions/hexciri.desktop\n' "$USER" > "$_sddm_state"
    if sudo install -Dm644 "$_sddm_state" /var/lib/sddm/state.conf 2>/dev/null; then
      info "SDDM last user seeded: $USER (/var/lib/sddm/state.conf)"
    else
      warn "could not seed /var/lib/sddm/state.conf, first SDDM login relies on the theme's first-user fallback"
    fi
    rm -f "$_sddm_state"
    unset _sddm_state
  fi
else
  warn "No SDDM theme source found, keeping the EndeavourOS default SDDM theme."
fi
unset SDDM_SRC

# --- Install Strata (file manager), best-effort ---
# Devi's default file manager is Strata (GitHub release, lgse/strata), not
# Omarchy's Folio. The forked launch-files scripts now call strata (rename
# map), so Strata must exist or Super+Shift+F errors with Command not found.
# bin/hexciri-strata-install is a symlink to bin/hexciri-setup and dispatches
# to its strata subcommand: per-user release binary, sha256-verified,
# idempotent, installs to ~/.local/bin/strata, needs glibc >= 2.39.
# Strata is the file-manager part of the default apps step above, not a
# one-off: the files default is pinned here too, once its desktop entry
# exists.
step "Installing Strata (file manager, best-effort)"
if [ -x "$HEXCIRI_REPO_ROOT/bin/hexciri-strata-install" ]; then
  if bash "$HEXCIRI_REPO_ROOT/bin/hexciri-strata-install"; then
    info "Strata installed (or already current)"
  else
    warn "Strata install failed or skipped, Super+Shift+F will error until Strata is installed. Install by hand: hexciri-strata-install"
  fi
else
  warn "bin/hexciri-strata-install not found in the installer tree, Strata not installed. Install by hand later if needed."
fi
# Strata lands in ~/.local/bin/strata, which Hyprland exec / uwsm-app does
# not reliably have on PATH, so Super+Shift+F still errored after a
# successful Strata install. Symlink it into /usr/share/hexciri/bin/, which
# IS on the uwsm PATH, so launch-files finds it either way.
if [ -x "$HOME/.local/bin/strata" ]; then
  sudo ln -sf "$HOME/.local/bin/strata" "$HEXCIRI_PATH/bin/strata" 2>/dev/null && info "Strata linked into hexciri bin PATH: $HEXCIRI_PATH/bin/strata" || warn "could not link strata into $HEXCIRI_PATH/bin, Super+Shift+F relies on ~/.local/bin being on PATH"
  # Pin Strata as the file manager (v1 mime-defaults pick: strata ->
  # io.github.lgse.Strata.desktop), now that its desktop entry exists.
  if [ -f "$HOME/.local/share/applications/io.github.lgse.Strata.desktop" ]; then
    [ -f "$HOME/.local/state/hexciri/defaults/files" ] || printf '%s' "strata" > "$HOME/.local/state/hexciri/defaults/files"
    xdg-mime default io.github.lgse.Strata.desktop inode/directory 2>/dev/null && info "Default file manager: Strata" || warn "xdg-mime could not pin Strata for inode/directory"
  fi
else
  warn "strata binary not found at ~/.local/bin/strata after install step, Super+Shift+F will error until it is installed"
fi
# Strata "Follow Omarchy" reads ~/.local/state/omarchy/current/theme/
# colors.toml. v2 stages themes at ~/.local/state/hexciri/current/theme/,
# so Strata sees nothing there and never follows a theme switch. v1
# fixed this with per-file symlinks in theme_set(); recreate them here
# and on every theme switch via a theme-set.d hook (theme-set calls
# hexciri-hook theme-set at the end of every switch). The whole-dir
# symlink guard mirrors v1 theme_ensure(): if
# ~/.local/state/omarchy/current is itself a symlink (older variant of
# the trick), remove it first so the per-file links land on real dirs.
mkdir -p "$HOME/.config/hexciri/hooks/theme-set.d"
cat > "$HOME/.config/hexciri/hooks/theme-set.d/10-hexciri-strata-theme" <<'STRATA_HOOK_EOF'
#!/bin/bash
# Hexciri: Strata Follow-Omarchy compat. Point Strata's Omarchy theme
# state at Hexciri's live theme files, so Strata recolors on theme switch.
# Runs on every theme switch (theme-set hook) and once at install.
if [ -L "$HOME/.local/state/omarchy/current" ]; then
  rm -f "$HOME/.local/state/omarchy/current"
fi
if command -v strata >/dev/null 2>&1 || [ -x "$HOME/.local/bin/strata" ]; then
  mkdir -p "$HOME/.local/state/omarchy/current/theme"
  ln -sfn "$HOME/.local/state/hexciri/current/theme.name" "$HOME/.local/state/omarchy/current/theme.name"
  ln -sfn "$HOME/.local/state/hexciri/current/theme/colors.toml" "$HOME/.local/state/omarchy/current/theme/colors.toml"
fi
STRATA_HOOK_EOF
chmod +x "$HOME/.config/hexciri/hooks/theme-set.d/10-hexciri-strata-theme"
bash "$HOME/.config/hexciri/hooks/theme-set.d/10-hexciri-strata-theme" 2>/dev/null && info "Installed: Strata Follow-Omarchy theme symlinks (theme-set.d hook + applied now)" || warn "Strata theme symlink hook failed, Strata will not follow live theme changes"

fi # end system-config guard (minimal re-apply: skipped in fork-only mode)
# --- Hexciri theme hooks (2026-11-24, Devi: modified better Omarchy theme hook) ---
# Omarchy's theme-set already calls hexciri-hook theme-set at the end of
# every switch, which runs every file in
# ~/.config/hexciri/hooks/theme-set.d/ in glob order. These are the
# Hexciri hooks, in run order:
#   10-hexciri-strata-theme (above): Strata Follow-Omarchy symlinks.
#   10-hexciri-gtk: flat GTK override sheet from the active palette.
#   11-hexciri-adapta: signaldirective/Adapta GTK, opt-in only.
#   20-hexciri-thpm: THPM hook-run theme-set (enabled integrations).
#   90-thpm: THPM's own hook, bridged from the omarchy hook dir.
# theme-env.sh is the shared THPM-port runtime every hook sources.
# No extra apps: GTK/Adapta/THPM/steam are theming only, the apps they
# theme (Steam, Nautilus, Adapta) are used only when already installed.
# --- Hexciri Settings, Hexciri shell plugin (2026-11-24) ---
# Fork of ipkalid/omarchy-settings master ad54288, kept as a PLUGIN, the
# way Omarchy does plugins for system stuff (service kind, no bar
# widget): Deoxizn/hexciri-settings, plugin id pizza.dirty.settings.
# Enabling builds the Qt app (qmake6 + make, gcc/make/qt6 in CORE_PKGS)
# and installs ~/.local/bin/hexciri-settings + desktop entry + icon
# (Devi's serversettings icon). Super+Ctrl+S opens it (bind in
# hexciri-custom-binds.lua, launcher via hexciri-launch-settings).
# This step installs + enables the plugin and builds the app
# synchronously, so hexciri update leaves a working binary behind with
# no manual build command. Updates after that come through
# `hexciri plugin update pizza.dirty.settings`; the plugin's Service.qml
# rebuilds on update. Best-effort, never dies: a failed build warns,
# the rest of the install still lands, and the next hexciri update
# retries the build automatically (missing binary blocks light-sync).
step "Installing Hexciri Settings (Hexciri shell plugin, Super+Ctrl+S)"
SETTINGS_PLUGIN_ID="pizza.dirty.settings"
SETTINGS_PLUGIN_DIR="$HOME/.config/hexciri/plugins/$SETTINGS_PLUGIN_ID"
SETTINGS_PLUGIN_URL="https://github.com/Deoxizn/hexciri-settings.git"
_HEXCIRI_CLI="/usr/share/hexciri/bin/hexciri"
[ -x "$_HEXCIRI_CLI" ] || _HEXCIRI_CLI="hexciri"
_HEXCIRI_VALIDATE="/usr/share/hexciri/bin/hexciri-plugin-validate"
[ -x "$_HEXCIRI_VALIDATE" ] || _HEXCIRI_VALIDATE="hexciri-plugin-validate"
# Already installed: pull the latest plugin commit first, so the build
# below is of the current plugin, not the checkout from last time.
if [ -d "$SETTINGS_PLUGIN_DIR/.git" ]; then
  if "$_HEXCIRI_CLI" plugin update "$SETTINGS_PLUGIN_ID" --yes >/dev/null 2>&1; then
    info "  settings plugin updated: $SETTINGS_PLUGIN_ID"
  else
    warn "  settings plugin update failed, building the installed checkout as-is"
  fi
elif ! "$_HEXCIRI_CLI" plugin add "$SETTINGS_PLUGIN_URL" --enable --yes >/dev/null 2>&1; then
  # No shell running (bootstrap from tty3): plugin add needs the shell
  # for rescan/enable, so clone + validate directly and let the first
  # shell start load Service.qml. Never die the install over this.
  mkdir -p "$HOME/.config/hexciri/plugins"
  if git clone -- "$SETTINGS_PLUGIN_URL" "$SETTINGS_PLUGIN_DIR" 2>/dev/null && "$_HEXCIRI_VALIDATE" "$SETTINGS_PLUGIN_DIR" >/dev/null 2>&1; then
    info "  settings plugin cloned (shell not running, enable happens on first shell start): $SETTINGS_PLUGIN_DIR"
  else
    rm -rf "$SETTINGS_PLUGIN_DIR"
    warn "  Hexciri Settings plugin could not be installed (network or git), app not built; the next hexciri update retries it"
  fi
else
  info "  settings plugin installed + enabled: $SETTINGS_PLUGIN_ID"
fi
# Synchronous build: the plugin's Service.qml would build in the
# background on shell enable, but hexciri update must leave the binary
# behind now, not "in a minute". git clones preserve exec bits, but
# belt and braces: chmod + bash invoke, never direct exec.
if [ -f "$SETTINGS_PLUGIN_DIR/plugin/install" ]; then
  chmod +x "$SETTINGS_PLUGIN_DIR/plugin/install" "$SETTINGS_PLUGIN_DIR/plugin/uninstall" "$SETTINGS_PLUGIN_DIR/bin/build" "$SETTINGS_PLUGIN_DIR/bin/install" "$SETTINGS_PLUGIN_DIR/bin/test" 2>/dev/null || true
  if bash "$SETTINGS_PLUGIN_DIR/plugin/install" --quiet; then
    info "  settings installed: hexciri-settings $(hexciri-settings --version 2>/dev/null || echo present) (Super+Ctrl+S, launcher: Hexciri Settings)"
  else
    warn "  Hexciri Settings build failed (log: ~/.cache/hexciri-settings-build/build.log); the next hexciri update retries the build automatically"
  fi
else
  warn "  Hexciri Settings plugin install script missing, app not built"
fi
# 2026-11-24, Devi: no Settings row in the main menu. If the old row
# ever landed in the user menu extensions file, drop that exact line
# (scoped to the hexciri-launch-settings action, nothing else).
# Super+Ctrl+S / launcher still open Settings.
_user_menu="$HOME/.config/hexciri/extensions/hexciri-menu.jsonc"
if [[ -f $_user_menu ]] && grep -q '"settings".*hexciri-launch-settings' "$_user_menu"; then
  sed -i '/"settings".*hexciri-launch-settings/d' "$_user_menu"
  info "  menu: removed Settings row from user menu extensions (Super+Ctrl+S / launcher only)"
fi
unset SETTINGS_PLUGIN_ID SETTINGS_PLUGIN_DIR SETTINGS_PLUGIN_URL _HEXCIRI_CLI _HEXCIRI_VALIDATE

# --- Nyxiri plugins, nyx branch (2026-11-24, Devi) ---
# Nyxiri is Devi's live Omarchy bar/menu/workspaces suite, forked to
# Deoxizn/* with plugin ids pizza.dirty.*. Hexciri needs the nyx branch
# of each, not main: nyx is the Hexciri port (omarchy -> hexciri paths,
# hexciri-shell IPC), main is the Omarchy build. hexciri-settings is
# NOT here: its main (master) IS Hexciri already, no nyx branch exists,
# and the Settings step above already installs it from main.
# OPT-IN, NOT base install (Devi 2026-11-24): Nyxiri and wallcraft are
# Devi's own setup, user choice, never a default. This step installs
# NOTHING on a machine that has none of them: it only re-adds / updates
# plugins that are ALREADY installed (from main or anywhere) to nyx,
# preserving settings. A fresh add happens only with --with-nyxiri
# (core seven: bar, menu, workspaces, clock, weather, arch-updates,
# wallcraft) or --with-cats (cpurr + bongocat, same as Nyxiri's
# installer). Once installed they stay installed: a later run without
# the flag still updates them, it just does not newly add them.
# How the branch gets in (checked against the forked plugin CLI,
# upstream omacom/omarchy 94a8c3c):
#   * `hexciri plugin add` has NO --branch flag (unknown options fail)
#     and it clones the repo's DEFAULT branch, refusing when the id is
#     already installed. So nyx installs go through git clone
#     --branch nyx + hexciri-plugin-validate + hexciri plugin enable,
#     the same tty3 fallback the Settings step uses.
#   * `hexciri plugin update <id>` pulls the CHECKED-OUT branch, not
#     origin HEAD: the fork patch below (bin/hexciri-plugin-update)
#     changed the fetch from `origin HEAD` (remote DEFAULT branch,
#     main) to the checked-out branch. Before that patch, update
#     merged main into a nyx checkout, or failed to fast-forward once
#     they diverged, and never pulled nyx; `git remote set-head origin
#     nyx` does NOT fix it, fetch resolves HEAD on the remote side
#     (verified in a local bare-repo sim). A plugin installed any
#     other way (e.g. plugin add from main) is still re-added from nyx
#     here, never trusted to update itself across branches.
#   * `hexciri plugin remove` only rm -rf's the plugin dir (+ shell IPC
#     disable). shell.json and plugin config dirs (~/.config/pizza.dirty.*,
#     e.g. the clock's calendars.json) are never touched by either the
#     remove or the re-clone, so settings survive a re-add.
#   * wallcraft ported to Hexciri 2026-11-24 (nyx, clonedFrom
#     hexciri.background, hexciri paths/commands, theme-set
#     skip-background kept on the OMARCHY_ spelling the fork still
#     reads). Re-added from nyx like the rest here, opt-in only.
# Best-effort, never dies: a failed clone/update warns, the rest of the
# install still lands, and the next hexciri update retries it.
step "Nyxiri plugins (opt-in, nyx branch: re-add if installed, install only with --with-nyxiri)"
_NYX_CLI="/usr/share/hexciri/bin/hexciri"
[ -x "$_NYX_CLI" ] || _NYX_CLI="hexciri"
_NYX_VALIDATE="/usr/share/hexciri/bin/hexciri-plugin-validate"
[ -x "$_NYX_VALIDATE" ] || _NYX_VALIDATE="hexciri-plugin-validate"
# Bar choice before the step, so a re-run can never flip it: bar use
# writes .bar.id in shell.json, and the enabled plugins live in the
# .plugins array there. Both are read straight from the file, no shell
# IPC needed, so this works from tty3 too.
_NYX_BAR_BEFORE=""
_NYX_PLUGINS_BEFORE=""
if [ -f "$HOME/.config/hexciri/shell.json" ] && command -v jq >/dev/null 2>&1; then
  _NYX_BAR_BEFORE="$(jq -r '.bar.id // empty' "$HOME/.config/hexciri/shell.json" 2>/dev/null || echo "")"
  _NYX_PLUGINS_BEFORE="$(jq -r '.plugins // [] | join(" ")' "$HOME/.config/hexciri/shell.json" 2>/dev/null || echo "")"
fi
# _nyxiri_plugin <id> <url> [cats-only]: install or update one plugin
# from its nyx branch. Always returns 0; failures warn only.
_NYX_BAR_NEW=0
_nyxiri_plugin() {
  local _id="$1" _url="$2" _cats_only="${3:-0}" _dir="" _branch="" _was_enabled=0
  _dir="$HOME/.config/hexciri/plugins/$_id"
  # Already on nyx: update in place, touch nothing else (no re-enable,
  # no bar switch, enable state and bar choice stay exactly as they are).
  if [ -d "$_dir/.git" ]; then
    _branch="$(git -C "$_dir" branch --show-current 2>/dev/null || echo "")"
    if [ "$_branch" = "nyx" ]; then
      if "$_NYX_CLI" plugin update "$_id" --yes >/dev/null 2>&1; then
        info "  nyxiri plugin updated: $_id (nyx)"
      else
        warn "  nyxiri plugin update failed, keeping installed checkout: $_id"
      fi
      return 0
    fi
    info "  nyxiri plugin on branch '${_branch:-unknown}', re-adding from nyx: $_id"
    # Was it enabled before removal? shell.json .plugins array is the
    # record (read above, no shell needed). No readable record means
    # assume enabled: a previous installer run enabled everything it
    # installed, and a plugin the user disabled is the rarer case.
    if [ -z "$_NYX_PLUGINS_BEFORE" ]; then
      _was_enabled=1
    else
      case " $_NYX_PLUGINS_BEFORE " in
        *" $_id "*) _was_enabled=1 ;;
        *) _was_enabled=0 ;;
      esac
    fi
    if ! "$_NYX_CLI" plugin remove "$_id" --yes >/dev/null 2>&1; then
      # Shell not running (tty3 bootstrap): plugin remove needs shell
      # IPC to disable + rescan, so it dies before rm. The dir is a
      # plain git checkout, remove it directly; shell.json and plugin
      # config dirs are never touched by either path.
      rm -rf "$_dir"
    fi
  else
    # Not installed: fresh add only on explicit opt-in, never by
    # default (Nyxiri is user choice, not base install). _NYX_BAR_NEW
    # records a fresh Nyxiri bar install, so the bar switch below only
    # fires for a real opt-in, never for a re-add on a machine whose
    # bar choice is already made.
    if [ "$_cats_only" = "1" ]; then
      if [ "${WITH_CATS:-0}" != "1" ]; then
        info "  nyxiri plugin skipped (not installed, cats are opt-in, --with-cats): $_id"
        return 0
      fi
    elif [ "${WITH_NYXIRI:-0}" != "1" ]; then
      info "  nyxiri plugin skipped (not installed, Nyxiri is opt-in, --with-nyxiri): $_id"
      return 0
    fi
    _was_enabled=1
    [ "$_id" = "pizza.dirty.nyxiri" ] && _NYX_BAR_NEW=1
  fi
  mkdir -p "$HOME/.config/hexciri/plugins"
  if git clone --branch nyx -- "$_url" "$_dir" 2>/dev/null && "$_NYX_VALIDATE" "$_dir" >/dev/null 2>&1; then
    info "  nyxiri plugin cloned from nyx: $_id"
  else
    rm -rf "$_dir"
    warn "  nyxiri plugin could not be installed from nyx (network or git): $_id, the next hexciri update retries it"
    return 0
  fi
  if [ "$_was_enabled" = "1" ]; then
    if "$_NYX_CLI" plugin enable "$_id" >/dev/null 2>&1; then
      info "  nyxiri plugin enabled: $_id"
    else
      warn "  nyxiri plugin cloned but not enabled (shell not running, enable happens on first shell start): $_id"
    fi
  else
    info "  nyxiri plugin cloned, left disabled (was disabled before re-add): $_id"
  fi
  return 0
}
# Nothing installed and no opt-in: one line, no per-plugin noise.
_NYX_ANY_INSTALLED=0
for _nyx_id in pizza.dirty.nyxiri pizza.dirty.nyxiri-menu pizza.dirty.nyxiri-workspaces pizza.dirty.clock pizza.dirty.weather pizza.dirty.arch-updates pizza.dirty.cpurr pizza.dirty.bongocat pizza.dirty.wallcraft; do
  [ -d "$HOME/.config/hexciri/plugins/$_nyx_id/.git" ] && _NYX_ANY_INSTALLED=1
done
if [ "$_NYX_ANY_INSTALLED" = "0" ] && [ "${WITH_NYXIRI:-0}" != "1" ] && [ "${WITH_CATS:-0}" != "1" ]; then
  info "  Nyxiri not installed, nothing to do (opt-in: install.sh --with-nyxiri, cats: --with-cats)"
else
_nyxiri_plugin "pizza.dirty.nyxiri" "https://github.com/Deoxizn/nyxiri.git"
_nyxiri_plugin "pizza.dirty.nyxiri-menu" "https://github.com/Deoxizn/nyxiri-menu.git"
_nyxiri_plugin "pizza.dirty.nyxiri-workspaces" "https://github.com/Deoxizn/nyxiri-workspaces.git"
_nyxiri_plugin "pizza.dirty.clock" "https://github.com/Deoxizn/omarchy-clock.git"
_nyxiri_plugin "pizza.dirty.weather" "https://github.com/Deoxizn/omarchy-weather.git"
_nyxiri_plugin "pizza.dirty.arch-updates" "https://github.com/Deoxizn/Arch-Updates.git"
_nyxiri_plugin "pizza.dirty.cpurr" "https://github.com/Deoxizn/omarchy-cpurr.git" 1
_nyxiri_plugin "pizza.dirty.bongocat" "https://github.com/Deoxizn/omarchy-bongocat.git" 1
_nyxiri_plugin "pizza.dirty.wallcraft" "https://github.com/Deoxizn/wallcraft.git"
fi
unset _nyx_id _NYX_ANY_INSTALLED
unset -f _nyxiri_plugin
# Stock workspaces off when Nyxiri workspaces is active: disable, never
# remove (it is a first-party plugin, there is nothing to remove).
if [ -d "$HOME/.config/hexciri/plugins/pizza.dirty.nyxiri-workspaces/.git" ]; then
  if "$_NYX_CLI" plugin disable hexciri.workspaces >/dev/null 2>&1; then
    info "  stock workspaces disabled (Nyxiri workspaces active): hexciri.workspaces"
  else
    warn "  stock workspaces could not be disabled (shell not running, disable it with: hexciri plugin disable hexciri.workspaces)"
  fi
fi
# Bar: switch to Nyxiri only when the user opted in and the bar plugin
# is newly installed this run. A re-add never switches it: if a re-add's
# enable flipped the bar away from the recorded choice, put it back.
# bar use edits shell.json directly (no shell IPC), so it works from
# tty3 too.
if [ "${_NYX_BAR_NEW:-0}" = "1" ]; then
  if "$_NYX_CLI" bar use pizza.dirty.nyxiri >/dev/null 2>&1; then
    info "  bar set to Nyxiri: pizza.dirty.nyxiri (opt-in install)"
  else
    warn "  Nyxiri bar could not be set (run after first login: hexciri bar use pizza.dirty.nyxiri)"
  fi
elif [ "${IS_RERUN:-0}" = "1" ]; then
  if [ -n "$_NYX_BAR_BEFORE" ] && [ "$_NYX_BAR_BEFORE" != "pizza.dirty.nyxiri" ]; then
    _nyx_bar_now="$(jq -r '.bar.id // empty' "$HOME/.config/hexciri/shell.json" 2>/dev/null || echo "")"
    if [ "$_nyx_bar_now" != "$_NYX_BAR_BEFORE" ]; then
      "$_NYX_CLI" bar use "$_NYX_BAR_BEFORE" >/dev/null 2>&1 && info "  bar choice kept: $_NYX_BAR_BEFORE (re-run, Nyxiri re-add did not switch it)" || warn "  bar choice changed to ${_nyx_bar_now:-stock} by the Nyxiri re-add, restore it with: hexciri bar use $_NYX_BAR_BEFORE"
    fi
    unset _nyx_bar_now
  fi
fi
unset _NYX_CLI _NYX_VALIDATE _NYX_BAR_BEFORE _NYX_PLUGINS_BEFORE _NYX_BAR_NEW

step "Installing Hexciri theme hooks (~/.config/hexciri/hooks/theme-set.d)"
mkdir -p "$HOME/.config/hexciri/hooks/theme-set.d" "$HOME/.config/hexciri/hooks/lib"
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-env.sh" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-env.sh" "$HOME/.config/hexciri/hooks/lib/theme-env.sh"
  info "  theme hook: hooks/lib/theme-env.sh installed (THPM-port runtime, colors + config reader)"
else
  die "v2/hexciri-theme-env.sh not in the installer tree, theme hooks cannot read the active palette"
fi
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-nautilus.fragment.css" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-nautilus.fragment.css" "$HOME/.config/hexciri/hooks/lib/nautilus-gtk4.fragment.css"
fi
for _hook in "hexciri-theme-hook-gtk.sh:10-hexciri-gtk" "hexciri-theme-hook-adapta.sh:11-hexciri-adapta" "hexciri-theme-hook-thpm.sh:20-hexciri-thpm"; do
  _hook_src="${_hook%%:*}"; _hook_dst="${_hook##*:}"
  if [ -f "$HEXCIRI_REPO_ROOT/v2/$_hook_src" ]; then
    cp -a "$HEXCIRI_REPO_ROOT/v2/$_hook_src" "$HOME/.config/hexciri/hooks/theme-set.d/$_hook_dst"
    chmod +x "$HOME/.config/hexciri/hooks/theme-set.d/$_hook_dst"
    info "  theme hook: theme-set.d/$_hook_dst installed"
  else
    die "v2/$_hook_src not in the installer tree, theme hook $_hook_dst cannot be installed"
  fi
done
unset _hook _hook_src _hook_dst
# theme-hook.toml is a USER setting: seed once, never overwrite on a
# re-run. Adapta stays off by default; flip [gtk] adapta=true after
# cloning signaldirective/Adapta to ~/.themes/Adapta.
if [ ! -f "$HOME/.config/hexciri/theme-hook.toml" ]; then
  if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-hook.toml" ]; then
    cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-hook.toml" "$HOME/.config/hexciri/theme-hook.toml"
    info "  theme hook config seeded: ~/.config/hexciri/theme-hook.toml ([gtk] adapta=false)"
  else
    warn "  v2/hexciri-theme-hook.toml not in the installer tree, theme hooks use their built-in defaults"
  fi
else
  info "  theme hook config kept: ~/.config/hexciri/theme-hook.toml (re-run, your settings preserved)"
fi
# Enable THPM steam here, not in the THPM step: the theme is applied
# by now, so THPM can generate the Steam palette from the staged
# colors.toml. Only when Steam is installed and the steam-adwaita
# checkout exists; otherwise it stays disabled for `thpm enable steam`.
if command -v thpm >/dev/null 2>&1 && command -v steam >/dev/null 2>&1 && [ -d "$HOME/.local/share/steam-adwaita" ]; then
  thpm enable steam >/tmp/hexciri-thpm-steam.log 2>&1 && info "  THPM steam integration enabled (Steam + steam-adwaita present)" || warn "  thpm enable steam failed (see /tmp/hexciri-thpm-steam.log), Steam theming stays off until: thpm doctor steam"
elif command -v thpm >/dev/null 2>&1; then
  info "  THPM steam integration left disabled (enable with: thpm enable steam, once Steam is installed)"
fi

# --- theme-link (Phase 2, 2026-11-24, Devi: Omarchy blocked Lua from themes) ---
# Omarchy 4.0.1 (#7884) stages only colors.toml / light.mode / images
# from a git-installed theme: *.lua, alacritty.toml, foot.ini,
# ghostty.conf, kitty.conf and vscode.json are ignored, because staging
# one would run its author's code. That makes some themes less special.
# theme-link (ministry-of-taste/theme-link, by the THPM author) brings
# it back unofficially: it clones a theme repo into a user-owned store
# (~/.config/theme-link-store/<name>) and symlinks it into the themes
# dir. The forked hexciri-theme-set treats a symlinked theme dir as a
# trusted local working copy (theme_came_from_a_repo() is false for a
# symlink, and hexciri-theme-extras skips symlinks the same way), so
# the whole theme stages, Lua included.
# theme-link is a tool, NOT a theme-set.d hook: it never activates a
# theme, never updates one, never runs theme code. This step only
# installs the tool and seeds its config; Devi adds themes himself
# with `hexciri theme link <url>` (or `theme-link add <url>`),
# confirms the trust warning himself, and applies with
# `hexciri theme set <name>`. No theme is ever auto-added here.
# Best-effort, never dies: without it, theme install/set still work,
# just without the Lua restore.
step "Installing theme-link (trusted theme symlinks, restores theme Lua)"
THEME_LINK_SRC="$HOME/.local/opt/theme-link"
THEME_LINK_PIN="76def15f239fad04464bc3e1ab996e1a1e00c526"
if command -v git >/dev/null 2>&1; then
  if [ -d "$THEME_LINK_SRC/.git" ]; then
    git -C "$THEME_LINK_SRC" fetch --quiet origin 2>/dev/null && git -C "$THEME_LINK_SRC" checkout --quiet "$THEME_LINK_PIN" 2>/dev/null && info "  theme-link source updated to pinned $THEME_LINK_PIN" || warn "  theme-link source checkout failed, keeping existing checkout at $THEME_LINK_SRC"
  else
    git clone --quiet https://github.com/ministry-of-taste/theme-link.git "$THEME_LINK_SRC" 2>/dev/null && git -C "$THEME_LINK_SRC" checkout --quiet "$THEME_LINK_PIN" 2>/dev/null && info "  theme-link source cloned, pinned $THEME_LINK_PIN" || warn "  theme-link source clone failed, hexciri theme link will not be available"
  fi
else
  warn "  git not found, theme-link source install skipped"
fi
if [ -x "$THEME_LINK_SRC/theme-link" ]; then
  if [ "$(git -C "$THEME_LINK_SRC" rev-parse HEAD 2>/dev/null || echo none)" = "$THEME_LINK_PIN" ]; then
    if (cd "$THEME_LINK_SRC" && make install >/tmp/hexciri-theme-link-install.log 2>&1); then
      info "  theme-link installed: $(theme-link --version 2>/dev/null || echo theme-link) (make install -> ~/.local/bin/theme-link)"
    elif install -Dm755 "$THEME_LINK_SRC/theme-link" "$HOME/.local/bin/theme-link" 2>/dev/null; then
      info "  theme-link installed: $(theme-link --version 2>/dev/null || echo theme-link) (direct install, make failed)"
    else
      warn "  theme-link install failed (see /tmp/hexciri-theme-link-install.log), hexciri theme link will not be available"
    fi
  else
    warn "  theme-link checkout is not at pinned $THEME_LINK_PIN, not installing it (inspect: git -C $THEME_LINK_SRC rev-parse HEAD)"
  fi
fi
# Config: seed-once, never overwrite. The upstream default themes_dir
# is ~/.config/omarchy/themes, which Hexciri never reads (user themes
# live in ~/.config/hexciri/themes); without this override every link
# would land in the wrong dir and do nothing. theme-link parses this
# file as data, it is never sourced or evaluated.
if [ ! -f "$HOME/.config/theme-link/config" ]; then
  mkdir -p "$HOME/.config/theme-link"
  cat > "$HOME/.config/theme-link/config" <<'THEME_LINK_CONFIG_EOF'
# theme-link config (Hexciri). Values are data, never shell code.
store_dir = ~/.config/theme-link-store
themes_dir = ~/.config/hexciri/themes
THEME_LINK_CONFIG_EOF
  info "  theme-link config seeded: ~/.config/theme-link/config (themes_dir = ~/.config/hexciri/themes)"
else
  info "  theme-link config kept: ~/.config/theme-link/config (re-run, your settings preserved)"
fi
# Verify the resolved config actually points at Hexciri's themes dir.
if command -v theme-link >/dev/null 2>&1; then
  if theme-link config show 2>/dev/null | grep -q "themes_dir = \"$HOME/.config/hexciri/themes\""; then
    info "  theme-link ready: $(theme-link --version 2>/dev/null || echo theme-link) (add a trusted theme with: hexciri theme link <git-url>)"
  else
    warn "  theme-link config does not point at ~/.config/hexciri/themes, hexciri theme link refuses until it does (theme-link config show)"
  fi
fi
unset THEME_LINK_SRC THEME_LINK_PIN
# themes.list seed-once, never overwrite: the declarative list
# `hexciri theme sync` reads. Comments only on first seed; Devi adds
# the theme repos he wants, one git URL per line. A missing list file
# makes theme-sync refuse outright, and an empty list never removes
# anything, so seeding this file can never delete a theme.
if [ ! -f "$HOME/.config/hexciri/themes.list" ]; then
  mkdir -p "$HOME/.config/hexciri/themes"
  cat > "$HOME/.config/hexciri/themes.list" <<'THEMES_LIST_EOF'
# Hexciri themes, one git URL per line. `hexciri theme sync` clones the
# missing ones, pulls the present ones (--ff-only), and removes git
# checkouts in ~/.config/hexciri/themes/ that are no longer listed.
# Never touches stock themes, theme-link symlinks, hand-made themes,
# or the current theme. Run `hexciri theme sync --dry-run` first.
# Example (commented out, add yours below):
# https://github.com/example/omarchy-example-theme.git
THEMES_LIST_EOF
  info "  themes.list seeded: ~/.config/hexciri/themes.list (comments only, add theme URLs to sync them)"
else
  info "  themes.list kept: ~/.config/hexciri/themes.list (re-run, your list preserved)"
fi

# Minimal re-apply: Spotify wrapper + trim run in full mode and in
# --re-apply-provision mode. --re-apply (fork patch) skips them.
if [ "${REAPPLY:-0}" != "1" ]; then
# --- Spotify fallback wrapper (post-placement) ---
# The Super+Shift+M bind calls `spotify`. The AUR `spotify` package
# provides that binary directly, but if only the Arch extra
# spotify-launcher fallback installed, its binary is spotify-launcher
# and the bind would miss. In that case write a tiny `spotify` wrapper
# into /usr/share/hexciri/bin/ (on the uwsm PATH, like the Strata link
# above), so the bind works either way. Never overwrites a real spotify.
if ! command -v spotify >/dev/null 2>&1 && command -v spotify-launcher >/dev/null 2>&1; then
  printf '#!/bin/sh\nexec spotify-launcher "$@"\n' | sudo tee "$HEXCIRI_PATH/bin/spotify" >/dev/null
  sudo chmod +x "$HEXCIRI_PATH/bin/spotify" 2>/dev/null || true
  info "Spotify wrapper installed: $HEXCIRI_PATH/bin/spotify -> spotify-launcher (AUR spotify was not installed)"
elif command -v spotify >/dev/null 2>&1; then
  info "Spotify present (spotify command)"
else
  warn "Spotify not installed, Super+Shift+M will fail until it is. Install by hand: yay -S spotify"
fi

# --- Trim bloat, and keep it trimmed on updates ---
# Devi 2026-11-23: 1322 packages is a bit much. The Haskell tree came from
# apostrophe -> python-pypandoc -> pandoc-cli -> ghc-libs + ~200 haskell-*
# packages; apostrophe is out of APP_PKGS and its tree is removed here and
# foot was in the trim list until 2026-11-24: it is NOT installed by
# default (Kitty is the default terminal) but it IS an Install > Terminal
# option now, so trimming it on every update would uninstall a terminal
# the user just chose. btop is still trimmed (bottom over btop, and it
# was only ever left over from the EndeavourOS base / an earlier install).
# 2026-11-23: ghostwriter, meld, ncspot, neovim, obsidian, pinta and
# xterm join the trim list (Devi does not want them, see the trim script
# comment for what each one was). They are out of every package list too,
# so they cannot come back through an install. vim and stoken were in the
# list until 2026-11-24, when the first full hexciri update showed why
# they cannot be: vim is required by ex-vi-compat (Arch base) and stoken
# by openconnect, so pacman -Rns refuses both on every run and the
# post-update hook printed the refusal after every update. They stay
# installed; their app entries are hidden with NoDisplay instead.
# Reinstall is prevented three ways: the packages are out of every list
# (CORE_PKGS / APP_PKGS here, v2/hexciri-base.packages), this step removes
# them if present, and a post-update hook (below) re-runs the trim on every
# hexciri-update, so a future -Syu that would pull one back as a dependency
# gets it removed again right after. pacman -Syu itself never installs new
# packages, so the hook is the backstop, not the mechanism.
step "Trimming bloat: btop, apostrophe, pandoc-cli / Haskell, ghostwriter, meld, ncspot, neovim, obsidian, pinta, xterm"
cat > "$HOME/.local/bin/hexciri-trim-bloat" <<'TRIM_EOF'
#!/bin/bash
# Hexciri 2.0: remove packages Devi does not want, best-effort, idempotent.
# Runs at install time and from the post-update hook, so an update can never
# leave them installed again. pacman -Rns refuses if something still depends
# on a package, so a removal here is always safe. Plain sudo, NOT sudo -n:
# the installer runs interactively from a terminal, and sudo -n fails
# silently once the sudo timestamp expires mid-install (the install takes
# far longer than the timeout), so every removal was quietly "kept" and
# vim + stoken survived the trim on the last live run.
# 2026-11-23 removals, Devi does not want them: ghostwriter (markdown
# editor, was the omawrite substitute), meld (diff/merge tool), ncspot
# (Spotify TUI, was the cliamp substitute), neovim (nano ships in Arch
# base and is the editor fallback now), obsidian (notes), pinta (image
# editor), xterm (provides xterm AND uxterm, both entries gone with the
# one package). vim and stoken are deliberately NOT here anymore
# (2026-11-24): vim is required by ex-vi-compat and stoken by openconnect,
# so pacman -Rns refuses both, and the post-update hook re-trying them on
# every update printed "removing vim breaks dependency" / "removing
# stoken breaks dependency" right after Restarting shell. Both stay
# installed; the NoDisplay hide below is what actually removes their
# entries (vim.desktop, stoken-gui.desktop, stoken-gui-small.desktop)
# from the grid. yad is deliberately NOT here:
# eos-bash-shared depends on it, its entry is hidden instead (above).
for _pkg in btop apostrophe pandoc-cli ghostwriter meld ncspot neovim obsidian pinta xterm; do
  if pacman -Q "$_pkg" >/dev/null 2>&1; then
    if sudo pacman -Rns --noconfirm "$_pkg" >/dev/null 2>&1; then
      echo "trim-bloat: removed $_pkg"
    else
      echo "trim-bloat: kept $_pkg (removal refused, something depends on it)" >&2
    fi
  fi
done
unset _pkg
# Haskell orphans left behind by pandoc-cli: only remove packages that are
# actually orphaned (nothing depends on them), never a blanket purge.
_orphans="$(pacman -Qtdq 2>/dev/null || true)"
if [ -n "$_orphans" ]; then
  _hs="$(printf '%s\n' "$_orphans" | grep -E '^(ghc-libs|haskell-|hslua-cli|pandoc-cli)' || true)"
  if [ -n "$_hs" ]; then
    # shellcheck disable=SC2086
    sudo pacman -Rns --noconfirm $_hs 2>/dev/null && echo "trim-bloat: removed orphaned Haskell packages" || echo "trim-bloat: Haskell orphan removal refused" >&2
  fi
  unset _hs
fi
unset _orphans
TRIM_EOF
chmod +x "$HOME/.local/bin/hexciri-trim-bloat"
sudo ln -sf "$HOME/.local/bin/hexciri-trim-bloat" "$HEXCIRI_PATH/bin/hexciri-trim-bloat" 2>/dev/null || warn "could not link hexciri-trim-bloat into $HEXCIRI_PATH/bin"
sudo -v || warn "sudo timestamp refresh failed, trim-bloat removals may be refused"
"$HOME/.local/bin/hexciri-trim-bloat" || warn "trim-bloat run failed, not fatal"
# Hide fallback, 2026-11-23: if a trim package still cannot be removed (a
# dependency holds it), its app entry must still not show in the grid.
# vim ships vim.desktop, stoken ships stoken-gui.desktop +
# stoken-gui-small.desktop (the small-window entry is stoken-gui-small,
# NOT stoken-small, which is why the hide missed it and Software Token
# (small) persisted). stoken is a dependency of openconnect, so pacman
# -Rns refuses to remove it; the NoDisplay hide below is the real removal.
for _hide_desk in vim.desktop stoken-gui.desktop stoken-gui-small.desktop; do
  if [ -f "/usr/share/applications/$_hide_desk" ] && [ ! -f "$HOME/.local/share/applications/$_hide_desk" ]; then
    cp -a "/usr/share/applications/$_hide_desk" "$HOME/.local/share/applications/$_hide_desk"
    printf 'NoDisplay=true\n' >> "$HOME/.local/share/applications/$_hide_desk"
    info "Hidden: $_hide_desk (package still installed, entry hidden from app grid)"
  elif [ -f "$HOME/.local/share/applications/$_hide_desk" ] && ! grep -q '^NoDisplay=' "$HOME/.local/share/applications/$_hide_desk"; then
    printf 'NoDisplay=true\n' >> "$HOME/.local/share/applications/$_hide_desk"
    info "Hidden: $_hide_desk (entry hidden from app grid)"
  fi
done
unset _hide_desk
# YAD settings: Devi does not want the "YAD settings" app entry. yad
# itself CANNOT be removed: eos-bash-shared depends on yad, and
# eos-bash-shared is required by welcome, eos-log-tool, eos-rankmirrors,
# reflector-simple, eos-apps-info, eos-update-notifier and akm, several of
# which Devi keeps (Welcome, Reflector Simple, EOS apps info, EOS log
# tool are in his apps grid). pacman -Rns yad is refused anyway. Hide
# just the yad-settings desktop entry with a NoDisplay override instead;
# the Icon Browser entry (yad-icon-browser, same package) is untouched,
# Devi did not ask to remove it.
mkdir -p "$HOME/.local/share/applications"
if [ -f /usr/share/applications/yad-settings.desktop ]; then
  if [ ! -f "$HOME/.local/share/applications/yad-settings.desktop" ]; then
    cp -a /usr/share/applications/yad-settings.desktop "$HOME/.local/share/applications/yad-settings.desktop"
  fi
  if ! grep -q '^NoDisplay=' "$HOME/.local/share/applications/yad-settings.desktop"; then
    printf 'NoDisplay=true\n' >> "$HOME/.local/share/applications/yad-settings.desktop"
  fi
  info "Hidden: YAD settings app entry (NoDisplay override, yad package kept for EOS tools)"
else
  warn "yad-settings.desktop not found, nothing to hide"
fi

# Post-update hook: hexciri-update runs `hexciri-hook post-update` at the end
# of every update, and the hook runner executes every script in
# ~/.config/hexciri/hooks/post-update.d/. This one re-runs the trim, so the
# removed packages can never come back through an update.
mkdir -p "$HOME/.config/hexciri/hooks/post-update.d"
cat > "$HOME/.config/hexciri/hooks/post-update.d/10-hexciri-trim-bloat" <<'HOOK_EOF'
#!/bin/bash
# Hexciri post-update hook: re-run the bloat trim after every hexciri-update.
# Best-effort, never fails the update: the hook runner already tolerates a
# non-zero exit, and trim-bloat itself never exits non-zero on a refusal.
hexciri-trim-bloat 2>/dev/null || "$HOME/.local/bin/hexciri-trim-bloat" 2>/dev/null || true
HOOK_EOF
chmod +x "$HOME/.config/hexciri/hooks/post-update.d/10-hexciri-trim-bloat"
info "Installed: hexciri-trim-bloat + post-update hook (btop/apostrophe/pandoc-cli/ghostwriter/meld/ncspot/neovim/obsidian/pinta/xterm stay removed; foot is an Install > Terminal option now, not trimmed; vim/stoken stay installed, unremovable, entries hidden)"
# First-update marker: the install itself is the first update, so mark it.
# Without this, hexciri-update-available counts every pending pacman update
# on first boot and the update icon never clears.
if [ -x "$HEXCIRI_PATH/bin/hexciri-done" ]; then
  "$HEXCIRI_PATH/bin/hexciri-done" mark first-update 2>/dev/null && info "Marked: first-update done (update icon will not count pending Arch updates)" || warn "could not mark first-update, update icon may show until the first hexciri-update"
fi

fi # end Spotify + trim guard (minimal re-apply: skipped in fork-only mode)
# Provision re-apply marker write (2026-11-24): placement is skipped
# in --re-apply-provision mode, so nothing else writes the installer
# sha / fingerprints. Write them here, after the config steps ran,
# or the next update would see a stale marker and re-run again.
if [ "${REAPPLY_PROV:-0}" = "1" ]; then
  installer_tree_sha | sudo tee "$HEXCIRI_PATH/.installer-sha" >/dev/null || warn "could not write installer sha marker, hexciri update will re-run the installer every time"
  printf '%s\n' "$(upstream_fingerprint)" | sudo tee "$HEXCIRI_PATH/.upstream-fingerprint" >/dev/null
  printf '%s\n' "$(patch_fingerprint)" | sudo tee "$HEXCIRI_PATH/.patch-fingerprint" >/dev/null
  printf '%s\n' "$(fork_fingerprint)" | sudo tee "$HEXCIRI_PATH/.fork-fingerprint" >/dev/null
  printf '%s\n' "$(provision_fingerprint)" | sudo tee "$HEXCIRI_PATH/.provision-fingerprint" >/dev/null
  printf '%s\n' "$(system_fingerprint)" | sudo tee "$HEXCIRI_PATH/.system-fingerprint" >/dev/null
  info "Provision re-apply done: installer marker + fingerprints updated, fork and packages untouched"
fi
# --- Health check, like v1 ---
# Post-install sanity before the reboot offer, so a broken bring-up is
# caught here, not at the login screen. Best-effort reads only.

step "Post-install health check"
HC_FAIL=0
# hc_info: health per-item status. On a fresh install it prints (useful
# bring-up checklist); on a re-run it is noise -- only warnings and the
# final "Health check: clean / flagged" line show.
hc_info() { if [ "${IS_RERUN:-0}" != "1" ]; then info "$1"; fi; }
if command -v systemctl >/dev/null 2>&1; then
  FAILED_UNITS="$(systemctl --failed --no-legend 2>/dev/null || true)"
  if [ -z "$FAILED_UNITS" ]; then
    hc_info "  systemd: no failed units"
  else
    warn "  systemd: FAILED units present:"
    printf '%s\n' "$FAILED_UNITS"
    HC_FAIL=1
  fi
fi
for _check in "$HEXCIRI_PATH/bin/hexciri-launch-shell" "$HEXCIRI_PATH/bin/hexciri-menu" "$HEXCIRI_PATH/bin/hexciri-shell" "$HEXCIRI_PATH/shell/shell.qml" "$HEXCIRI_PATH/default/hypr/bootstrap.lua" "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hexciri/shell.json" /usr/share/wayland-sessions/hexciri.desktop; do
  if [ -e "$_check" ]; then
    hc_info "  present: $_check"
  else
    warn "  MISSING: $_check"
    HC_FAIL=1
  fi
done
# bootstrap.lua needs a content check, not just -e: a 0-byte file passes
# -e and still bricks the next boot (sim8, 2026-11-24).
if bootstrap_ok "$HEXCIRI_PATH/default/hypr/bootstrap.lua"; then
  hc_info "  bootstrap.lua: valid ($(wc -c < "$HEXCIRI_PATH/default/hypr/bootstrap.lua" | tr -d ' ') bytes, package.path + HEXCIRI_PATH present)"
else
  warn "  bootstrap.lua: MISSING or corrupt (empty/truncated), next boot trips emergency mode (repair: hexciri update hexciri --force)"
  HC_FAIL=1
fi
if hyprlua_ok "$HEXCIRI_PATH/default/hypr/hexciri.lua"; then
  hc_info "  hexciri.lua: valid ($(wc -c < "$HEXCIRI_PATH/default/hypr/hexciri.lua" | tr -d ' ') bytes, helpers require present, required by hyprland.lua:17)"
else
  warn "  hexciri.lua: MISSING or corrupt (empty/truncated or no helpers require), next boot trips emergency mode (repair: hexciri update hexciri --force, then: hyprctl reload)"
  HC_FAIL=1
fi
if command -v quickshell >/dev/null 2>&1; then
  if quickshell --version >/dev/null 2>&1; then
    QS_VER="$(quickshell --version 2>/dev/null || true)"
    hc_info "  quickshell: $QS_VER"
  else
    warn "  quickshell binary exists but --version failed"
    HC_FAIL=1
  fi
else
  warn "  quickshell binary not found"
  HC_FAIL=1
fi
if systemctl is-enabled --quiet sddm 2>/dev/null; then
  hc_info "  sddm: enabled"
else
  warn "  sddm: not enabled"
  HC_FAIL=1
fi
if [ -f /usr/share/sddm/themes/hexciri/Main.qml ]; then
  hc_info "  sddm theme: /usr/share/sddm/themes/hexciri (Main.qml present)"
else
  warn "  sddm theme: hexciri theme not installed, SDDM uses its default theme (cosmetic only, login still works)"
fi
if [ -f /var/lib/sddm/state.conf ] && grep -q '^User=' /var/lib/sddm/state.conf 2>/dev/null; then hc_info "  sddm last user: $(grep '^User=' /var/lib/sddm/state.conf | cut -d= -f2)"; else warn "  sddm last user: /var/lib/sddm/state.conf has no Last User, first SDDM login relies on the theme's first-user fallback (re-run the installer to seed it)"; fi
command -v kitty >/dev/null 2>&1 && hc_info "  terminal: kitty present" || warn "  terminal: kitty NOT installed, terminal binds fall back to xdg-terminal-exec"
command -v tmux >/dev/null 2>&1 && hc_info "  tmux: present" || warn "  tmux: NOT installed, Learn > Tmux and Super+Alt+Return will fail"
command -v udiskie >/dev/null 2>&1 && hc_info "  udiskie: present" || warn "  udiskie: NOT installed, autostart will pop a Command not found error"
if command -v brave-origin >/dev/null 2>&1; then
  hc_info "  browser: Brave Origin present (default: $(xdg-settings get default-web-browser 2>/dev/null || echo unknown))"
else
  warn "  browser: Brave Origin NOT installed, Super+Shift+Return / Super+Shift+B will fail"
fi
if command -v zathura >/dev/null 2>&1; then hc_info "  pdf: zathura present"; else warn "  pdf: zathura NOT installed"; fi
if [ -f /etc/pam.d/hexciri-lock-password ]; then hc_info "  lock PAM: /etc/pam.d/hexciri-lock-password present (System > Lock works)"; else warn "  lock PAM: missing, System > Lock returns missing-pam (run: sudo hexciri-apply-lock)"; fi
if sudo test -f /etc/sudoers.d/hexciri-theme-browser 2>/dev/null || [ -f /etc/sudoers.d/hexciri-theme-browser ]; then hc_info "  browser policy sudoers: present (theme switch repaints Brave)"; else warn "  browser policy sudoers: missing, theme switch reports hexciri-theme-set-browser failed"; fi
# (sudo test first: /etc/sudoers.d can be 0750 root, so a plain -f as the
# user reports a present file as missing.)
if pacman -Q fprintd >/dev/null 2>&1 || command -v fprintd-enroll >/dev/null 2>&1; then hc_info "  fingerprint: fprintd present (Setup > Security > Fingerprint)"; else warn "  fingerprint: fprintd NOT installed, Setup > Security > Fingerprint will fail"; fi
# (command -v fprintd is wrong: the daemon lives at /usr/lib/fprintd,
# the user CLIs are fprintd-enroll/verify/list.)
if command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'; then
  if grep -q 'pam_unix.so try_first_pass likeauth nullok' /etc/pam.d/sddm 2>/dev/null && grep -q pam_fprintd.so /etc/pam.d/sddm 2>/dev/null; then
    hc_info "  fingerprint: SDDM login has pam_unix first, then pam_fprintd (password alone logs in)"
  elif grep -q pam_fprintd.so /etc/pam.d/sddm 2>/dev/null; then
    warn "  fingerprint: /etc/pam.d/sddm has pam_fprintd but no pam_unix-first line (old order: fingerprint demanded after password)"
  else
    warn "  fingerprint: enrolled, but /etc/pam.d/sddm has no pam_fprintd, SDDM login stays password-only"
  fi
fi
if ! hexciri_has_fingerprint_reader 2>/dev/null; then
  if grep -q pam_fprintd.so /etc/pam.d/sddm 2>/dev/null; then
    warn "  fingerprint: /etc/pam.d/sddm still has pam_fprintd but no fingerprint reader was detected, SDDM password login may fail (re-run the installer to strip it)"
  else
    hc_info "  fingerprint: no reader detected, SDDM is password-only"
  fi
fi
if grep -q 'pam_gnome_keyring.so' /etc/pam.d/sddm 2>/dev/null && grep -q 'pam_gnome_keyring.so auto_start' /etc/pam.d/sddm 2>/dev/null; then hc_info "  keyring: SDDM PAM unlocks gnome-keyring at login (Brave launches with no password prompt)"; else warn "  keyring: /etc/pam.d/sddm has no pam_gnome_keyring.so, Brave asks for the keyring password on every launch (re-run the installer)"; fi
command -v gnome-keyring-daemon >/dev/null 2>&1 && hc_info "  keyring daemon: gnome-keyring-daemon present" || warn "  keyring daemon: gnome-keyring-daemon NOT installed, Brave has no Secret Service backend"
if command -v mpv >/dev/null 2>&1; then hc_info "  video: mpv present"; else warn "  video: mpv NOT installed"; fi
if command -v gpu-screen-recorder >/dev/null 2>&1; then hc_info "  screenrecord: gpu-screen-recorder present"; else warn "  screenrecord: gpu-screen-recorder NOT installed, menu Capture > Screenrecord will fail"; fi
if command -v localsend >/dev/null 2>&1; then hc_info "  share: localsend present (localsend-bin)"; else warn "  share: localsend NOT installed, menu Share > Receive will fail (yay -S localsend-bin)"; fi
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then if sudo firewall-cmd --list-ports 2>/dev/null | grep -q '53317/tcp' && sudo firewall-cmd --list-ports 2>/dev/null | grep -q '53317/udp'; then hc_info "  share: firewalld allows 53317/tcp+udp (LocalSend discovery + transfer)"; else warn "  share: firewalld does not allow 53317, other devices may not see this laptop's LocalSend (run: sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp && sudo firewall-cmd --reload)"; fi; fi
if command -v nmcli >/dev/null 2>&1; then if nmcli -t -f TYPE connection show 2>/dev/null | grep -q "802-11-wireless"; then hc_info "  network: a Wi-Fi connection is saved (fallback if dock Ethernet drops)"; else warn "  network: no Wi-Fi connection saved, Ethernet is the only path (set one up with: nmtui, so Wi-Fi is the fallback when the dock drops)"; fi; fi
if command -v fastfetch >/dev/null 2>&1; then hc_info "  fastfetch: present"; else warn "  fastfetch: NOT installed"; fi
if [ -f /etc/fastfetch/config.jsonc ]; then hc_info "  fastfetch config: /etc/fastfetch/config.jsonc present (Hexciri config)"; elif [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then hc_info "  fastfetch config: ~/.config/fastfetch/config.jsonc present"; else warn "  fastfetch config: not placed, stock config in use"; fi
grep -q 'hexciri-launch-about --render' "$HEXCIRI_PATH/bin/hexciri-launch-about" 2>/dev/null && grep -q 'hexciri-launch-or-focus-tui --app-id=org.hexciri.about' "$HEXCIRI_PATH/bin/hexciri-launch-about" 2>/dev/null && grep -q '_about_fit' "$HEXCIRI_PATH/bin/hexciri-launch-about" 2>/dev/null && hc_info "  about: launch-about is the two-mode fastfetch (--render runs inside the terminal, no bash -c quoting trap)" || warn "  about: launch-about is not the two-mode --render script, System > About may open and close at once"
if grep -q 'icon.txt' /etc/fastfetch/config.jsonc 2>/dev/null; then hc_info "  about logo: fastfetch config logo points at icon.txt"; elif grep -q 'hexciri-nb.png' /etc/fastfetch/config.jsonc 2>/dev/null && [ -f "$HOME/.config/fastfetch/hexciri-nb.png" ]; then hc_info "  about logo: fastfetch config logo points at hexciri-nb.png (present)"; else warn "  about logo: fastfetch config logo does not point at icon.txt or hexciri-nb.png, About may render a blank logo column"; fi
if grep -q '^gtk-theme-name=Adwaita$' "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null && ! grep -q 'Adwaita-dark' "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null; then hc_info "  gtk picker: settings.ini theme=Adwaita, no Adwaita-dark (GTK4 dark comes from prefer-dark)"; else warn "  gtk picker: settings.ini still names Adwaita-dark or is missing, file picker will come up light with ghost text"; fi
if command -v dbus-run-session >/dev/null 2>&1; then _gtk_scheme_now="$(dbus-run-session -- gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo unknown)"; if [ "$_gtk_scheme_now" = "'prefer-dark'" ]; then hc_info "  gtk picker: dconf color-scheme=prefer-dark (portal dialog reads dconf on Wayland, not settings.ini)"; else warn "  gtk picker: dconf color-scheme=$_gtk_scheme_now, portal file picker may stay light (expected 'prefer-dark' for a dark theme)"; fi; unset _gtk_scheme_now; fi
[ -x /usr/lib/hexciri/speedtest ] && hc_info "  speedtest: /usr/lib/hexciri/speedtest present (Speed Test > Network works)" || warn "  speedtest: /usr/lib/hexciri/speedtest missing, Speed Test > Network will show speedtest.failed"
command -v btm >/dev/null 2>&1 && hc_info "  activity monitor: btm present (Super+Shift+T)" || warn "  activity monitor: btm NOT installed, Super+Shift+T will fail (package: bottom, binary: btm)"
if command -v hexciri-settings >/dev/null 2>&1; then hc_info "  settings: hexciri-settings present (Super+Ctrl+S, launcher: Hexciri Settings)"; else warn "  settings: hexciri-settings NOT installed, Super+Ctrl+S will notify instead of opening (the next hexciri update retries the build automatically, log: ~/.cache/hexciri-settings-build/build.log)"; fi
[ -x "$HEXCIRI_PATH/bin/hexciri-launch-settings" ] && hc_info "  settings launcher: hexciri-launch-settings present (Super+Ctrl+S notifies when the app is missing)" || warn "  settings launcher: hexciri-launch-settings missing from $HEXCIRI_PATH/bin, Super+Ctrl+S will fail silently"
# Nyxiri plugins (2026-11-24): each INSTALLED one must sit on nyx, or
# the next `hexciri plugin update` pulls main. Absent is fine, Nyxiri
# is opt-in, not base install.
for _nyx_id in pizza.dirty.nyxiri pizza.dirty.nyxiri-menu pizza.dirty.nyxiri-workspaces pizza.dirty.clock pizza.dirty.weather pizza.dirty.arch-updates pizza.dirty.wallcraft; do
  if [ -d "$HOME/.config/hexciri/plugins/$_nyx_id/.git" ]; then
    _nyx_br="$(git -C "$HOME/.config/hexciri/plugins/$_nyx_id" branch --show-current 2>/dev/null || echo unknown)"
    if [ "$_nyx_br" = "nyx" ]; then
      hc_info "  nyx plugin: $_nyx_id on nyx"
    else
      warn "  nyx plugin: $_nyx_id on branch '${_nyx_br:-unknown}', expected nyx (repair: hexciri update)"
      HC_FAIL=1
    fi
  else
    hc_info "  nyx plugin: $_nyx_id not installed (optional, --with-nyxiri)"
  fi
done
for _nyx_id in pizza.dirty.cpurr pizza.dirty.bongocat; do
  if [ -d "$HOME/.config/hexciri/plugins/$_nyx_id/.git" ]; then
    _nyx_br="$(git -C "$HOME/.config/hexciri/plugins/$_nyx_id" branch --show-current 2>/dev/null || echo unknown)"
    if [ "$_nyx_br" = "nyx" ]; then
      hc_info "  nyx plugin: $_nyx_id on nyx (cats)"
    else
      warn "  nyx plugin: $_nyx_id on branch '${_nyx_br:-unknown}', expected nyx (repair: hexciri update)"
      HC_FAIL=1
    fi
  else
    hc_info "  nyx plugin: $_nyx_id not installed (cats are opt-in, --with-cats)"
  fi
done
unset _nyx_id _nyx_br
command -v opencode >/dev/null 2>&1 && hc_info "  agent: opencode present ($(opencode --version 2>/dev/null | head -1), free models need no account)" || warn "  agent: opencode NOT installed, hexciri-agent / default agent opencode will fail (pacman -S opencode)"
_boot_hc_ok=1; _boot_hc_seen=0; for _f in /efi/loader/loader.conf /boot/loader/loader.conf /boot/efi/loader/loader.conf; do if [ -f "$_f" ]; then _boot_hc_seen=1; grep -q '^timeout 1$' "$_f" 2>/dev/null || _boot_hc_ok=0; fi; done; if [ "$_boot_hc_seen" -eq 1 ] && [ "$_boot_hc_ok" -eq 1 ]; then hc_info "  boot timeout: every loader.conf says timeout 1"; elif [ "$_boot_hc_seen" -eq 0 ]; then _boot_hc_noconf=1; else warn "  boot timeout: a loader.conf does not say timeout 1 (grep timeout in /efi/loader/loader.conf /boot/loader/loader.conf /boot/efi/loader/loader.conf)"; fi; _boot_hc_efi=""; [ -r /sys/firmware/efi/efivars/LoaderConfigTimeout-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f ] && _boot_hc_efi="$(tail -c +5 /sys/firmware/efi/efivars/LoaderConfigTimeout-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f 2>/dev/null | tr -d '\0')"; if [ "$_boot_hc_efi" = "1" ]; then hc_info "  boot timeout EFI: LoaderConfigTimeout=1"; elif [ -n "$_boot_hc_efi" ]; then warn "  boot timeout EFI: LoaderConfigTimeout=$_boot_hc_efi, overrides loader.conf (run: sudo bootctl set-timeout 1)"; else hc_info "  boot timeout EFI: no LoaderConfigTimeout variable, loader.conf controls it"; fi; if [ "${_boot_hc_noconf:-0}" = "1" ] && [ "$_boot_hc_efi" != "1" ]; then warn "  boot timeout: no loader.conf found and LoaderConfigTimeout is not 1 (GRUB or other bootloader?)"; elif [ "${_boot_hc_noconf:-0}" = "1" ]; then hc_info "  boot timeout: no loader.conf on this ESP layout, EFI LoaderConfigTimeout=1 controls it"; fi; unset _boot_hc_ok _boot_hc_seen _boot_hc_efi _boot_hc_noconf _f
command -v strata >/dev/null 2>&1 || [ -x "$HOME/.local/bin/strata" ] || [ -x "$HEXCIRI_PATH/bin/strata" ] && hc_info "  file manager: strata present" || warn "  file manager: strata NOT installed, Super+Shift+F will error until it is"
command -v xdg-terminal-exec >/dev/null 2>&1 && hc_info "  xdg-terminal-exec: present" || warn "  xdg-terminal-exec: not installed, floating terminals use the xdg-terminals.list fast path only"
if command -v spotify >/dev/null 2>&1; then hc_info "  music: spotify present (Super+Shift+M)"; elif command -v spotify-launcher >/dev/null 2>&1; then hc_info "  music: spotify-launcher present (Super+Shift+M via wrapper)"; else warn "  music: Spotify NOT installed, Super+Shift+M will fail"; fi
command -v gnome-calculator >/dev/null 2>&1 && hc_info "  calculator: gnome-calculator present (Super+Shift+Q / Super+Shift+C)" || warn "  calculator: gnome-calculator NOT installed, Super+Shift+Q / Super+Shift+C will fail"
[ -x "$HEXCIRI_PATH/bin/hexciri-web-search" ] && hc_info "  web search: hexciri-web-search present (Super+Shift+S, QS prompt, Brave Origin)" || warn "  web search: hexciri-web-search missing from $HEXCIRI_PATH/bin, Super+Shift+S will fail"
[ -x "$HEXCIRI_PATH/bin/hexciri-theme-sync" ] && hc_info "  theme sync: hexciri-theme-sync present (hexciri theme sync, bulk git themes from ~/.config/hexciri/themes.list)" || warn "  theme sync: hexciri-theme-sync missing from $HEXCIRI_PATH/bin, hexciri theme sync will fail"
command -v hexciri >/dev/null 2>&1 && hc_info "  cli: hexciri present" || warn "  cli: hexciri NOT on PATH, hexciri plugin list will fail"
command -v checkupdates >/dev/null 2>&1 && hc_info "  update check: checkupdates present (update icon)" || warn "  update check: checkupdates NOT installed, update icon never shows"
command -v eos-update >/dev/null 2>&1 && hc_info "  update engine: eos-update present (repo + AUR, --aur)" || warn "  update engine: eos-update NOT installed, hexciri update falls back to pacman -Syu --noconfirm"
grep -q '^ILoveCandy' /etc/pacman.conf 2>/dev/null && hc_info "  pacman bars: ILoveCandy on (Pac-Man eating dots)" || warn "  pacman bars: ILoveCandy NOT set in /etc/pacman.conf, pacman shows the plain bar"
command -v mise >/dev/null 2>&1 && hc_info "  mise: $(mise --version 2>/dev/null || echo present)" || warn "  mise: NOT installed, Omarchy scripts that call mise will fail"
[ -f /etc/mise/conf.d/hexciri-tools.toml ] && hc_info "  mise tools: /etc/mise/conf.d/hexciri-tools.toml present (node, uv, gh, lazy; no AI agents, no Herdr)" || warn "  mise tools: /etc/mise/conf.d/hexciri-tools.toml missing"
[ -f "$HOME/.config/kitty/kitty.conf" ] && hc_info "  kitty config: ~/.config/kitty/kitty.conf present (theme include)" || warn "  kitty config: not placed, Kitty will not load theme colours"
[ -d "$HEXCIRI_PATH/default/themed" ] && hc_info "  theme templates: default/themed present" || warn "  theme templates: default/themed missing, theme-set generates nothing"
[ -f "$HEXCIRI_PATH/default/hypr/bindings/hexciri.lua" ] && [ -f "$HEXCIRI_PATH/default/hypr/apps/hexciri.lua" ] && hc_info "  hexciri lua: bindings/hexciri.lua + apps/hexciri.lua present (custom binds/rules only, Omarchy binds not duplicated)" || warn "  hexciri lua: custom binds/apps Lua missing, monocle cycle / TUI float / mpv+imv opacity will not load"
grep -q 'require("default.hypr.bindings.hexciri")' "$HEXCIRI_PATH/default/hypr/hexciri.lua" 2>/dev/null && hc_info "  hexciri binds wired: hexciri.lua requires default.hypr.bindings.hexciri (Super+Ctrl+S Settings, Super+Shift+S web search, Super+Shift+C calculator register)" || warn "  hexciri binds NOT wired: hexciri.lua does not require default.hypr.bindings.hexciri, Super+Ctrl+S Settings will not register (run hexciri update)"
[ -x "$HOME/.config/hexciri/hooks/theme-set.d/10-hexciri-gtk" ] && [ -x "$HOME/.config/hexciri/hooks/theme-set.d/11-hexciri-adapta" ] && [ -x "$HOME/.config/hexciri/hooks/theme-set.d/20-hexciri-thpm" ] && [ -f "$HOME/.config/hexciri/hooks/lib/theme-env.sh" ] && hc_info "  theme hooks: 10-gtk + 11-adapta + 20-thpm + theme-env.sh present (theme-set.d)" || warn "  theme hooks: a Hexciri theme hook is missing from ~/.config/hexciri/hooks/theme-set.d/, theme switch will skip GTK/Adapta/THPM"
command -v thpm >/dev/null 2>&1 && hc_info "  thpm: $(thpm --version 2>/dev/null || echo present) (source install, not AUR)" || warn "  thpm: NOT installed, theme switch skips THPM integrations (install: git clone OldJobobo/thpm, ./install.sh --no-ui)"
[ -x /usr/local/bin/omarchy ] && hc_info "  thpm compat: /usr/local/bin/omarchy -> hexciri (THPM hardcodes the omarchy CLI)" || warn "  thpm compat: /usr/local/bin/omarchy missing, thpm install/doctor will fail its capability check"
if command -v theme-link >/dev/null 2>&1; then hc_info "  theme-link: $(theme-link --version 2>/dev/null || echo present) (trusted theme symlinks, restores theme Lua)"; else warn "  theme-link: NOT installed, hexciri theme link is unavailable (install: git clone ministry-of-taste/theme-link, make install)"; fi
if command -v theme-link >/dev/null 2>&1 && theme-link config show 2>/dev/null | grep -q "themes_dir = \"$HOME/.config/hexciri/themes\""; then hc_info "  theme-link config: themes_dir = ~/.config/hexciri/themes (links land where Hexciri reads them)"; elif command -v theme-link >/dev/null 2>&1; then warn "  theme-link config: themes_dir is not ~/.config/hexciri/themes, hexciri theme link refuses until it does (theme-link config show)"; fi
[ -x "$HEXCIRI_PATH/bin/hexciri-theme-link" ] && hc_info "  theme link: hexciri-theme-link present (hexciri theme link <git-url>)" || warn "  theme link: hexciri-theme-link missing from $HEXCIRI_PATH/bin, hexciri theme link will fail (theme-link add still works)"
[ -d "$HOME/.local/share/steam-adwaita" ] && hc_info "  steam-adwaita: checkout present (THPM steam target)" || warn "  steam-adwaita: checkout missing at ~/.local/share/steam-adwaita, THPM steam integration stays unavailable (thpm report steam)"
if command -v grim >/dev/null 2>&1 && command -v slurp >/dev/null 2>&1; then hc_info "  screenshot: grim + slurp present (PRINT, hexciri-capture-screenshot)"; else warn "  screenshot: grim/slurp missing, PRINT will fail"; fi
command -v tesseract >/dev/null 2>&1 && hc_info "  OCR: tesseract present (SUPER+CTRL+PRINT capture-text)" || warn "  OCR: tesseract NOT installed, capture-text will fail"
if [ "$HC_FAIL" -eq 0 ]; then
  info "Health check: clean"
else
  warn "Health check: flagged issues above, see the warnings. Reboot may still work, check the logs if it does not."
fi
unset _check

# --- Reload Hyprland config after placement (2026-11-24, Devi) ---
# The 926c9d7 update placed a good hexciri.lua, but the running Hyprland
# kept its stale/emergency config until a manual `hyprctl reload` fixed
# it. Nothing in the update reloaded it: hexciri-update-restart only
# restarts the Quickshell shell, and theme-set reloads Hyprland only
# when a theme actually changes (it was skipped that run). Reload after
# placement so the new Lua tree takes effect in the live session, no
# reboot needed. Best-effort, never fatal, and a no-op when Hyprland
# is not running (tty3 bootstrap). hexciri-restart-hyprctl already
# handles the instance signature and exits 0 with no Hyprland.
if [ "${HYPR_GUARD_PAUSED:-0}" = "1" ]; then
  step "Resuming Hyprland config auto-reload (one clean reload on the placed tree)"
  hypr_guard_resume
elif pgrep -x Hyprland >/dev/null 2>&1 && [ -x "$HEXCIRI_PATH/bin/hexciri-restart-hyprctl" ]; then
  step "Reloading Hyprland config (new Lua tree placed, clears a stale or emergency config)"
  "$HEXCIRI_PATH/bin/hexciri-restart-hyprctl" && info "Hyprland config reloaded (hyprctl reload, binds live again without a reboot)"
fi

# Binds smoke check (2026-11-24, Devi: Super+Space / Super+Alt+Space
# died after a failed update and nothing in the log said so): after the
# reload, prove the two GlobalShortcuts actually registered. A non-empty
# `hyprctl configerrors` means the reload tripped (emergency mode, no
# normal binds at all). A shell that never registered omarchy:menu.root
# / omarchy:ipc.hexciri.dock.apps means the chords dispatch nowhere.
# Warn only, never die: the shell restart in hexciri-update-restart
# runs after this installer and re-registers the shortcuts, and a tty3
# run has no Hyprland at all. (hyprctl binds is not grepped here: its
# output format varies, globalshortcuts is the authority.)
# 2026-11-24 noise fix: the two GlobalShortcut lines below used to warn
# here, but at this point the guard-resume reload has just run and the
# shell restart has NOT happened yet, so missing registrations are the
# expected state, not a failure. They now go to the detail log only.
# The real check is patch 8f in hexciri-update-restart, which polls
# after the last reload and restarts the shell again if needed.
if pgrep -x Hyprland >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then
  _cfgerr="$(hyprctl configerrors 2>/dev/null || true)"
  if [ -n "$_cfgerr" ]; then
    warn "Hyprland config errors after reload (binds may be dead, emergency mode?): $_cfgerr (check: hyprctl configerrors, then hyprctl reload)"
  elif hyprctl globalshortcuts >/dev/null 2>&1; then
    _gs="$(hyprctl globalshortcuts 2>/dev/null || true)"
    echo "$_gs" | grep -q 'omarchy:menu.root' || printf '%s\n' "binds smoke check (expected before shell restart): omarchy:menu.root not yet registered" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
    echo "$_gs" | grep -q 'omarchy:ipc.hexciri.dock.apps' || printf '%s\n' "binds smoke check (expected before shell restart): omarchy:ipc.hexciri.dock.apps not yet registered" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
  fi
  unset _cfgerr _gs
fi

# --- Final checklist ---

if [ "${IS_RERUN:-0}" = "1" ]; then
  step "Hexciri re-run done. Settings and theme preserved, no reboot checklist (fresh-install list is in the installer source)."
else
step "Hexiri 2.0 single install done. Test after reboot."
cat <<'EOF'
Reboot, then check in order:
  1. SDDM login screen appears
  2. Pick Hexiri at the SDDM session menu, log in
  3. Hyprland starts, no black screen, no immediate logout to SDDM
  4. Quickshell starts, stock bar appears: `quickshell --version` in kitty if the shell is missing
  5. Network works: `nmcli device status`
  6. Audio works: `wpctl status` (PipeWire ships with EndeavourOS)
  7. Bluetooth works if needed: `bluetoothctl devices`
  8. Theme: `hexciri-theme-set` with a stock theme, check bar and menu recolor
  9. Plugin: install a stock plugin, check it loads, check the alias resolves omarchy.bar to hexciri.bar
  10. Apps / menu: Super+Space opens the apps (dock apps), Super+Alt+Space opens the menu. Clicking the Arch logo at the bar's left end opens the menu too (bar trigger now calls hexciri-shell by absolute path), and clicking Apps inside the menu opens the app grid the same way. Both go through Hyprland global shortcuts for the keys, spawned hexciri-shell for the clicks.
  11. File manager: Super+Shift+F opens Strata, terminal opens Kitty
  12. Clock popup shows the real month and weekday names, not clock.monthYear / clock.weekShort
  13. Workspace 1 shows 1 / its mode glyph, and SDDM shows the Hexciri emblem, not Omarchy logos
  14. Default apps: Super+Shift+Return opens Brave Origin (default browser), Super+Shift+N opens Zed (nano is the fallback now, neovim removed), Super+Alt+Return opens tmux in Kitty, menu Capture > Screenrecord records (gpu-screen-recorder), menu Share > Receive opens LocalSend. Super+Shift+O (Obsidian), Super+Shift+Alt+M (ncspot) and Super+Shift+W (Ghostwriter) are unbound now, those apps were removed 2026-11-23.
  15. fastfetch: run `fastfetch` in Kitty, Hexciri logo + layout, not stock, WM shows Hyprland | Quickshell, not Niri | Noctalia
  16. Spotify + Arch substitutes: Super+Shift+M opens Spotify, Super+Shift+Q opens the calculator (gnome-calculator), PRINT takes a screenshot (grim + slurp, saved to ~/Pictures/Screenshots). Super+Ctrl+Return (Herdr) is deliberately unbound, herdr is an Omarchy AI-agent app not installed in v2, use Super+Alt+Return for tmux. v1 binds restored 2026-11-24: Super+Shift+S is web search (QS prompt via hexciri-web-search, Brave Origin) and Super+Shift+C is calculator too (same gnome-calculator as Super+Shift+Q, cheatsheet shows both chords on one Calculator row); the Google Maps / Hey Calendar region binds that owned those chords are gone.

  17. hexciri CLI: `hexciri plugin list` works in a terminal, and `hexciri update` runs the Hexciri update (eos-update --aur for repo + AUR, Hexciri self-update syncs nyx with git (tarball fallback) and re-runs the installer when it changed, mise up for mise tools). `hexciri-update` is the same script, and `hexciri update hexciri` re-runs just the Hexciri self-update. btop, apostrophe, ghostwriter, meld, ncspot, neovim, obsidian, pinta, xterm and the Haskell tree are removed and stay removed (post-update hook re-trims on every update). Foot is NOT trimmed anymore: it is an Install > Terminal option, Kitty stays default. vim and stoken stay installed, they cannot be removed (ex-vi-compat / openconnect depend on them), their entries are hidden instead, and the trim no longer tries them. YAD settings is hidden, yad itself stays (EOS tools depend on it).

  18. Menu audit 2026-11-23: Install and Remove subtrees were deleted then (install-*/remove-* were never in the fork), restored 2026-11-24 where a backing script exists (see item 21), then restored in FULL 2026-11-24 (Devi: full install/remove back): Browser, Terminal, Editor, Service, Development, Dictation, Gaming extras and their Remove counterparts are back, with their bins and data files copied. Still out: Herdr only (AI agents are options now, Devi prefers opencode), Windows + preinstalls (Omarchy-specific), Docker rows, factory reset (btrfs-only), Emacs (dead upstream). Foot is back as an Install > Terminal option only, Kitty stays default; foot is out of the trim list so an update cannot uninstall a Foot the user chose, and it removes via Remove > Package (upstream has no Remove > Terminal subtree). Update > Channel is gone (Hexciri has no channels), Update > Hexciri is back (Phase 2, 2026-11-24, runs hexciri-update in a floating terminal), System > Screensaver is gone (no screensaver binary in v2). Setup > Security > Fingerprint, Setup > Plugin options, System > Lock, System > Logout/Reboot/Shutdown, Appearance > Dock, Setup > Network > DNS, display scale and network data should all work now; the missing bins that broke them are copied. AI menu options are back 2026-11-24 (correction: Devi never said no agent options, he prefers opencode; Herdr stays removed; opencode stays the pacman default, no account prompt; mise itself is back in, Phase 2 2026-11-24, for the non-agent tools node, uv, gh). Hide/Show Bar works (bare hexciri-toggle was missing in the sim, now copied). Setup > Defaults > Dictation rows work (pick a backend, its installer is in the fork now). The dock pinned list is Strata, Spotify, Brave Origin, Zed, Kitty (Devi 2026-11-23); hexciri-browser / hexciri-terminal are not pinned, they are wrappers for Brave Origin / Kitty and would duplicate them.

  19. Regression fixes 2026-11-23: socat is installed now (hexciri-shell IPC was failing without it, which broke menu Apps, the bar Arch trigger, theme switching past the background, the background picker, and lock, all at once); Appearance > Icons has the stock icon sets; default terminal reports Kitty, not Foot; vim and stoken are NOT removed (ex-vi-compat / openconnect depend on them, the trim stopped trying them 2026-11-24 after the first full update printed the refusal on every run), their entries are hidden with NoDisplay instead; the app grid no longer shows Browser/Terminal wrappers next to Brave Origin/Kitty; `hexciri` works in a terminal (bare dispatcher was never linked into ~/.local/bin); About fits its window again (fastfetch config moved to /etc/fastfetch, About logo file created). Display and network plugins were working and were not touched.
  20. Remaining fixes 2026-11-23: SDDM login accepts fingerprint (pam_fprintd in /etc/pam.d/sddm, only when a finger is enrolled); Appearance > Icons lists Arcade/Original/Papercraft (vipsthumbnail, ffmpegthumbnailer, rsvg-convert installed, picker thumbnails work); Software Token (small) hidden for real (entry is stoken-gui-small.desktop, and stoken cannot be removed, openconnect depends on it); About is a floating fastfetch window now, fitted to the rendered content at launch (two-mode launch-about, --render measures logo + modules and resizes the window, no fixed 920x480); systemd-boot timeout 1s in every loader.conf AND the LoaderConfigTimeout EFI variable (bootctl set-timeout 1, the variable overrides loader.conf); Super+Shift+T runs btm (bottom package binary); LocalSend file picker is dark (theme name Adwaita in gtk-3.0/gtk-4.0 settings.ini, dconf color-scheme prefer-dark via dbus-run-session, FileChooser=gtk portal; Adwaita-dark is not a theme name); EOS update icon launches kitty --hold -e eos-update --yay (eos-update never called hexciri-update, the Terminal=true launch path was the break).

  21. Remaining fixes 2026-11-24: SDDM fingerprint is password-first now (pam_unix before the gate + pam_fprintd, so a correct password logs in at once and an empty-password Enter uses the reader; the old order demanded a fingerprint after the password, and rerunning the installer repairs a machine that already has the old order); System > About exports a UTF-8 locale for the whole About process (a C-locale session made wc/awk count multibyte glyphs as zero width, so the window came out narrower than the layout); EOS update keeps its icon (read from the EOS desktop file, endeavouros-icon, or system-software-update, instead of the invented eos-update name); Speed Test > Network measures with Hexciri's own curl client at /usr/lib/hexciri/speedtest (the Omarchy speedtest package comes from Omarchy's repo, which Hexciri does not use); Install and Remove menu entries are back in FULL (Package, AUR, Web App, TUI, Style, Gaming, Browser, Terminal, Editor, Service, Development, Dictation and their Remove counterparts, kept only where the backing script exists in the fork; Herdr, Windows, preinstalls, Docker rows, factory reset and Emacs stay out, see item 18; Foot and the AI rows are back (2026-11-24 correction). Every restored bin was combed for hard defaults: no folio or nautilus calls in any restored row or bin (folio only ever lived in theme-bg-install, fixed 748c59a; nautilus-dropbox appears only as a package removal), the chromium flags file's extension paths resolve to /usr/share/hexciri/default/chromium/ (copied whole), and the Tailscale Taildrop unit is installed by its install bin (ExecStart fixed to /usr/share/hexciri/bin). The restored AI bins were combed too: no folio/nautilus/herdr/docker calls in any of them; install-terminal foot copies config/foot + applications/foot.desktop. Install > Terminal is four rows now (Alacritty, Kitty, Ghostty, Foot, Kitty stays default): the 81356136 Foot verification checked $HEXCIRI_PATH/applications/foot.desktop but placement never copied applications/ there, so every update since died at verification and the shell never restarted; applications/ joins the placement copy (same as config/ in the tmux fix, curated to the three desktop files only), and placement now checks all four terminal rows plus the four desktop_id arms in install-terminal. Menu jsonc now parses (2026-11-24, Devi: whole Super+Alt+Space menu empty after update): the cf3bb1a maple row had bare double quotes inside its action string, so the shell JSON.parse failed on the whole file and a fresh shell showed nothingHere; the row now emits escaped quotes, the fork patch parses the menu before placement, and placement verification parses it again.

  22. Keyring auto-unlock 2026-11-24: Brave Origin asked for the keyring password on every launch because gnome-keyring was installed but nothing unlocked it at login. SDDM PAM now has pam_gnome_keyring.so (auth at the end of the auth section, session auto_start at the end of the session section, placed after the fingerprint block so the pam_unix success=2 skip still lands on the gate + pam_fprintd), plus password sync in /etc/pam.d/passwd so a future login-password change updates the keyring password. Brave keeps using gnome-libsecret, no --password-store flag, no plaintext storage. Two limits: a fingerprint login carries no password so the keyring stays locked that session, log in with the password to unlock it; and the Login keyring password must match the login password, if it does not, change it in Seahorse (right-click Login, Change Password), do NOT delete login.keyring, that destroys the stored secrets including Brave's Safe Storage key.

If Super+Alt+Space (menu) still does nothing after reboot, run this in a terminal and report what it prints:
  hexciri-shell shell toggle hexciri.menu '{"menu":"root"}'
If the bar Arch icon still does nothing but that command opens the menu, the bar trigger spawn is at fault, not the menu plugin. If Setup > Plugin options show nothing, run:
  hexciri-shell shell listPlugins | head -c 500
If the display panel still shows no scale, run:
  hexciri-monitor-state; echo $?
If the network panel still shows no data, run:
  hexciri-network-status --verbose | head -20

If Super+Alt+Space (menu) still does nothing after reboot, run this in a terminal and report what it prints:
  hexciri-menu toggle root
If Super+Space (apps) still does nothing, run this instead:
  hexciri-shell "hexciri.dock" "apps"
That tells whether the menu command is missing (PATH), the shell IPC is unreachable, or the menu plugin did not load.
If the menu opens from the keys but the bar Arch icon does nothing, run:
  hexciri-shell shell toggle hexciri.menu '{"menu":"root"}'
If that opens the menu, the menu plugin and shell IPC are fine and only the bar trigger spawn is at fault.

Installed locations:
  /usr/share/hexciri/  (shell, default, themes, bin)
  ~/.config/hypr/       (hyprland.lua and Hyprland templates, Lua only)
  ~/.config/hexciri/    (shell.json, plugins, themes, hooks)
  ~/.local/state/hexciri/ (theme state, toggles, migrations)
  ~/.local/bin/hexciri-* (symlinks to /usr/share/hexciri/bin/)
  /etc/profile.d/hexciri.sh, /usr/share/uwsm/env.d/10-hexciri

If Hyprland fails to start:
  - Check the Hyprland version trap above. On 0.57, a stray hyprland.conf is ignored, use Lua only.
  - Check GPU drivers match the card. Pascal 10xx needs nvidia-580xx, never nvidia-open.
  - Check logs: `journalctl --user -u hyprland` and `uwsm check` output.

If Quickshell fails to start:
  - Stock quickshell was installed first by design.
  - Fallback only if stock fails: `yay -S quickshell-git`, then reboot and retest.

Phase 2 is NOT installed. Next steps are separate work:
  Hexciri Lua edits, port Hexciri scripts from Noctalia to QS, theme engine merge,
  arch-updates EndeavourOS backend, Nyxiri overlay. (hexciri-update rework done 2026-11-24: eos-update --aur + Hexciri self-update + mise. THPM + theme hook done 2026-11-24.)
EOF
fi

# --- Reboot offer, like v1 ---
# Never auto-reboots unless --reboot was passed. Never hangs: with
# --reboot it reboots outright, with a TTY it asks (default No),
# otherwise it just notes a relogin is needed.
# This is the end of the install: v1 does everything up to this point,
# then you just reboot and it is all setup.
# Re-run from hexciri-update (IS_RERUN=1 and --no-reboot, 2026-11-24,
# Devi: "Reboot?" + "done, Hexiri 2.0 is installed. Pick Hexiri at SDDM
# ... pick a theme" leaked into an update re-run): the update already
# has its own reboot offer at the end, and this is not a fresh install.
# Skip the step and the fresh-install wording entirely; say only that
# Hexciri was re-applied and settings were preserved.
if [ "${IS_RERUN:-0}" = "1" ] && [ "${NO_REBOOT:-0}" -eq 1 ]; then
  info "Hexciri re-applied, user settings and theme preserved (the update handles the reboot offer)"
else
step "Reboot?"
if [ "${NO_REBOOT:-0}" -eq 1 ]; then
  info "no reboot (--no-reboot, the caller handles the reboot offer)"
elif [ "$AUTO_REBOOT" -eq 1 ]; then
  info "rebooting now (--reboot)"
  sudo reboot || info "reboot manually: sudo reboot"
elif [ -t 0 ]; then
  if [ "$HC_FAIL" -eq 1 ]; then
    info "health check flagged issues above, a reboot clears session-level ones"
  fi
  REBOOT_ANSWER=""
  read -r -p "Reboot now? [y/N] " REBOOT_ANSWER || REBOOT_ANSWER=""
  case "$REBOOT_ANSWER" in
    y|Y|yes|YES)
      info "rebooting..."
      sudo reboot || info "reboot manually: sudo reboot"
      ;;
    *)
      info "no reboot, at minimum relogin (new session, drivers and keybinds need a fresh session)"
      ;;
  esac
else
  info "no reboot, at minimum relogin (no TTY to ask on)"
fi
if [ "${IS_RERUN:-0}" = "1" ]; then
  info "done, Hexciri re-applied, user settings and theme preserved."
else
  info "done, Hexiri 2.0 is installed. Pick Hexiri at SDDM after reboot, then pick a theme with hexciri-theme-set if you want a different one."
fi
fi
