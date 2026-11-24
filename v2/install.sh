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
#      verify SHA from the tarball top dir, then fork and rename the shell inline.
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
#   Hexciri Lua edits (binds, windowrules, workspaces, opacity, Steam rules)
#   Port Hexciri scripts from Noctalia calls to QS calls
#   Theme engine merge, arch-updates EndeavourOS backend
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
for _a in "$@"; do
  case "$_a" in
    --yes|-y) UPDATE_YES="--yes" ;;
    --reboot) AUTO_REBOOT=1 ;;
    --no-reboot) NO_REBOOT=1 ;;
    --refork|--force) REFORK=1 ;;
    --light-sync) LIGHT_SYNC=1 ;;
    --print-fingerprints) PRINT_FP=1 ;;
    -h|--help) echo "usage: install.sh [--yes] [--reboot] [--no-reboot] [--refork] [--light-sync] [--print-fingerprints]"; exit 0 ;;
    *) printf 'install.sh: unknown arg: %s (usage: install.sh [--yes] [--reboot] [--no-reboot])\n' "$_a" >&2; exit 1 ;;
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
#     -> compat wiring marker) + pinned commit. Changes only when the
#     upstream fork itself changes.
#   patch_fingerprint(): compat wiring + all fork patches (compat marker
#     -> placement marker) + repo files copied into the fork
#     (hexciri-update-hexciri, hexciri-theme-ansi). Changes when a
#     patched bin/script changes.
#   fork_fingerprint(): combined, kept for legacy checks.
# A change to anything else (packages, SDDM, trim, theme re-apply,
# health check, output wording) changes NEITHER fingerprint: the
# self-update light-syncs instead of re-running the installer at all.
upstream_fingerprint() {
  {
    sed -n '/^# --- Fork and rename, inline/,/^# --- Wire the compat alias in, before placement ---/p' "$INSTALLER_DIR/install.sh"
    printf 'pinned=%s\n' "$PINNED_SHA"
  } | sha256sum | cut -d' ' -f1
}
patch_fingerprint() {
  {
    sed -n '/^# --- Wire the compat alias in, before placement ---/,/^# --- Place the forked tree to its install targets ---/p' "$INSTALLER_DIR/install.sh"
    for _ff in "$HEXCIRI_REPO_ROOT/v2/hexciri-update-hexciri" "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-ansi"; do
      if [ -f "$_ff" ]; then sha256sum "$_ff"; else printf 'missing %s\n' "$_ff"; fi
    done
  } | sha256sum | cut -d' ' -f1
}
fork_fingerprint() {
  printf '%s %s\n' "$(upstream_fingerprint)" "$(patch_fingerprint)" | sha256sum | cut -d' ' -f1
}
# --print-fingerprints: no side effects, used by hexciri-update-hexciri
# to decide light-sync vs full installer without running anything.
# Must run before the IS_RERUN info line below, so the output is just
# the two fingerprint lines and nothing else.
if [ "${PRINT_FP:-0}" = "1" ]; then
  printf 'upstream=%s\npatch=%s\n' "$(upstream_fingerprint)" "$(patch_fingerprint)"
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
    _n="$(grep -cE '^\([0-9]+/[0-9]+\) (installing|upgrading|reinstalling)' "$_log" 2>/dev/null || true)"
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
  printf '[hexciri] pacman failed (%s), output:\n' "$_label" >&2
  cat "$_log" >&2
  rm -f "$_log"
  return 1
}
info() { printf '[hexciri] %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

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
# change; only the installer sha marker (and the two repo bins that are
# copied straight into /usr/share/hexciri/bin) need syncing. No pacman,
# no fork, no theme re-apply, no settings touched at all.
if [ "${LIGHT_SYNC:-0}" = "1" ]; then
  _ls_sha="$(sha256sum "$INSTALLER_DIR/install.sh" 2>/dev/null | cut -d' ' -f1)"
  for _ls_f in hexciri-update-hexciri hexciri-theme-ansi; do
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
  info "Light sync done: installer marker updated, no packages, theme or settings touched"
  exit 0
fi

cleanup() {
  if [ -n "${TMP_WORK:-}" ] && [ -d "$TMP_WORK" ]; then
    rm -rf "$TMP_WORK"
  fi
}
trap cleanup EXIT

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
  xdg-user-dirs xdg-utils xorg-xwayland
  qt6-base qt6-declarative qt6-wayland qt6-svg qt6-5compat qt6-multimedia qt6-imageformats
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

# xdg-terminal-exec is NOT in stable extra and NOT in the AUR (only
# extra-testing 0.14.4-1), so it must never go in the pacman CORE_PKGS call
# above, and yay -S xdg-terminal-exec can never succeed: do not try it.
# launch-terminal's fast path (xdg-terminals.list, kitty first) works
# without it, and the binary is usually already present on EndeavourOS.
# If it is missing, enable extra-testing and install it from there; until
# then floating/presentation terminals fall back to the fast path.
if ! command -v xdg-terminal-exec >/dev/null 2>&1; then
  if [ "${IS_RERUN:-0}" = "1" ]; then
    info "xdg-terminal-exec not installed (extra-testing only, expected): terminal launches use the xdg-terminals.list fast path"
  else
    warn "xdg-terminal-exec not installed (only in Arch extra-testing, not AUR), terminal launches use the xdg-terminals.list fast path only. Install later from extra-testing if a floating terminal needs it."
  fi
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
# or AUR package exists for them), docker, AI agents (opencode,
# pi-coding-agent), fuzzel / noctalia (v2 shell is Quickshell, not
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
  # (file-manager trash/network backends), qrencode, eject (XF86Eject bind).
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
  lazygit yt-dlp gvfs zbar qrencode imv eject
  gnome-calculator
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

if [ "$HAS_AMD" -eq 1 ]; then
  step "AMD GPU detected (Framework laptop path). Installing Mesa and Vulkan, no Nvidia packages."
  run_pacman "AMD GPU drivers" -S --needed --noconfirm mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon amd-ucode linux-firmware
fi

if [ "$HAS_NVIDIA" -eq 1 ]; then
  if echo "$GPU_INFO" | grep -qiE 'RTX|GTX 16|GTX 20|GTX 30|GTX 40'; then
    step "Nvidia Turing or newer detected (RTX 4080 Super path). Installing nvidia-open."
    install_kernel_headers
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  elif echo "$GPU_INFO" | grep -qiE 'GTX 10'; then
    step "Nvidia Pascal detected (GTX 1080 Ti, 10xx path). Installing nvidia-580xx from AUR."
    warn "Pascal is legacy. nvidia-580xx is the legacy branch, end of support is coming. Do NOT install nvidia-open on this card."
    install_kernel_headers
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils
  else
    warn "Nvidia GPU found but model not matched as Turing+ or Pascal 10xx. Check lspci output above."
    warn "Defaulting to nvidia-open. If this is a Pascal 10xx card, remove nvidia-open and install nvidia-580xx-dkms and nvidia-580xx-utils from AUR instead."
    install_kernel_headers
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
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
  if [ ! -f "$FORK_OUT/default/hypr/bootstrap.lua" ]; then
    warn "Fork cache invalid: cached upstream tree is missing default/hypr/bootstrap.lua, dropping the cache and full re-forking"
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
  if [ ! -f "$FORK_OUT/default/hypr/bootstrap.lua" ] || [ ! -f "$FORK_OUT/default/hypr/hexciri.lua" ]; then
    warn "Fork cache invalid: cached patched tree is missing default/hypr/bootstrap.lua or hexciri.lua, re-applying patches to the cached upstream tree"
    rm -rf "$FORK_CACHE_DIR/fork-out" "$FORK_CACHE_DIR/patch-fingerprint" "$FORK_CACHE_DIR/fork-fingerprint"
    SKIP_PATCHES=0
    SKIP_FORK=0
    rm -rf "$FORK_OUT"
    cp -a "$FORK_CACHE_DIR/upstream-out" "$FORK_OUT"
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
      dock | dns | state | show-* | setup-* | device-* | apply-lock | sudo-passwordless | security-functions | display-* | monitor-* | network-* | font-* | disk-speedtest | file-select | input-method | git-url-check | kernel | language | locale-session | locale-generate | refresh-shell | refresh-tmux | refresh-hyprsunset | refresh-applications | refresh-config | install-font | install-app | install-and-launch | install-editor-zed | install-gaming-steam | install-gaming-heroic | install-gaming-lutris | install-gaming-retroarch | install-gaming-battlenet | install-gaming-geforce-now | install-gaming-gpu-lib32 | remove-browser | remove-security-fingerprint | remove-gaming-steam | remove-gaming-retroarch | remove-gaming-minecraft | remove-gaming-geforce-now)
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
      # Deliberately still NOT included: install-ai-*, install-service-*,
      # install-terminal-*, install-dictation-*, install-browser (its tree
      # pulls install-chromium-*, install-video-decode, install-camera and
      # config/chromium-flags.conf, none of which the fork copies; Brave
      # Origin is already installed, so no row needs it), install-windows-vm,
      # install-preinstalls, install-dev-env, channel-*, mirror-*, keyring-*,
      # upgrade-* (Omarchy repo machinery, out of the shell-only Phase 1
      # scope), and windows-vm (Docker/KVM VM manager, needs Docker).
      # The install-*/remove-* scripts that ARE listed are the bounded set
      # the menu restore keeps rows for (pkg-*, font, app, and-launch,
      # editor-zed, gaming, remove-browser/fingerprint/gaming); the menu
      # patch step below drops every other install/remove row whose backing
      # script is not in the fork, so no dead row can be clicked.
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

copy_subsets() {
  step "Copying only the listed Phase 1 subsets (everything else is skipped by design)"
  info "Skipped: apps/GUI preinstalls, Limine/UKI, snapper/btrfs, Plymouth, LUKS scripts, Docker, AI agents, omarchy-upgrade-to-quattro, channel/keyring/mirror scripts, pacman guard hook, upstream migrations (migration runner mechanism only, no upstream migrations)"
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
  cp -a "$FORK_OUT" "$FORK_CACHE_DIR/upstream-out"
  printf '%s\n' "$UP_FP" > "$FORK_CACHE_DIR/upstream-fingerprint"
  fork_detail "Upstream fork cache saved: $FORK_CACHE_DIR/upstream-out"
fi
# Emergency-mode guard, 2026-11-24: fail fast if the fork lost
# bootstrap.lua, before patches run and before placement wipes the
# last good /usr/share/hexciri. Hyprland dofiles this file first;
# without it the next boot trips emergency mode with no binds.
if [ "${SKIP_UPSTREAM:-0}" = "0" ] && [ ! -f "$FORK_OUT/default/hypr/bootstrap.lua" ]; then
  die "fork lost default/hypr/bootstrap.lua (Hyprland dofiles it first; missing it trips emergency mode). Refusing to continue with a broken fork."
fi

# Patch guard: compat wiring + all fork patches run on the upstream
# tree (fresh, or restored from the upstream cache). They never run on
# an already-patched tree, so whole-file rewrites stay idempotent.
if [ "${SKIP_PATCHES:-0}" = "0" ]; then

# --- Wire the compat alias in, before placement ---
# This was the missing step in Phase 1. Wiring happens on the fork output
# (user-owned temp dir), so placement then copies wired files to their targets.

step "Wiring hexciri-compat into launch-shell, env-bootstrap, and Hyprland Lua"

LAUNCH_SHELL="$FORK_OUT/bin/hexciri-launch-shell"
ENV_BOOTSTRAP="$FORK_OUT/default/bash/env-bootstrap"
HEXCIRI_LUA="$FORK_OUT/default/hypr/hexciri.lua"

if [ -f "$LAUNCH_SHELL" ]; then
  if head -1 "$LAUNCH_SHELL" | grep -q 'bash'; then
    python3 - "$LAUNCH_SHELL" <<'PY'
import sys
path = sys.argv[1]
line = 'source "$(dirname "$0")/hexciri-compat.sh" 2>/dev/null || source "/usr/share/hexciri/bin/hexciri-compat.sh" 2>/dev/null || true'
with open(path) as f:
    lines = f.read().splitlines()
if any("hexciri-compat.sh" in l for l in lines):
    print("launch-shell: compat source already present, skipping")
else:
    lines.insert(1, line)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("launch-shell: inserted compat source after shebang")
PY
    bash -n "$LAUNCH_SHELL" || die "bash -n failed on wired $LAUNCH_SHELL"
    info "Wired: hexciri-compat.sh sourced from hexciri-launch-shell"
  else
    warn "hexciri-launch-shell is not a bash script, skipping compat source insertion. Check its shebang manually."
  fi
else
  warn "hexciri-launch-shell not found in fork output, skipping compat wiring for it."
fi

if [ -f "$ENV_BOOTSTRAP" ]; then
  if ! grep -q 'hexciri-compat.sh' "$ENV_BOOTSTRAP"; then
    {
      echo ""
      echo "# Hexiri compat alias: OMARCHY_PATH is a runtime alias for HEXCIRI_PATH."
      echo 'source "/usr/share/hexciri/bin/hexciri-compat.sh" 2>/dev/null || true'
    } >> "$ENV_BOOTSTRAP"
    info "Wired: hexciri-compat.sh sourced from default/bash/env-bootstrap"
  else
    info "env-bootstrap: compat source already present, skipping"
  fi
elif [ -e "$ENV_BOOTSTRAP" ]; then
  warn "default/bash/env-bootstrap is not a regular file, skipping compat wiring for it."
else
  warn "default/bash/env-bootstrap not found in fork output, skipping compat wiring for it."
fi

if [ -f "$HEXCIRI_LUA" ]; then
  python3 - "$HEXCIRI_LUA" <<'PY'
import sys
path = sys.argv[1]
line = 'pcall(require, "default.hypr.hexciri-compat")'
with open(path) as f:
    content = f.read()
if "hexciri-compat" in content:
    print("hexciri.lua: compat require already present, skipping")
else:
    with open(path, "w") as f:
        f.write(line + "\n" + content)
    print("hexciri.lua: inserted compat require as first line")
PY
  # Syntax-only check: parse the file, never execute it. luac -p is the
  # correct tool for that. The old check used
  #   lua5.1 -e 'assert(loadfile(arg[1]))' file
  # which is a false failure: with -e, lua sets global arg to nil, so
  # arg[1] errors with "attempt to index global 'arg' (a nil value)"
  # on every file, even a syntactically valid one. It also made the
  # luac branch unreachable, since lua5.1 is installed whenever luac is.
  if command -v luac5.1 >/dev/null 2>&1; then
    luac5.1 -p "$HEXCIRI_LUA" || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (luac5.1 syntax OK)"
  elif command -v luac >/dev/null 2>&1; then
    luac -p "$HEXCIRI_LUA" || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (luac syntax OK)"
  elif command -v lua5.1 >/dev/null 2>&1; then
    # No luac: loadfile() parses without executing. Pass the path via an
    # env var, not arg[1], because arg is nil under lua -e.
    HEXCIRI_LUA_CHECK="$HEXCIRI_LUA" lua5.1 -e 'assert(loadfile(os.getenv("HEXCIRI_LUA_CHECK")))' || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (lua5.1 syntax OK)"
  else
    warn "No luac5.1/luac/lua5.1 binary found, skipping Lua syntax check on wired hexciri.lua."
  fi
else
  die "default/hypr/hexciri.lua not found in fork output, cannot wire compat require."
fi

# Defence in depth for the emergency-mode bug: bootstrap.lua is dofile'd by
# config/hypr/hyprland.lua BEFORE it requires default.hypr.omarchy, so a
# package.preload alias there catches any require of the old module name
# that the rewrite above missed, e.g. in a user config or a third-party
# module, and resolves it to default.hypr.hexciri. No file named omarchy
# is created. This runs from tty with no GUI, like the rest of the installer.
BOOTSTRAP_LUA="$FORK_OUT/default/hypr/bootstrap.lua"
if [ -f "$BOOTSTRAP_LUA" ]; then
  python3 - "$BOOTSTRAP_LUA" <<'PY'
import sys
path = sys.argv[1]
alias = (
    '\n-- Hexiri compat: legacy module name default.hypr.omarchy resolves to\n'
    '-- default.hypr.hexciri. This is the defence in depth for the Hyprland\n'
    '-- emergency mode on the first live boot, when hyprland.lua still\n'
    '-- required the old name after the file had been renamed.\n'
    'package.preload["default.hypr.omarchy"] = function() return require("default.hypr.hexciri") end\n'
    'package.preload["omarchy.current.theme.hyprland"] = function() return require("hexciri.current.theme.hyprland") end\n'
)
with open(path) as f:
    content = f.read()
if 'package.preload["default.hypr.omarchy"]' in content:
    print("bootstrap.lua: legacy module preload alias already present, skipping")
else:
    with open(path, "w") as f:
        f.write(content.rstrip("\n") + "\n" + alias)
    print("bootstrap.lua: added legacy module preload alias for default.hypr.omarchy")
PY
  if command -v luac5.1 >/dev/null 2>&1; then
    luac5.1 -p "$BOOTSTRAP_LUA" && info "bootstrap.lua preload alias added (luac5.1 syntax OK)" || warn "luac5.1 syntax check failed on wired bootstrap.lua, continuing anyway, Hyprland will report the real error at boot if this is broken."
  elif command -v luac >/dev/null 2>&1; then
    luac -p "$BOOTSTRAP_LUA" && info "bootstrap.lua preload alias added (luac syntax OK)" || warn "luac syntax check failed on wired bootstrap.lua, continuing anyway."
  else
    info "bootstrap.lua preload alias added, no luac binary to syntax-check it with."
  fi
else
  warn "default/hypr/bootstrap.lua not found in fork output, skipping legacy module preload alias. The rewrite fix above is still the primary fix."
fi

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
python3 - "$FORK_OUT" <<'PY'
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

# 6. Screenshot: hexciri-capture-screenshot execs omasnap (Omarchy-repo-only).
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
# --- Patch menu audit fixes: dead rows out, shell IPC paths absolute ---
# Menu audit 2026-11-23 (Devi: "basically super alt space menu needs a full
# audit"): every menu entry was checked against the forked bin/ allowlist.
# What this block does, all on the fork output before placement:
#  1. Deletes dead menu rows, and restores Install + Remove where a backing
#     script exists in the fork (2026-11-24, Devi: install/remove exist in
#     Hexciri v1 and should come back). A row stays when every hexciri-*
#     command its action names exists in bin/, so Package / AUR / Web App /
#     TUI / Style / Gaming and their Remove counterparts come back, while
#     rows whose script was never copied (AI, services, terminals, windows,
#     preinstalls, dictation, install-browser) still drop. A when/disabled
#     guard naming a missing command only hides or mis-guards the row, it
#     never runs, so only the action decides. Header rows (no action) stay
#     only while at least one child row under them stays. Still deleted:
#     Update > Channel (Hexciri has no channels), Update > Games /
#     Password (games-*/drive-* out of scope), Update > Config > Plymouth
#     (plymouth out), System > Screensaver (no screensaver binary ships
#     in v2). Update > Hexciri is BACK: hexciri-update is Phase 2, done
#     2026-11-24 (eos-update --aur + Hexciri self-update + mise).
#     Appearance > Unlock (plymouth), Learn > Herdr keybindings (Herdr out),
#     Setup > Default Editor > Neovim (neovim removed), Setup > Security >
#     Sudoless Docker (Docker out). The upstream jsonc is untouched.
#  2. Menu "Apps" row + bar trigger call hexciri-shell by absolute path:
#     both go through Util.execDetached, and a spawned process only finds
#     hexciri-shell if the shell's env carries /usr/share/hexciri/bin on
#     PATH. Super+Alt+Space works (Hyprland global shortcut, in-process)
#     while the bar Arch icon and the menu Apps click do nothing: same
#     spawn path, same missing lookup. Absolute path + the hexciri-shell
#     HEXCIRI_PATH default below make both independent of that env.
#  3. hexciri-shell defaults HEXCIRI_PATH to /usr/share/hexciri when unset
#     instead of failing: it is the fixed install path, and compat.sh
#     already applies the same default for the shell process itself.
#  4. shell.qml + Menu.qml execArgv call sites for hexciri-shell /
#     hexciri-menu-keybindings go absolute for the same reason.
#  5. launch-editor falls back to nano (was nvim); default-editor loses
#     its nvim choice (neovim removed, and its branch called the missing
#     hexciri-pkg-add).
# Idempotent: every replacement checks it is not already applied.
step "Patching menu audit fixes: dead rows out, shell IPC paths absolute"
python3 - "$FORK_OUT" <<'PY'
import os
import re
import sys

root = sys.argv[1]
changed = []

# 1. Delete dead menu rows, one entry per line in the jsonc.
menu = root + "/default/hexciri/hexciri-menu.jsonc"
with open(menu) as f:
    lines = f.read().splitlines()
bin_dir = root + "/bin"
have_bins = set(os.listdir(bin_dir)) if os.path.isdir(bin_dir) else set()
def _row_key(line):
    m = re.match(r'^\s*"([^"]+)"\s*:', line)
    return m.group(1) if m else None
def _action_tokens(line):
    m = re.search(r'"action"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
    return re.findall(r'hexciri-[a-z0-9-]+', m.group(1)) if m else []
dead = re.compile(
    r'^\s*"(update\.channel(\..*)?|'
    r'update\.omarchy|update\.games|update\.password|'
    r'update\.config\.plymouth|system\.screensaver|'
    r'learn\.herdr-keybindings|setup\.default\.editor\.neovim|'
    r'setup\.security\.sudoless-docker|appearance\.unlock)"\s*:'
)
kept = []
removed = []
kept_keys = set()
# Out of scope even when the action's helper exists: generic helpers
# (install-and-launch, install-app, launch-floating-terminal) make AI,
# service, editor and dev-env rows look valid, but those subtrees are
# Phase 2 / not wanted (vim was removed on purpose, AI agents are out,
# factory reset is destructive and btrfs-only). Zed is the one editor kept.
_drop_prefix = (
    "install.ai.", "install.service.", "install.development.",
    "install.terminal.", "install.browser.", "install.dictation.",
    "remove.ai.", "remove.service.", "remove.development.",
    "remove.dictation.",
)
_drop_exact = {
    "install.windows", "install.preinstalls", "install.dictation",
    "remove.windows", "remove.preinstalls", "remove.factory-reset",
    "remove.security.fido2", "remove.security.sshd",
    "remove.security.sudoless-docker",
}
for line in lines:
    key = _row_key(line)
    if key is None or not (key == "install" or key == "remove" or key.startswith("install.") or key.startswith("remove.")):
        if key is not None and dead.match(line):
            removed.append(line.strip()[:60])
            continue
        kept.append(line)
        continue
    if key in _drop_exact or key.startswith(_drop_prefix) or (key.startswith("install.editor.") and key != "install.editor.zed"):
        removed.append(line.strip()[:60])
        continue
    toks = _action_tokens(line)
    if toks and any(t not in have_bins for t in toks):
        removed.append(line.strip()[:60])
        continue
    kept.append(line)
    kept_keys.add(key)
# Second pass, repeated until stable: drop header rows whose subtree has no
# kept row left. One pass is not enough, an empty submenu (development /
# javascript / php / elixir) keeps its parent alive for a round even
# though the submenu itself drops in the same round.
while True:
    final = []
    dropped_this_round = False
    for line in kept:
        key = _row_key(line)
        if key is not None and _action_tokens(line) == [] and (key == "install" or key == "remove" or key.startswith("install.") or key.startswith("remove.")):
            prefix = key + "."
            if not any(k.startswith(prefix) for k in kept_keys):
                removed.append(line.strip()[:60])
                dropped_this_round = True
                continue
        final.append(line)
    kept = final
    kept_keys = {_row_key(l) for l in kept if _row_key(l) is not None}
    if not dropped_this_round:
        break
if removed:
    with open(menu, "w") as f:
        f.write("\n".join(kept) + "\n")
    changed.append("menu: removed %d dead rows (kept install/remove rows whose backing bin exists, dropped the rest + update channels, screensaver, unlock, herdr keys, neovim editor, sudoless-docker)" % len(removed))
    for r in removed[:8]:
        print("  menu removed: " + r)
    if len(removed) > 8:
        print("  menu removed: ... and %d more" % (len(removed) - 8))
else:
    print("menu: no dead rows found (already patched?)")

with open(menu) as f:
    m = f.read()
m_orig = m
# 2. Menu Apps row: absolute hexciri-shell path.
if '"action":"hexciri-shell hexciri.dock apps"' in m:
    m = m.replace('"action":"hexciri-shell hexciri.dock apps"', '"action":"/usr/share/hexciri/bin/hexciri-shell hexciri.dock apps"')
    changed.append("menu apps row: hexciri-shell by absolute path")
elif "/usr/share/hexciri/bin/hexciri-shell hexciri.dock apps" in m:
    print("menu apps row already absolute, skipping")
else:
    print("WARN: menu apps action not found, apps row NOT patched")

if m != m_orig:
    with open(menu, "w") as f:
        f.write(m)

# 3. hexciri-shell: default HEXCIRI_PATH instead of failing when unset.
sh = root + "/bin/hexciri-shell"
with open(sh) as f:
    shs = f.read()
sh_orig = shs
_old_fail = '[[ -n ${HEXCIRI_PATH:-} ]] || fail "HEXCIRI_PATH is not set"'
_new_def = '[[ -n ${HEXCIRI_PATH:-} ]] || HEXCIRI_PATH="/usr/share/hexciri"'
if _old_fail in shs:
    shs = shs.replace(_old_fail, _new_def, 1)
    changed.append("hexciri-shell: HEXCIRI_PATH defaults to /usr/share/hexciri when unset")
elif _new_def in shs:
    print("hexciri-shell default already present, skipping")
else:
    print("WARN: hexciri-shell HEXCIRI_PATH check not found, default NOT applied")
if shs != sh_orig:
    with open(sh, "w") as f:
        f.write(shs)

# 4. Bar trigger + shell/menu execArgv call sites: absolute hexciri-shell.
bw = root + "/shell/plugins/menu/BarWidget.qml"
with open(bw) as f:
    b = f.read()
b_orig = b
if 'root.bar.run("hexciri-shell shell toggle hexciri.menu' in b:
    b = b.replace('root.bar.run("hexciri-shell shell toggle hexciri.menu', 'root.bar.run("/usr/share/hexciri/bin/hexciri-shell shell toggle hexciri.menu', 1)
    changed.append("bar trigger: hexciri-shell by absolute path")
elif "/usr/share/hexciri/bin/hexciri-shell shell toggle hexciri.menu" in b:
    print("bar trigger already absolute, skipping")
else:
    print("WARN: bar trigger hexciri-shell call not found, trigger NOT patched")
if b != b_orig:
    with open(bw, "w") as f:
        f.write(b)

sq = root + "/shell/shell.qml"
with open(sq) as f:
    q = f.read()
q_orig = q
if 'Util.execArgv(["hexciri-shell", target, method])' in q:
    q = q.replace('Util.execArgv(["hexciri-shell", target, method])', 'Util.execArgv(["/usr/share/hexciri/bin/hexciri-shell", target, method])', 1)
    changed.append("shell.qml: hexciri-shell execArgv by absolute path")
elif 'Util.execArgv(["/usr/share/hexciri/bin/hexciri-shell", target, method])' in q:
    print("shell.qml execArgv already absolute, skipping")
else:
    print("WARN: shell.qml hexciri-shell execArgv not found, NOT patched")
if q != q_orig:
    with open(sq, "w") as f:
        f.write(q)

mq = root + "/shell/plugins/menu/Menu.qml"
with open(mq) as f:
    mq_s = f.read()
mq_orig = mq_s
if 'Util.execArgv(["hexciri-menu-keybindings", "--dispatch", kbEntry.dispatcher, kbEntry.arg])' in mq_s:
    mq_s = mq_s.replace('Util.execArgv(["hexciri-menu-keybindings", "--dispatch", kbEntry.dispatcher, kbEntry.arg])', 'Util.execArgv(["/usr/share/hexciri/bin/hexciri-menu-keybindings", "--dispatch", kbEntry.dispatcher, kbEntry.arg])', 1)
    changed.append("Menu.qml: hexciri-menu-keybindings execArgv by absolute path")
elif "/usr/share/hexciri/bin/hexciri-menu-keybindings" in mq_s:
    print("Menu.qml execArgv already absolute, skipping")
else:
    print("WARN: Menu.qml hexciri-menu-keybindings execArgv not found, NOT patched")
if mq_s != mq_orig:
    with open(mq, "w") as f:
        f.write(mq_s)

# 5. Editor fallbacks: launch-editor nvim -> nano, default-editor nvim out.
le = root + "/bin/hexciri-launch-editor"
with open(le) as f:
    le_s = f.read()
le_orig = le_s
if '|| editor="nvim"' in le_s:
    le_s = le_s.replace('|| editor="nvim"', '|| editor="nano"', 1)
    changed.append("launch-editor fallback nvim -> nano")
elif '|| editor="nano"' in le_s:
    print("launch-editor fallback already nano, skipping")
else:
    print("WARN: launch-editor nvim fallback not found, NOT patched")
if le_s != le_orig:
    with open(le, "w") as f:
        f.write(le_s)

de = root + "/bin/hexciri-default-editor"
with open(de) as f:
    de_s = f.read()
de_orig = de_s
de_s = re.sub(r'^nvim\) selection="nvim"; editor="nvim"; name="Neovim"; glyph=.*$\n', "", de_s, flags=re.M)
de_s = re.sub(r'^\s*nvim\) hexciri-pkg-add neovim ;;$\n', "", de_s, flags=re.M)
de_s = de_s.replace("<plain|code|cursor|zed|sublime_text|helix|vim|emacs|nvim>", "<plain|code|cursor|zed|sublime_text|helix|vim|emacs>")
if de_s != de_orig:
    with open(de, "w") as f:
        f.write(de_s)
    changed.append("default-editor: nvim choice removed (neovim not installed)")
else:
    print("default-editor: nvim choice already gone, skipping")

# 6. Herdr autostart: default/hypr/autostart.lua unconditionally starts a
#    Herdr server on every boot (systemd-run ... herdr server). Herdr is
#    deliberately out of v2 (bind removed, AI agents out of scope), so the
#    unit fails quietly on every boot. Remove the block, comments and all.
auto = root + "/default/hypr/autostart.lua"
with open(auto) as f:
    a_lines = f.read().splitlines()
a_start = None
for i, l in enumerate(a_lines):
    if "-- Start the herdr server inside the graphical session" in l:
        a_start = i
        break
if a_start is not None:
    a_end = None
    for j in range(a_start, len(a_lines)):
        if a_lines[j] == "  )":
            a_end = j + 1
            break
    if a_end is not None:
        del a_lines[a_start:a_end]
        if a_start < len(a_lines) and a_lines[a_start] == "":
            del a_lines[a_start]
        with open(auto, "w") as f:
            f.write("\n".join(a_lines) + "\n")
        changed.append("autostart: Herdr server block removed (Herdr out of v2 scope)")
    else:
        print("menu audit: herdr autostart block end not found, skipping")
else:
    print("menu audit: herdr autostart block already gone, skipping")

for c in changed:
    print("menu audit: " + c)
if not changed:
    print("menu audit: no changes needed")
PY

# Syntax-check the patched Lua at install time, like the hexciri.lua check
# above: a bad bind would otherwise only surface as a Hyprland error at boot.
if command -v luac5.1 >/dev/null 2>&1; then
  luac5.1 -p "$FORK_OUT/default/hypr/bindings/applications.lua" && info "applications.lua patch OK (luac5.1 syntax OK)" || warn "luac5.1 syntax check failed on patched applications.lua, Hyprland will report the real error at boot if this is broken."
elif command -v luac >/dev/null 2>&1; then
  luac -p "$FORK_OUT/default/hypr/bindings/applications.lua" && info "applications.lua patch OK (luac syntax OK)" || warn "luac syntax check failed on patched applications.lua, Hyprland will report the real error at boot if this is broken."
else
  warn "No luac5.1/luac binary found, skipping Lua syntax check on patched applications.lua (the patch mirrors the existing Obsidian bind line for line)."
fi
if command -v luac5.1 >/dev/null 2>&1; then
  luac5.1 -p "$FORK_OUT/default/hypr/bindings/utilities.lua" && info "utilities.lua patch OK (luac5.1 syntax OK)" || warn "luac5.1 syntax check failed on patched utilities.lua, Hyprland will report the real error at boot if this is broken."
elif command -v luac >/dev/null 2>&1; then
  luac -p "$FORK_OUT/default/hypr/bindings/utilities.lua" && info "utilities.lua patch OK (luac syntax OK)" || warn "luac syntax check failed on patched utilities.lua, Hyprland will report the real error at boot if this is broken."
fi
bash -n "$FORK_OUT/bin/hexciri-capture-screenshot" || die "bash -n failed on rewritten $FORK_OUT/bin/hexciri-capture-screenshot"
info "Bind patch done: Super+Space apps / Super+Alt+Space menu swap, Super+Shift+M Spotify, gnome-calculator, btm (bottom package), Herdr removed, cliamp/omawrite/Obsidian binds removed (ncspot/ghostwriter/obsidian not wanted), screenshot via grim+slurp, touchpad bottom-right = right click"

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
python3 - "$FORK_OUT" <<'PY'
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

# --- Fork-time patches: SDDM fingerprint in setup script, About replacement ---
# 1. hexciri-setup-security-fingerprint: upstream setup_pam_config only
# configures sudo, polkit and the lock screen, so fingerprint worked for
# sudo but SDDM always asked for a password. Prepend pam_unix first, then
# the gate + pam_fprintd, to /etc/pam.d/sddm (ArchWiki either-or order:
# a correct password logs in at once, an empty/wrong one falls through to
# the reader), repairing any earlier Hexciri SDDM lines first, so a later
# Setup > Security > Fingerprint run (e.g. enrolling another finger) keeps
# SDDM working. The installer step above does the same thing at install
# time; this keeps the setup script consistent afterwards.
# 2. hexciri-launch-about: replaced wholesale (2026-11-24) with a floating
# fastfetch window, fixed 2026-11-24 to a two-mode script. No about.txt,
# no fit measurement, no awk locale sizing. The menu row system.about
# still calls it; the Hyprland rule in default/hypr/apps/system.lua floats
# org.hexciri.about (1280x800 start, fitted at launch). Never pass a bash -c '...' string through
# launch-or-focus-tui: it builds LAUNCH_COMMAND with unquoted $@ and
# launch-or-focus re-parses it with eval, so the -c string is split and
# bash -c receives only `export`, prints the env and exits, which is why
# About opened and closed instantly. Single-word args (--render) survive.
python3 - "$FORK_OUT" <<'PY'
import os
import re
import sys

root = sys.argv[1]
changed = []

fp = root + "/bin/hexciri-setup-security-fingerprint"
with open(fp) as f:
    s = f.read()
s_orig = s
_marker = "# Hexciri: SDDM login unlock"
_tail = "session   include system-auth\nEOF\n  fi\n}"
_sddm = "session   include system-auth\nEOF\n  fi\n\n  # Hexciri: SDDM login unlock (2026-11-23, fixed 2026-11-24). Upstream only\n  # configures sudo, polkit and the lock screen, so fingerprint worked for\n  # sudo but SDDM always asked for a password. SDDM authenticates the user\n  # through /etc/pam.d/sddm. The order matters, ArchWiki SDDM fingerprint:\n  # pam_unix FIRST, so a correct password logs in at once and fingerprint\n  # is never asked for after it; only an empty/wrong password falls through\n  # to the clamshell gate and then pam_fprintd (press Enter on an empty\n  # password field to touch the reader). The old Hexciri order (gate +\n  # pam_fprintd first) demanded a fingerprint AFTER a correct password.\n  # Repair first: strip any earlier Hexciri SDDM lines, so a rerun fixes a\n  # machine that already has the broken order instead of skipping it.\n  if [[ -f /etc/pam.d/sddm ]]; then\n    echo \"Configuring SDDM login for fingerprint authentication...\"\n    _sddm_tmp=\"$(mktemp)\"\n    sudo sed -e '/pam_fprintd\\.so/d' -e '/hexciri-hw-laptop-closed/d' -e '/try_first_pass likeauth nullok/d' /etc/pam.d/sddm > \"$_sddm_tmp\" 2>/dev/null || cp /etc/pam.d/sddm \"$_sddm_tmp\"\n    _sddm_out=\"$(mktemp)\"\n    {\n      printf 'auth      [success=2 new_authtok_reqd=2 default=ignore] pam_unix.so try_first_pass likeauth nullok\\n'\n      printf '%s\\n' \"$fprintd_gate\"\n      printf 'auth      sufficient pam_fprintd.so\\n'\n      cat \"$_sddm_tmp\"\n    } > \"$_sddm_out\"\n    sudo install -Dm644 \"$_sddm_out\" /etc/pam.d/sddm && echo \"SDDM login fingerprint configured.\"\n    rm -f \"$_sddm_tmp\" \"$_sddm_out\"\n    if [[ -f /usr/share/sddm/themes/hexciri/theme.conf ]]; then\n      sudo sed -i '/^Fingerprint=/d' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null || true\n      printf 'Fingerprint=true\\n' | sudo tee -a /usr/share/sddm/themes/hexciri/theme.conf >/dev/null 2>&1 || true\n    fi\n  fi\n}"
if _marker in s:
    print("setup-security-fingerprint SDDM block already present, skipping")
elif s.count(_tail) == 1:
    s = s.replace(_tail, _sddm, 1)
    changed.append("setup-security-fingerprint: SDDM PAM block in setup_pam_config")
else:
    print("WARN: setup_pam_config polkit tail not found (%d), SDDM block NOT applied" % s.count(_tail))
if s != s_orig:
    with open(fp, "w") as f:
        f.write(s)

# 2. hexciri-launch-about: replace wholesale with a floating fastfetch
#    (2026-11-24). The old script measured the logo with wc/awk, remembered
#    the size in about.fit, and kept breaking (multibyte width, stale fit,
#    blank logo). About is now just a floating Kitty running fastfetch with
#    the Hexciri config at /etc/fastfetch/config.jsonc; the Hyprland rule
#    in default/hypr/apps/system.lua floats org.hexciri.about (1280x800 start, fitted at launch).
#    Also fix that rule's stale comment, which still describes the fit.
# 2. hexciri-launch-about: two-mode script (2026-11-24, fixed same day).
#    The old script measured the logo with wc/awk, remembered the size in
#    about.fit, and kept breaking (multibyte width, stale fit, blank logo).
#    The 2b92c50 replacement passed `bash -c 'export ...; fastfetch; read'`
#    through hexciri-launch-or-focus-tui, whose unquoted $@ + eval in
#    hexciri-launch-or-focus split the -c string, so bash -c got only
#    `export` and the window opened and closed at once. Now the outer call
#    passes only single-word args (hexciri-launch-about --render), which
#    survive that chain intact, and --render runs inside the terminal:
#    fastfetch with the Hexciri config at /etc/fastfetch/config.jsonc,
#    then read blocks until any key. The Hyprland rule in
#    default/hypr/apps/system.lua floats org.hexciri.about (1280x800 start, fitted at launch).
#    Also fix that rule's stale comment, which still describes the fit.
la = root + "/bin/hexciri-launch-about"
_about_lines = [
    "#!/bin/bash",
    "# hexciri-launch-about (2026-11-24): System > About is a floating fastfetch,",
    "# fitted to the rendered content at launch. No about.txt, no fit file.",
    "# Menu row system.about calls this script; it opens a floating terminal",
    "# running fastfetch with the Hexciri config at /etc/fastfetch/config.jsonc.",
    "# Window size starts from the Hyprland rule for org.hexciri.about (1280x800);",
    "# --render measures the real content and resizes the window to hug it",
    "# before painting, so it fits on any font size / DPI instead of wrapping",
    "# at a fixed 920x480 (module lines wrapped to the left margin).",
    "# --render runs INSIDE the terminal. Never pass a bash -c '...' string",
    "# through launch-or-focus-tui: unquoted $@ + eval splits it, bash -c",
    "# gets only `export` and exits, so About opens and closes at once.",
    "_about_cfg=\"/etc/fastfetch/config.jsonc\"",
    "_about_config() { if [ -f \"$_about_cfg\" ]; then fastfetch --config \"$_about_cfg\" \"$@\"; else fastfetch \"$@\"; fi; }",
    "_about_strip() { sed 's/\\x1b\\[[0-9;?]*[a-zA-Z]//g'; }",
    "_about_settle() {",
    "  local current previous=\"\" held=0",
    "  for _ in {1..20}; do",
    "    current=$(stty size 2>/dev/null || echo \"\")",
    "    if [[ $current == \"$previous\" && -n $current ]]; then (( ++held >= 3 )) && return 0; else held=0; previous=$current; fi",
    "    sleep 0.05",
    "  done",
    "  return 0",
    "}",
    "_about_fit() {",
    "  local modules module_w module_r logo_w logo_h logo_src target_c target_r",
    "  modules=$(_about_config --logo none 2>/dev/null | _about_strip; printf X); modules=${modules%X}",
    "  module_w=$(printf '%s' \"$modules\" | LC_ALL=C.UTF-8 wc -L 2>/dev/null || echo 60)",
    "  module_r=$(printf '%s' \"$modules\" | wc -l 2>/dev/null || echo 36)",
    "  logo_w=65; logo_h=35",
    "  logo_src=$(grep -m1 -o '\"source\": *\"[^\"]*\"' \"$_about_cfg\" 2>/dev/null | sed 's/\"source\": *\"//; s/\"$//')",
    "  if [[ $logo_src == *.txt ]]; then",
    "    logo_src=${logo_src/#~/$HOME}",
    "    if [ -f \"$logo_src\" ]; then logo_w=$(LC_ALL=C.UTF-8 wc -L <\"$logo_src\" 2>/dev/null || echo 54); logo_h=$(wc -l <\"$logo_src\" 2>/dev/null || echo 26); fi",
    "  else",
    "    logo_w=$(grep -m1 -o '\"width\": *[0-9]*' \"$_about_cfg\" 2>/dev/null | grep -o '[0-9]*' || echo 65)",
    "    logo_h=$(grep -m1 -o '\"height\": *[0-9]*' \"$_about_cfg\" 2>/dev/null | grep -o '[0-9]*' || echo 35)",
    "  fi",
    "  target_c=$(( logo_w + 6 + module_w + 4 ))",
    "  target_r=$(( module_r > logo_h + 3 ? module_r : logo_h + 3 ))",
    "  target_r=$(( target_r + 2 ))",
    "  local rows cols address width height nudges=0 shift_w shift_h target_w target_h mon_w mon_h",
    "  _about_settle",
    "  while :; do",
    "    read -r rows cols <<<\"$(stty size 2>/dev/null || echo \"0 0\")\"",
    "    read -r address width height <<<\"$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == \"org.hexciri.about\") | \"\\(.address) \\(.size[0]) \\(.size[1])\"' 2>/dev/null || echo \"\")\"",
    "    [[ -n ${address:-} && $cols -gt 0 && $rows -gt 0 && $width -gt 0 && $height -gt 0 ]] || return 0",
    "    if (( cols >= target_c && cols <= target_c + 1 && rows >= target_r && rows <= target_r + 1 )); then return 0; fi",
    "    (( ++nudges <= 2 )) || return 0",
    "    shift_w=$(( (target_c - cols) * width ))",
    "    shift_h=$(( (target_r - rows) * height ))",
    "    target_w=$(( width + (shift_w >= 0 ? (shift_w + cols - 1) / cols : shift_w / cols) ))",
    "    target_h=$(( height + (shift_h >= 0 ? (shift_h + rows - 1) / rows : shift_h / rows) ))",
    "    read -r mon_w mon_h <<<\"$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | \"\\(.width) \\(.height)\"' 2>/dev/null || echo \"\")\"",
    "    if [[ -n ${mon_w:-} && $mon_w -gt 0 ]]; then (( target_w > mon_w * 95 / 100 )) && target_w=$(( mon_w * 95 / 100 )); (( target_h > mon_h * 95 / 100 )) && target_h=$(( mon_h * 95 / 100 )); fi",
    "    hyprctl dispatch resizewindowpixel \"exact $target_w $target_h,address:$address\" >/dev/null 2>&1 || return 0",
    "    hyprctl dispatch centerwindow >/dev/null 2>&1 || true",
    "    _about_settle",
    "  done",
    "}",
    "if [[ ${1:-} == \"--render\" ]]; then",
    "  export LC_ALL=C.UTF-8 LANG=C.UTF-8",
    "  _about_fit",
    "  clear",
    "  _about_config",
    "  echo",
    "  read -n1 -s -r -p \"Press any key to close...\" || true",
    "  exit 0",
    "fi",
    "exec hexciri-launch-or-focus-tui --app-id=org.hexciri.about hexciri-launch-about --render",
]
with open(la, "w") as f:
    f.write("\n".join(_about_lines) + "\n")
os.chmod(la, 0o755)
changed.append("launch-about: two-mode script, --render runs fastfetch + read inside the terminal (bash -c quoting trap fixed)")
sl = root + "/default/hypr/apps/system.lua"
with open(sl) as f:
    _sl = f.read()
_sl_orig = _sl
_sl = _sl.replace("size = { 920, 480 }", "size = { 1280, 800 }", 1)
_sl = _sl.replace("-- The About fastfetch layout needs more columns than the standard float provides.\n-- This size only covers the first launch: hexciri-launch-about measures the\n-- rendered content, remembers the size that hugs it, and applies that as its own\n-- rule before every later launch.", "-- About is a floating fastfetch (hexciri-launch-about): this fixed\n-- 1280x800 starting float; --render fits it to the content at launch.")
if _sl != _sl_orig:
    with open(sl, "w") as f:
        f.write(_sl)
    changed.append("system.lua: About float comment updated (no fit measurement)")
else:
    print("WARN: system.lua About comment not found, comment NOT updated")

# 4. hexciri-install-editor-zed: `omazed` is an Omarchy-repo package that does
#    not exist on Arch, so `pkg-add zed omazed` fails and the Zed row is dead.
#    Install plain zed; theming Zed is out of v2 scope.
zed = root + "/bin/hexciri-install-editor-zed"
if os.path.isfile(zed):
    with open(zed) as f:
        z = f.read()
    z_orig = z
    z = z.replace("hexciri-pkg-add zed omazed", "hexciri-pkg-add zed")
    z = z.replace("omazed setup", "# omazed is Omarchy-repo-only, not installed: skip Zed theme setup")
    if z != z_orig:
        with open(zed, "w") as f:
            f.write(z)
        changed.append("install-editor-zed: dropped omazed (Omarchy-repo-only)")
    else:
        print("install-editor-zed: omazed already gone, skipping")
else:
    print("WARN: hexciri-install-editor-zed not in fork, Zed row will drop")

# 5. lifecycle-dispatch is a no-op on x86 (upstream docs/lifecycle-dispatch.md):
#    only Apple Silicon registers a platform package. The fork never copies
#    it, so the bare calls in install-browser / install-gaming-steam /
#    remove-gaming-steam die under set -e. Guard them.
for _lf in ("hexciri-install-browser", "hexciri-install-gaming-steam", "hexciri-remove-gaming-steam"):
    _lp = root + "/bin/" + _lf
    if os.path.isfile(_lp):
        with open(_lp) as f:
            _lt = f.read()
        _lt_orig = _lt
        _lt = re.sub(r'hexciri-lifecycle-dispatch (post-install|pre-remove) (\S+)', r'command -v hexciri-lifecycle-dispatch >/dev/null 2>&1 && hexciri-lifecycle-dispatch \1 \2 || true', _lt)
        if _lt != _lt_orig:
            with open(_lp, "w") as f:
                f.write(_lt)
            changed.append(_lf + ": lifecycle-dispatch calls guarded (no-op on x86)")
        else:
            print(_lf + ": no lifecycle-dispatch calls found, skipping")

# 6. hexciri-remove-security-fingerprint: upstream removes fingerprint from
#    sudo, polkit and the lock screen, but never from SDDM, so removing the
#    finger would leave /etc/pam.d/sddm demanding a touch after the
#    password. Strip the SDDM lines and the theme.conf Fingerprint key too.
rfp = root + "/bin/hexciri-remove-security-fingerprint"
if os.path.isfile(rfp):
    with open(rfp) as f:
        r = f.read()
    r_orig = r
    _rfp_fn = '\nremove_sddm_fingerprint_pam() {\n  # Hexciri SDDM lines (2026-11-24): removing the finger must also remove\n  # the SDDM fingerprint lines, or SDDM keeps demanding a touch after the\n  # password. Strip the pam_unix-first line too, it belongs to the block.\n  if [[ -f /etc/pam.d/sddm ]] && grep -Eq \'pam_fprintd\\.so|hexciri-hw-laptop-closed|try_first_pass likeauth nullok\' /etc/pam.d/sddm; then\n    echo "Removing fingerprint authentication from SDDM..."\n    sudo sed -i -e \'/pam_fprintd\\.so/d\' -e \'/hexciri-hw-laptop-closed/d\' -e \'/try_first_pass likeauth nullok/d\' /etc/pam.d/sddm\n  fi\n  if [[ -f /usr/share/sddm/themes/hexciri/theme.conf ]]; then\n    sudo sed -i \'/^Fingerprint=/d\' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null || true\n  fi\n}\n'
    if "remove_sddm_fingerprint_pam" in r:
        print("remove-security-fingerprint SDDM strip already present, skipping")
    elif r.count("\n}\n\nremove_lock_fingerprint_pam()") == 1:
        r = r.replace("\n}\n\nremove_lock_fingerprint_pam()", "\n}\n" + _rfp_fn + "\nremove_lock_fingerprint_pam()", 1)
        changed.append("remove-security-fingerprint: SDDM strip function added")
    else:
        print("WARN: remove_lock_fingerprint_pam anchor not found, SDDM strip NOT added")
    if "remove_sddm_fingerprint_pam\nremove_lock_fingerprint_pam" not in r and r.count("remove_pam_config\nremove_lock_fingerprint_pam") == 1:
        r = r.replace("remove_pam_config\nremove_lock_fingerprint_pam", "remove_pam_config\nremove_sddm_fingerprint_pam\nremove_lock_fingerprint_pam", 1)
        changed.append("remove-security-fingerprint: SDDM strip called after remove_pam_config")
    if r != r_orig:
        with open(rfp, "w") as f:
            f.write(r)
else:
    print("WARN: hexciri-remove-security-fingerprint not in fork, fingerprint row will drop")

for c in changed:
    print("  fork patch: " + c)
PY

# --- Fork-time patch: theme-set-gnome writes GTK settings.ini (2026-11-24) ---
# Upstream theme-set-gnome only sets gsettings and exits before doing
# anything when there is no DBus session, so it never wrote settings.ini
# and, from a tty3 install, never set dconf at all. It also set the theme
# name to Adwaita-dark, which is not a theme name (see the GTK step above).
# Every theme switch must rewrite both settings.ini files with theme name
# Adwaita + prefer-dark, and set dconf (through dbus-run-session when there
# is no live bus), or the file picker goes light again on the next switch.
python3 - "$FORK_OUT" <<'PY'
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

# --- Fork-time patch: hexciri-update for EndeavourOS (Phase 2, 2026-11-24) ---
# Rework upstream omarchy-update into the Hexciri update pipeline. Do NOT
# call eos-update directly and do NOT build a new updater: the forked
# hexciri-update stays the orchestrator (lock, transcript, confirm, sudo
# keepalive, stay-awake, status refresh, restart prompt, shell restart),
# only its steps are swapped for EndeavourOS:
#   * No snapshot. Devi 2026-11-24: systemd-boot + ext4, no GRUB/btrfs, so
#     snapshots are not a thing; eos-update --aur + Hexciri sync is enough.
#   * System packages: pacman directly, unattended. The start confirm
#     in hexciri-update is the one approval; after it
#     HEXCIRI_UPDATE_UNATTENDED=1, so the pacman --noconfirm path runs
#     and eos-update --aur does not (eos-update has NO --noconfirm
#     flag, and yay inside it prompts [Y/n] for e.g. mise). Db sync
#     runs captured (no "is up to date" lines), checkupdates counts
#     pending updates, pacman -Su runs live so the ILoveCandy bar
#     shows, then one status line. A .pacnew in /etc gets one line.
#   * AUR: yay output is captured, one status line instead ("AUR
#     packages are up to date" / "AUR packages updated"). The EOS
#     marker branch prints the same one line, never "skipping".
#   * Hexciri self-update: the dev-checkout step is a no-op on an installed
#     machine (HEXCIRI_PATH is /usr/share/hexciri, not a checkout), so
#     hexciri-update-hexciri (repo file v2/hexciri-update-hexciri) syncs
#     nyx with git like v1 (clone/pull ~/.local/opt/hexciri-nyx, no
#     auth, tarball fallback) and re-runs this installer when the
#     installer sha changed, judged by /usr/share/hexciri/.installer-sha.
#     Output is quiet (2026-11-24, Devi): one themed 'Updating Hexciri'
#     header and one short status line on screen; full shas, paths and
#     reasons go to /tmp/hexciri-update-hexciri.log (or to the screen
#     with HEXCIRI_UPDATE_VERBOSE=1). Real errors still print clearly.
#     The installer re-places /usr/share/hexciri/bin while hexciri-update
#     is running, so if hexciri-update itself changed it re-execs the new
#     copy (same PID, so the sudo keepalive and the update lock survive).
#   * Keyring: Arch + EndeavourOS keyrings only. There is no Hexciri
#     keyring package, no WKD key, no pkgs@hexciri.org, no Omarchy repo.
#   * Boot: no lifecycle-dispatch package is registered (it is a no-op on
#     x86 and is deliberately not copied), so boot verification runs
#     bootctl status directly instead of failing with 127.
#   * Available: the upstream check only counted the omarchy package, which
#     Hexciri does not ship, so it always reported up to date. Now any
#     pending checkupdates entry counts.
#   * Analyze-logs: dracut failure strings added (EndeavourOS default,
#     not mkinitcpio).
#   * Pacman guard: replaced by a no-op. The guard as shipped blocks any
#     direct pacman call, which is exactly what eos-update and yay do.
#   * mise: hexciri-mise-install / hexciri-mise-default-tools are now
#     copied (allowlist above), /etc/mise/conf.d/hexciri-tools.toml is
#     installed below, shims are on PATH in profile.d and uwsm env.
step "Patching hexciri-update for EndeavourOS (eos-update --aur, no snapshot, Hexciri self-update, mise)"
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-update-hexciri" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-update-hexciri" "$FORK_OUT/bin/hexciri-update-hexciri"
  chmod +x "$FORK_OUT/bin/hexciri-update-hexciri"
  info "  update: hexciri-update-hexciri installed (nyx git sync self-update, tarball fallback, re-runs installer when it changed)"
else
  die "v2/hexciri-update-hexciri not in the installer tree, hexciri update cannot pull Hexciri updates"
fi
# hexciri-theme-ansi (repo file v2/hexciri-theme-ansi): prints the ANSI
# truecolor escape for a named color from the ACTIVE theme, so update
# output follows the theme instead of stock Omarchy green. Copied here
# like hexciri-update-hexciri, same step as the update fork patch below.
if [ -f "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-ansi" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/v2/hexciri-theme-ansi" "$FORK_OUT/bin/hexciri-theme-ansi"
  chmod +x "$FORK_OUT/bin/hexciri-theme-ansi"
  info "  update: hexciri-theme-ansi installed (theme-matched green/red for update output)"
else
  die "v2/hexciri-theme-ansi not in the installer tree, update output falls back to stock green"
fi
python3 - "$FORK_OUT" <<'PY'
import sys
fork = sys.argv[1]

def read(p):
    with open(p) as f:
        return f.read()

def write(p, text):
    with open(p, "w") as f:
        f.write(text)

def must_replace(path, old, new, what):
    text = read(path)
    assert text.count(old) == 1, "%s: anchor not unique in %s (count %d)" % (what, path, text.count(old))
    write(path, text.replace(old, new, 1))
    print("  update: %s" % what)

upd = fork + "/bin/hexciri-update"

# 1. Drop the snapshot step. BUG (2026-11-24, Devi: Prune package cache
# missing): upstream called hexciri-update-pkg-prune BEFORE the snapshot,
# with the "Before the snapshot:" comment above it, so the prune CALL was
# inside the deleted lines[start:end+1] range and got dropped with the
# snapshot. The replacement comment then claimed "the cache prune above
# stays", which was false: nothing called pkg-prune any more (sim6out
# had the call, sim7out has zero). Restore the call here, in the same
# place upstream had it: after authorize, before stay-awake / self-update
# / system-pkgs. No snapshot on Hexciri (systemd-boot + ext4), so there
# is no snapshot for the prune to precede; it just runs before any update.
lines = read(upd).splitlines(keepends=True)
start = next(i for i, l in enumerate(lines) if "Before the snapshot:" in l)
end = next(i for i, l in enumerate(lines) if "update.noSnapshot" in l)
assert end > start, "snapshot block bounds wrong"
lines[start:end + 1] = [
    "  # No snapshot: Devi 2026-11-24, systemd-boot + ext4, no GRUB/btrfs,\n",
    "  # so snapshots are not a thing. eos-update --aur + Hexciri sync is\n",
    "  # enough. No snapshot, so the prune runs here, before any update.\n",
    "  hexciri-update-pkg-prune\n",
]
write(upd, "".join(lines))
print("  update: snapshot step dropped from hexciri-update")

# 2. Hexciri self-update before update-dev, with a re-exec guard: the
# installer re-places /usr/share/hexciri/bin while this script runs.
must_replace(upd, "  hexciri-update-dev\n", "\n".join([
    "  # Hexciri self-update first: pull nyx and re-run the installer when it",
    "  # changed. On an installed machine update-dev is a no-op (HEXCIRI_PATH is",
    "  # /usr/share/hexciri, not a checkout), so it cannot pull Hexciri updates.",
    "  if [[ ${HEXCIRI_UPDATE_SELF_DONE:-0} != \"1\" ]]; then",
    "    _hexciri_update_self_before=\"$(sha256sum \"$0\" 2>/dev/null || true)\"",
    "    _hexciri_update_self_before=\"${_hexciri_update_self_before%% *}\"",
    "    hexciri-update-hexciri",
    "    _hexciri_update_self_after=\"$(sha256sum \"$0\" 2>/dev/null || true)\"",
    "    _hexciri_update_self_after=\"${_hexciri_update_self_after%% *}\"",
    "    # If this script itself changed, re-exec the new copy so the rest of",
    "    # the pipeline runs new code. Same PID after exec, so the sudo",
    "    # keepalive and the update lock survive.",
    "    if [[ -n \"$_hexciri_update_self_before\" && -n \"$_hexciri_update_self_after\" && \"$_hexciri_update_self_before\" != \"$_hexciri_update_self_after\" ]]; then",
    "      exec env HEXCIRI_UPDATE_REEXECED=1 HEXCIRI_UPDATE_SELF_DONE=1 HEXCIRI_UPDATE_LOGGED=1 \"$0\" \"$@\"",
    "    fi",
    "    export HEXCIRI_UPDATE_SELF_DONE=1",
    "  fi",
    "",
    "  hexciri-update-dev",
]) + "\n", "hexciri-update calls hexciri-update-hexciri before update-dev")

# 2b. No second Ready box after a self-update re-exec (2026-11-24, Devi:
# the confirm box showed again after "Hexciri updated to ..."). When the
# installer re-placed hexciri-update, it re-execs the new copy with
# HEXCIRI_UPDATE_REEXECED=1 (same PID, sudo keepalive and lock survive).
# The first pass already confirmed and authorized, so the re-exec must
# skip the confirm box. authorize_update itself is made a no-op on a
# re-exec (next must_replace) instead of nesting the call: the marker /
# UNATTENDED exports inserted after the call still have to run on the
# re-exec pass.
must_replace(upd, "if [[ ${1:-} == \"-y\" ]] || hexciri-update-confirm; then\n  authorize_update\n",
    "if [[ ${1:-} == \"-y\" || ${HEXCIRI_UPDATE_REEXECED:-0} == \"1\" ]] || hexciri-update-confirm; then\n  authorize_update\n",
    "hexciri-update skips the second confirm on a self-update re-exec")
must_replace(upd, "authorize_update() {\n  sudo true || return 1\n",
    "authorize_update() {\n  # Re-exec after self-update: the first pass already authorized\n  # and its sudo keepalive is still running (same PID after exec).\n  # Do not start a second keepalive the cleanup never kills.\n  if [[ ${HEXCIRI_UPDATE_REEXECED:-0} == \"1\" ]]; then\n    return 0\n  fi\n  sudo true || return 1\n",
    "authorize_update is a no-op on a self-update re-exec")

# 3. Marker path for this run only: system-pkgs sets it when eos-update --aur
# already updated the AUR, so the aur-pkgs step skips its duplicate yay run.
must_replace(upd, "  authorize_update\n",
    "  authorize_update\n  # Marker file for this run only (underscores, not hyphens, so the\n  # fork scan does not read it as a hexciri-* command name).\n  export HEXCIRI_UPDATE_EOS_MARKER=\"/tmp/hexciri_update_eos_aur_$$.marker\"\n",
    "hexciri-update exports the eos-update AUR marker path")

# 3b. Unattended after the single start confirm (2026-11-24, Devi:
# once it finds an update it should all just be -y, no more Y/n
# prompts). The confirm above is the one approval; after it the run
# is unattended, so system-pkgs takes the pacman --noconfirm path
# instead of eos-update (whose yay prompts [Y/n]), the reboot step
# prints "reboot later" instead of prompting, and a real package
# conflict fails with "run interactively" instead of sitting on a
# prompt nobody answers.
must_replace(upd, "  authorize_update\n",
    "  authorize_update\n  export HEXCIRI_UPDATE_UNATTENDED=1\n",
    "hexciri-update is unattended after the single start confirm")

# 4. Cleanup removes the marker (cleanup_update calls end_update_authorization;
# the same call also appears in the main flow after boot verification, so
# anchor on the cleanup_update function header, not on the call alone).
must_replace(upd, "cleanup_update() {\n  local status=$?\n  trap - EXIT HUP INT TERM\n  end_update_authorization\n",
    "cleanup_update() {\n  local status=$?\n  trap - EXIT HUP INT TERM\n  end_update_authorization\n  rm -f \"${HEXCIRI_UPDATE_EOS_MARKER:-}\" 2>/dev/null || true\n",
    "hexciri-update cleanup removes the eos-update AUR marker")

# 5. aur-pkgs: whole-file rewrite (2026-11-24, Devi: quiet AUR step).
# The EOS-marker branch prints one line ("AUR packages are up to
# date"), never "already updated by eos-update --aur, skipping".
# Otherwise yay output is captured and one status line is shown.
_aur = fork + "/bin/hexciri-update-aur-pkgs"
with open(_aur, "w") as f:
    f.write(r'''#!/bin/bash

# omarchy:summary=Update AUR packages if any are installed

# mise exports GOROOT and GOBIN for its own Go. hexciri-upgrade-to-quattro runs
# this with the system PATH but the caller's environment, so /usr/bin/go would
# compile with mise's toolchain and every Go PKGBUILD fails with
# "compile: version ... does not match go tool version". With both unset,
# whichever go is on PATH uses its own root.
unset GOROOT GOBIN

# eos-update --aur already did the AUR in the system-pkgs step; the marker
# file is set by hexciri-update for this run only. One line, no "skipping",
# no duplicate yay run. In a normal `hexciri update` this branch is not
# reached (system-pkgs takes the pacman path and leaves the marker unset);
# it is kept for a standalone interactive run.
if [[ -n ${HEXCIRI_UPDATE_EOS_MARKER:-} && -f $HEXCIRI_UPDATE_EOS_MARKER ]]; then
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.aur)\e[0m"
  echo "AUR packages are up to date"
  exit 0
fi

if pacman -Qem >/dev/null; then
  # Header FIRST, before the accessibility check (2026-11-24, Devi: the
  # AUR error appeared right under "Update mise tools" with no AUR header
  # at all, so it read as a mise error). mise never calls the AUR helper;
  # the next step after mise is this one, and its old else branch only
  # printed the red "AUR is unavailable" line, never the step header.
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.aur)\e[0m"
  # Is the AUR reachable? Prefer the helper, but do NOT fail with
  # "command not found" if it is missing from the fork (2026-11-24: it
  # was not in the bin allowlist, so the fork never copied it and every
  # update reported "AUR is unavailable"). Fall back to the same curl
  # check the helper does, inline.
  _aur_accessible=0
  if command -v hexciri-pkg-aur-accessible >/dev/null 2>&1; then
    hexciri-pkg-aur-accessible && _aur_accessible=1 || _aur_accessible=0
  elif curl -sf --connect-timeout 30 --retry 3 --retry-delay 3 -A "hexciri-update" "https://aur.archlinux.org/rpc/?v=5&type=info&arg=base" >/dev/null 2>&1; then
    _aur_accessible=1
  fi
  if [[ "$_aur_accessible" == "1" ]]; then
    # Quiet on purpose (2026-11-24, Devi): yay prints "Searching AUR for
    # updates... there is nothing to do" and build logs. Capture it, show
    # one status line instead. Real failures print the captured output.
    _aur_log="$(mktemp /tmp/hexciri-aur.XXXXXX)"
    if yay -Sua --noconfirm --cleanafter --ignore gcc14,gcc14-libs >"$_aur_log" 2>&1; then
      _aur_ok=1
    else
      _aur_ok=0
    fi
    # thpm (2026-11-24, Devi): kicked off AUR, installed via GitHub
    # (OldJobobo/thpm) source script, not yay/pacman, so yay's
    # "Packages not in AUR: thpm" warning is expected noise. Strip it
    # from the log before judging success, and never report AUR as
    # failing / unavailable because of thpm alone: if the filtered log
    # says "there is nothing to do", it is up to date even if yay
    # exited non-zero over thpm. Failure output shows the filtered
    # log, never the thpm line.
    grep -v "Packages not in AUR: thpm" "$_aur_log" >"$_aur_log.filtered" 2>/dev/null || true
    if grep -q "there is nothing to do" "$_aur_log.filtered"; then
      echo "AUR packages are up to date"
      rm -f "$_aur_log" "$_aur_log.filtered"
    elif [[ "$_aur_ok" == "1" ]]; then
      echo "AUR packages updated"
      grep -E "upgrading" "$_aur_log.filtered" | sed 's/^/  /' || true
      rm -f "$_aur_log" "$_aur_log.filtered"
    else
      echo "ERROR: AUR update failed, output:" >&2
      cat "$_aur_log.filtered" >&2
      rm -f "$_aur_log" "$_aur_log.filtered"
      exit 1
    fi
    echo
  else
    echo "AUR is unavailable, skipping AUR updates (aur.archlinux.org not reachable)"
    echo
  fi
fi
''')
print("  update: hexciri-update-aur-pkgs rewritten (quiet: one status line, no duplicate yay output)")

# 6. boot: verify systemd-boot directly when lifecycle-dispatch is absent.
must_replace(fork + "/bin/hexciri-update-boot", "set -e\n",
    "set -e\n\n# x86 / systemd-boot: no lifecycle-dispatch package is registered (it is a\n# no-op on x86 and is deliberately not copied), so verify the boot chain\n# directly instead of failing with 127 on a missing command.\nif ! command -v hexciri-lifecycle-dispatch >/dev/null 2>&1; then\n  if bootctl status >/dev/null 2>&1 || sudo bootctl status >/dev/null 2>&1; then\n    exit 0\n  fi\n  echo \"Warning: bootctl status failed, boot chain not verified\" >&2\n  exit 1\nfi\n",
    "hexciri-update-boot verifies systemd-boot directly when lifecycle-dispatch is absent")

# 7. confirm: the whats-new link pointed at omacom/hexciri, which is not a repo.
# 2026-11-24: repo root, not releases/latest -- Devi does no releases/ISOs.
must_replace(fork + "/bin/hexciri-update-confirm",
    "https://github.com/omacom/hexciri/releases/latest",
    "https://github.com/Deoxizn/hexciri",
    "hexciri-update-confirm points at Deoxizn/hexciri (repo root, no releases)")

# 8. Theme-matched green/red in update output, 2026-11-24: upstream prints
# section headers with hardcoded \e[32m (stock Omarchy green) and errors
# with \e[31m. Replace both with hexciri-theme-ansi, which reads the green /
# red of the ACTIVE theme (current/theme/colors.toml), falling back to the
# theme accent, then dirty.pizza #33ff99 / #ff3333 with no theme set. The
# helper prints a truecolor escape, which echo -e / printf interpret.
# Scope is the update presentation path only: update-* bins, show-logo,
# show-done. Other bins keep their own colours.
for _name in ["hexciri-update", "hexciri-update-system-pkgs", "hexciri-update-keyring", "hexciri-update-aur-pkgs", "hexciri-update-mise", "hexciri-update-dev", "hexciri-update-firmware", "hexciri-update-orphan-pkgs", "hexciri-update-pkg-prune", "hexciri-update-restart", "hexciri-update-analyze-logs", "hexciri-show-logo", "hexciri-show-done"]:
    _p = fork + "/bin/" + _name
    _t = read(_p)
    _t = _t.replace("\\e[32m", "$(hexciri-theme-ansi green)")
    _t = _t.replace("\\033[32m", "$(hexciri-theme-ansi green)")
    _t = _t.replace("\\033[0;31m", "$(hexciri-theme-ansi red)")
    _t = _t.replace("\\e[31m", "$(hexciri-theme-ansi red)")
    _t = _t.replace("\\033[31m", "$(hexciri-theme-ansi red)")
    write(_p, _t)
    print("  update: theme-matched green/red in %s" % _name)
PY

# 8b. Single-quote fix, 2026-11-24: step 8 above replaced \e[32m / \e[31m
# with $(hexciri-theme-ansi ...) even inside single-quoted strings, where
# bash never expands $(). hexciri-show-done printed the literal
# "$(hexciri-theme-ansi green)● Done!" and hexciri-update-analyze-logs
# would print the literal on an initramfs failure. Capture the escape in
# a variable first (show-done) and switch the analyze-logs line to
# double quotes. The trap line in hexciri-update is NOT fixed here: a
# trap string is evaluated when it fires, so $() inside it DOES expand.
python3 - "$FORK_OUT" <<'PYEOF8B'
import sys
fork = sys.argv[1]
def read(p):
    with open(p) as f:
        return f.read()
def write(p, t):
    with open(p, "w") as f:
        f.write(t)
SQ = chr(39)
# show-done: two printf lines, green and red.
_p = fork + "/bin/hexciri-show-done"
_t = read(_p)
_old_g = "  printf " + SQ + "\\n$(hexciri-theme-ansi green)\u25cf \\033[0m%s" + SQ + ' "$(hexciri-i18n done.success)" >/dev/tty'
_new_g = '  _show_done_color="$(hexciri-theme-ansi green)"\n  printf ' + SQ + "\\n%s\u25cf \\033[0m%s" + SQ + ' "$_show_done_color" "$(hexciri-i18n done.success)" >/dev/tty'
assert _old_g in _t, "show-done green line not found: " + repr(_t[-600:])
_t = _t.replace(_old_g, _new_g, 1)
_old_r = "  printf " + SQ + "\\n$(hexciri-theme-ansi red)\u25cf \\033[0m%s" + SQ + ' "$(hexciri-i18n done.failed "$code")" >/dev/tty'
_new_r = '  _show_done_color="$(hexciri-theme-ansi red)"\n  printf ' + SQ + "\\n%s\u25cf \\033[0m%s" + SQ + ' "$_show_done_color" "$(hexciri-i18n done.failed "$code")" >/dev/tty'
assert _old_r in _t, "show-done red line not found"
_t = _t.replace(_old_r, _new_r, 1)
write(_p, _t)
print("  update: show-done captures theme colour in a variable (no more literal)")
# analyze-logs: the initramfs line was echo -e '...' (single quotes).
_p = fork + "/bin/hexciri-update-analyze-logs"
_t = read(_p)
_old = "echo -e " + SQ + "$(hexciri-theme-ansi red)Error: Initramfs generation may have failed. Review logs before restart.\\e[0m" + SQ
_new = 'echo -e "$(hexciri-theme-ansi red)Error: Initramfs generation may have failed. Review logs before restart.\\e[0m"'
assert _old in _t, "analyze-logs initramfs line not found"
_t = _t.replace(_old, _new, 1)
write(_p, _t)
print("  update: analyze-logs initramfs line uses double quotes (no more literal)")
PYEOF8B

# 9. pkg-prune: whole-file rewrite (2026-11-24, Devi: Prune package
# cache was missing from hexciri update, see Fix 1 above). Upstream bin
# printed the themed header then ran `sudo paccache -rk2` live, whose
# output is the Omarchy line Devi quoted:
#   Prune package cache
#   ==> finished: 3 packages removed (disk space saved: 83.23 MiB)
# Quiet version: capture paccache, show ONE status line only (the
# finished line, or "Package cache is clean" when it finds no
# candidates). paccache -rk2 keeps 2 versions, the only offline
# downgrade path, and is non-interactive, so no Y/n prompt. A paccache
# failure prints the pruneFailed warning and the update continues.
cat > "$FORK_OUT/bin/hexciri-update-pkg-prune" <<'PRUNE_EOF'
#!/bin/bash

# omarchy:summary=Prune superseded versions from the pacman package cache
# omarchy:requires-sudo=true

set -e

# The cache is the only offline downgrade path, so keep two. Run before the
# packages update and the installed version survives with a spare. paccache
# retains by version order, never by what is installed.
echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.pruneCache)\e[0m"
_prune_log="$(mktemp /tmp/hexciri-pkg-prune.XXXXXX)"
if sudo paccache -rk2 >"$_prune_log" 2>&1; then
  _finished="$(grep -E 'finished:' "$_prune_log" | tail -1 || true)"
  if [[ -n "$_finished" ]]; then
    # "==> finished: 3 packages removed (disk space saved: 83.23 MiB)"
    echo "${_finished#==> }"
  elif grep -qi 'no candidate' "$_prune_log"; then
    echo "Package cache is clean"
  else
    echo "Package cache pruned"
  fi
else
  echo -e "\e[33m$(hexciri-i18n update.pruneFailed)\e[0m" >&2
  cat "$_prune_log" >&2 || true
fi
rm -f "$_prune_log"
echo
PRUNE_EOF
info "  update: hexciri-update-pkg-prune rewritten (quiet: one status line, paccache -rk2)"

# 10. Section consistency (2026-11-24, Devi: Omarchy style, every step
# its own little section with themed header + one-line status).
#   a. orphan-pkgs: was silent when no orphans existed, so the step had
#      no section at all. Now always prints the themed header, then
#      "No orphaned packages" when none. Removal behaviour unchanged:
#      called with -y by hexciri-update, so orphans are removed without
#      a gum prompt; standalone non-tty use still reports and exits.
#   b. mise: ran `mise up` live. Now captured, one status line only.
cat > "$FORK_OUT/bin/hexciri-update-orphan-pkgs" <<'ORPHAN_EOF'
#!/bin/bash

# omarchy:summary=Review and optionally remove orphaned system packages after updates
# omarchy:args=[-y]
# omarchy:examples=hexciri update orphan-pkgs | hexciri update orphan-pkgs -y
# omarchy:requires-sudo=true

set -e

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.orphans)\e[0m"
mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
if (( ${#orphans[@]} == 0 )); then
  echo "No orphaned packages"
  echo
  exit 0
fi
printf '  %s\n' "${orphans[@]}"
echo

if [[ ${1:-} != "-y" && ( ! -t 0 || ! -t 1 ) ]]; then
  echo "$(hexciri-i18n --count "${#orphans[@]}" update.orphansFound "${#orphans[@]}" hexciri-update-orphan-pkgs)"
  echo
  exit 0
fi

if [[ ${1:-} != "-y" ]] && ! gum confirm --default=false --affirmative "$(hexciri-i18n common.yes)" --negative "$(hexciri-i18n common.no)" "$(hexciri-i18n --count "${#orphans[@]}" update.removeOrphans "${#orphans[@]}")"; then
  echo "$(hexciri-i18n update.keepingOrphans)"
  echo
  exit 0
fi

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.removingOrphans)\e[0m"
hexciri-pkg-drop "${orphans[@]}"
echo
ORPHAN_EOF
info "  update: hexciri-update-orphan-pkgs rewritten (always a section, one line when none)"

cat > "$FORK_OUT/bin/hexciri-update-mise" <<'MISE_EOF'
#!/bin/bash

# omarchy:summary=Update mise-managed tools

if hexciri-cmd-present mise; then
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.mise)\e[0m"

  # mise withholds releases younger than its cooldown, so tools stay behind for
  # days after they ship. Running hexciri update is the user asking for current
  # versions now, which is the same call the mup alias makes by hand.
  # Quiet (2026-11-24, Devi): capture `mise up`, show one status line only,
  # like the other sections. Failure still exits non-zero so hexciri-update
  # sets mise_updated=0 and prints the retry hint at the end.
  _mise_log="$(mktemp /tmp/hexciri-mise.XXXXXX)"
  if MISE_MINIMUM_RELEASE_AGE=0 mise up >"$_mise_log" 2>&1; then
    if grep -qi "up to date" "$_mise_log"; then
      echo "All tools are up to date"
    else
      echo "Mise tools updated"
      grep -iE "updated|installed" "$_mise_log" | sed 's/^/  /' || true
    fi
    rm -f "$_mise_log"
  else
    echo "ERROR: mise update failed, output:" >&2
    cat "$_mise_log" >&2
    rm -f "$_mise_log"
    exit 1
  fi
  echo
fi
MISE_EOF
info "  update: hexciri-update-mise rewritten (quiet: one status line)"

# Whole-file rewrites: keyring, system-pkgs, pacman guard, available.
# The keyring file: Arch + EndeavourOS keyrings only. No Hexciri keyring
# package, no WKD key, no pkgs@hexciri.org, no Omarchy repo. ARM handling
# dropped: Hexciri machines are x86_64.
cat > "$FORK_OUT/bin/hexciri-update-keyring" <<'KEYRING_EOF'
#!/bin/bash
# Hexciri: refresh Arch + EndeavourOS keyrings only. There is no Hexciri
# keyring package, no WKD key, no pkgs@hexciri.org, no Omarchy repo, so the
# upstream keyring step (which tries to install a Hexciri keyring package
# from the Omarchy repo) cannot work here. ARM keyring handling is dropped
# too: Hexciri machines are x86_64.
set -euo pipefail

keyrings=(archlinux-keyring)
if pacman -Qq endeavouros-keyring >/dev/null 2>&1; then
  keyrings+=(endeavouros-keyring)
fi

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.signingKeys)\e[0m"
# Quiet on purpose (2026-11-24, Devi): pacman-key --populate prints
# "Appending keys..." / "Updating trust database..." and `pacman -Sy
# --needed` prints the db sync lines plus "warning: <keyring> is up to
# date -- skipping" twice and "there is nothing to do". All of that
# reads as errors to a new person when it is really nothing. Capture
# everything, show it only if something actually fails.
sudo pacman-key --populate archlinux endeavouros >/dev/null 2>&1 || sudo pacman-key --populate archlinux >/dev/null 2>&1 || true
_keyring_log="$(mktemp /tmp/hexciri-keyring.XXXXXX)"
if sudo pacman -Sy --needed --noconfirm "${keyrings[@]}" >"$_keyring_log" 2>&1; then
  if grep -qE "upgrading|installing|reinstalling" "$_keyring_log"; then
    echo "Keys updated"
  else
    echo "$(hexciri-i18n update.keysCorrect)"
  fi
else
  echo "ERROR: keyring update failed, output:" >&2
  cat "$_keyring_log" >&2
  rm -f "$_keyring_log"
  exit 1
fi
rm -f "$_keyring_log"
KEYRING_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-keyring"

# The system-pkgs file: pacman directly is the package engine (2026-11-24:
# eos-update --aur is kept only for a standalone interactive run, it has
# no --noconfirm and its yay prompts [Y/n]). pacman -Sy/-Su sync and
# upgrade every repo in /etc/pacman.conf, including [endeavouros], so EOS
# packages update here like any other repo package. The conflict handler
# below is unchanged: it takes over on a failed pacman run.
cat > "$FORK_OUT/bin/hexciri-update-system-pkgs" <<'SYSPKGS_EOF'
#!/bin/bash
# omarchy:summary=Update system packages with pacman
# omarchy:requires-sudo=true
# Hexciri (2026-11-24): the package engine is pacman directly, unattended.
# The start confirm in hexciri-update is the one approval; after it
# HEXCIRI_UPDATE_UNATTENDED=1, so this file never runs eos-update in a
# normal update (eos-update has no --noconfirm flag, and yay inside it
# prompts [Y/n] for e.g. mise). eos-update --aur is kept only for a
# standalone interactive run of this file.
# Flow: db sync quietly (captured, no "is up to date" lines), then
# checkupdates counts pending repo updates; if none, one line
# "System packages are up to date" and no upgrade run at all. If there
# are updates, pacman -Su runs live so the ILoveCandy Pac-Man bar shows,
# then one closing line. A .pacnew in /etc gets one warning line.
set -e

# The conflict handler's last resort: pacman puts its questions to the person
# running the update instead of answering them itself. Nothing here may capture
# a stream, because an upgrade without --noconfirm prompts on stderr. The
# handler has already said why, so no heading here either.
if [[ ${HEXCIRI_UPDATE_CONFLICT:-} == 1 && ${HEXCIRI_UPDATE_INTERACTIVE:-} == 1 ]]; then
  exec hexciri-update-pacman -Syu --overwrite '/usr/share/hexciri/*'
fi

# Standalone interactive run only: eos-update --aur. In a normal
# `hexciri update` UNATTENDED is already 1 (set after the start confirm),
# so this branch never runs there and its banner never prints.
if [[ ${HEXCIRI_UPDATE_UNATTENDED:-0} != "1" ]] && command -v eos-update >/dev/null 2>&1; then
  echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.systemPackages) (eos-update --aur)\e[0m"
  if eos-update --aur; then
    # Tell the aur-pkgs step the AUR is already done, for this run only.
    [[ -n ${HEXCIRI_UPDATE_EOS_MARKER:-} ]] && : > "$HEXCIRI_UPDATE_EOS_MARKER"
    exit 0
  fi
  echo "eos-update --aur failed, falling back to pacman (review /tmp/hexciri-update.log for details)." >&2
fi

echo -e "$(hexciri-theme-ansi green)\n$(hexciri-i18n update.systemPackages)\e[0m"

# Db sync, quiet: capture it, the "is up to date" lines are not shown.
_sync_log="$(mktemp /tmp/hexciri-syspkgs-sync.XXXXXX)"
if ! LC_ALL=C hexciri-update-pacman -Sy --noconfirm >"$_sync_log" 2>&1; then
  echo "ERROR: package database sync failed, output:" >&2
  cat "$_sync_log" >&2
  rm -f "$_sync_log"
  exit 1
fi
rm -f "$_sync_log"

# Nothing pending: one line, no upgrade run, no "there is nothing to do".
# checkupdates reads the just-synced db. Its exit codes (pacman-contrib):
# 0 = up to date, 2 = updates available, 1 = error. The old code treated
# ANY non-zero exit as "assume 1 pending", so an exit-2 run was reported
# as 1, and an exit-1 error run was reported as 1 even when pacman then
# found nothing to do ("System packages updated (1 package(s))" after
# "there is nothing to do", 2026-11-24). Count the lines whatever the
# exit code is; only on a real error fall back to pacman -Qu.
_pending_file="$(mktemp /tmp/hexciri-syspkgs-pending.XXXXXX)"
_checkupdates_status=0
checkupdates >"$_pending_file" 2>/dev/null || _checkupdates_status=$?
_pending="$(wc -l < "$_pending_file" | tr -d ' ')"
if [[ "$_checkupdates_status" == "1" ]]; then
  _pending="$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ')"
fi
rm -f "$_pending_file"
if [[ "$_pending" == "0" ]]; then
  echo "System packages are up to date"
  exit 0
fi

errors=$(mktemp)
trap 'rm -f "$errors"' EXIT

# EOS packages (2026-11-24, Devi: does dropping eos-update skip EOS
# pkgs?): no. pacman -Sy / -Su sync and upgrade EVERY repo in
# /etc/pacman.conf, and on EndeavourOS that includes [endeavouros]
# (eos-update, eos-hooks, endeavouros-keyring, welcome, ...). checkupdates
# counts those entries too, so an EOS package update is a pending update
# like any other. eos-update's other steps are covered elsewhere in this
# pipeline: keyring refresh (hexciri-update-keyring), free-space check
# (hexciri-update-requires-free-space), .pacnew check (below), AUR
# (hexciri-update-aur-pkgs). If the EOS repo is ever missing from
# pacman.conf, say so instead of silently skipping EOS pkgs.
if ! pacman -Sl endeavouros >/dev/null 2>&1; then
  echo "Warning: endeavouros repo not found in pacman config, EOS packages will not update" >&2
fi

# /usr/share/hexciri is wholly Hexciri's; files can land there unowned and would
# otherwise abort the upgrade. Packaged content wins there.
#
# Progress bars stay on stdout (ILoveCandy Pac-Man bar). Errors are on stderr,
# kept for the conflict handler below; LC_ALL=C is what keeps them parseable
# in any locale. stdout is tee'd to a log so the real upgrade count can be
# read back: _pending is only a pre-flight count, and pacman can still find
# nothing to do (db race, IgnorePkg, a package checkupdates counted but
# pacman skips). Never claim "updated (1)" when nothing was upgraded.
_su_log="$(mktemp /tmp/hexciri-syspkgs-su.XXXXXX)"
LC_ALL=C hexciri-update-pacman -Su --noconfirm \
  --overwrite '/usr/share/hexciri/*' 2>"$errors" | tee "$_su_log"
_su_status="${PIPESTATUS[0]}"
if [[ "$_su_status" == "0" ]]; then
  cat "$errors" >&2
  _upgraded="$(grep -cE '^\([0-9]+/[0-9]+\) upgrading ' "$_su_log" 2>/dev/null || true)"
  _upgraded="$(echo "$_upgraded" | tr -d ' ')"
  rm -f "$_su_log"
  _pacnew="$(find /etc -name '*.pacnew' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$_pacnew" != "0" ]]; then
    echo "Note: $_pacnew .pacnew file(s) in /etc need review (run pacdiff)" >&2
  fi
  if [[ "$_upgraded" == "0" ]]; then
    echo "System packages are up to date"
  else
    echo "System packages updated ($_upgraded package(s))"
  fi
  exit 0
fi
rm -f "$_su_log"
cat "$errors" >&2

# The handler takes it from here: it clears files pacman doesn't own yet and
# runs this again, and puts a package conflict to whoever started the update.
# Anything else, including a second failure, is for a human.
[[ ${HEXCIRI_UPDATE_RETRY:-} != 1 ]] || exit 1
# exec, so the EXIT trap above does not fire and the handler can still read the
# report. It takes over deleting it.
exec env HEXCIRI_UPDATE_CONFLICT=1 hexciri-update-system-pkgs-when-conflicted "$errors"

SYSPKGS_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-system-pkgs"

# The pacman guard file: no-op. The guard as shipped blocks any direct
# pacman call, which is exactly what eos-update and yay do, so it would
# break every update. There is no Hexciri repo to protect, no
# linux-omarchy kernel, no keyring pinning to defend.
cat > "$FORK_OUT/bin/hexciri-update-pacman-guard" <<'GUARD_EOF'
#!/bin/bash
# hexciri-update-pacman-guard: no-op in Hexciri. The guard as shipped blocks
# any direct pacman call, which is exactly what eos-update and yay do, so
# it would break every update. There is no Hexciri repo to protect, no
# linux-omarchy kernel, no keyring pinning to defend.
exit 0
GUARD_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-pacman-guard"

# The available file: upstream only counted the omarchy package after
# first-update, which Hexciri does not ship, so it always reported up to
# date. Now any pending checkupdates entry counts, plus a git checkout
# behind count when a dev checkout exists at ~/.local/opt/hexciri (v1 dev
# path) or ~/.local/opt/hexciri-nyx (v2 git sync); the installer sha
# check lives in hexciri-update-hexciri, not here).
cat > "$FORK_OUT/bin/hexciri-update-available" <<'AVAIL_EOF'
#!/bin/bash
# hexciri-update-available: check whether Hexciri / system updates are available.
# Exit 0 when updates exist (and list them), exit 1 when up to date.
# Used by the bar update indicator and by hexciri-update-status.
set -euo pipefail

updates=()
for _checkout in "$HOME/.local/opt/hexciri" "$HOME/.local/opt/hexciri-nyx"; do
  if [[ -d $_checkout/.git ]]; then
    upstream="$(git -C "$_checkout" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -n $upstream ]]; then
      behind="$(git -C "$_checkout" rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
      if (( behind > 0 )); then
        commit_label=commits
        (( behind == 1 )) && commit_label=commit
        updates+=("hexciri-dev-checkout $behind new $commit_label on $upstream")
      fi
    fi
  fi
done
unset _checkout

mapfile -t _pending < <(checkupdates --nocolor 2>/dev/null || true)
updates+=("${_pending[@]}")

if (( ${#updates[@]} > 0 )); then
  printf '%s\n' "${updates[@]}"
  exit 0
else
  echo "Hexciri is up to date"
  exit 1
fi
AVAIL_EOF
chmod +x "$FORK_OUT/bin/hexciri-update-available"

# Analyze-logs: dracut (EndeavourOS default, not mkinitcpio) plus a failed
# transaction, in the same plain-echo style as the existing checks.
cat >> "$FORK_OUT/bin/hexciri-update-analyze-logs" <<'ANALYZE_EOF'

# dracut (EndeavourOS default, not mkinitcpio): a failed initramfs rebuild
# shows as dracut errors in the log. Also surface a failed transaction.
if grep -qiE "dracut: (failed|error)|dracut:.*failed" "$update_log"; then
  echo -e "$(hexciri-theme-ansi red)Error: dracut reported errors during the update. Review logs before restart.\e[0m"
  echo
fi
if grep -q "error: failed to commit transaction" "$update_log"; then
  echo -e "$(hexciri-theme-ansi red)Error: pacman transaction failed. Review /tmp/hexciri-update.log before retrying.\e[0m"
  echo
fi
ANALYZE_EOF

# Every patched update script must still parse.
for _f in hexciri-update hexciri-update-system-pkgs hexciri-update-keyring hexciri-update-aur-pkgs hexciri-update-mise hexciri-update-available hexciri-update-boot hexciri-update-analyze-logs hexciri-update-hexciri hexciri-update-pacman-guard hexciri-update-confirm hexciri-theme-ansi; do
  bash -n "$FORK_OUT/bin/$_f" || die "bash -n failed on patched $_f"
done
unset _f
info "  update: hexciri-update patched (eos-update --aur, no snapshot, Hexciri self-update, mise, dracut log scan)"

# Save the fully patched fork for the next re-run (fork cache,
# 2026-11-24). Only when patches actually ran (SKIP_PATCHES=0) and
# the fingerprints were computed (a real install, not sim7, which
# sources only the fork block and has no PATCH_FP).
if [ "${SKIP_PATCHES:-0}" = "0" ] && [ -n "${PATCH_FP:-}" ] && [ -n "${FORK_CACHE_DIR:-}" ]; then
  mkdir -p "$FORK_CACHE_DIR"
  rm -rf "$FORK_CACHE_DIR/fork-out"
  cp -a "$FORK_OUT" "$FORK_CACHE_DIR/fork-out"
  printf '%s\n' "$PATCH_FP" > "$FORK_CACHE_DIR/patch-fingerprint"
  [ -n "${FORK_FP:-}" ] && printf '%s\n' "$FORK_FP" > "$FORK_CACHE_DIR/fork-fingerprint"
  info "Fork cache saved: $FORK_CACHE_DIR/fork-out (reused on the next update unless the fork changes)"
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

# --- Place the forked tree to its install targets ---
# sudo is used ONLY for the /usr/share and /etc steps below. Everything else
# runs as the normal user.

step "Placing forked tree: /usr/share/hexciri (sudo), ~/.config, ~/.local/state"

sudo rm -rf "$HEXCIRI_PATH"
sudo mkdir -p "$HEXCIRI_PATH"
sudo cp -a "$FORK_OUT/shell" "$FORK_OUT/default" "$FORK_OUT/themes" "$FORK_OUT/bin" "$FORK_OUT/install" "$FORK_OUT/icons" "$HEXCIRI_PATH/"
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
# Installer sha marker for hexciri-update-hexciri: it re-runs this installer
# only when the installer itself changed.
sha256sum "$INSTALLER_DIR/install.sh" 2>/dev/null | cut -d' ' -f1 | sudo tee "$HEXCIRI_PATH/.installer-sha" >/dev/null && info "Wrote installer sha marker /usr/share/hexciri/.installer-sha (hexciri update re-runs the installer only when this changes)" || warn "could not write installer sha marker, hexciri update will re-run the installer every time"
[ -n "${FORK_FP:-}" ] && printf '%s\n' "$FORK_FP" | sudo tee "$HEXCIRI_PATH/.fork-fingerprint" >/dev/null || true
[ -n "${UP_FP:-}" ] && printf '%s\n' "$UP_FP" | sudo tee "$HEXCIRI_PATH/.upstream-fingerprint" >/dev/null || true
[ -n "${PATCH_FP:-}" ] && printf '%s\n' "$PATCH_FP" | sudo tee "$HEXCIRI_PATH/.patch-fingerprint" >/dev/null || true
info "Installed: $HEXCIRI_PATH/shell, $HEXCIRI_PATH/default, $HEXCIRI_PATH/themes, $HEXCIRI_PATH/bin, $HEXCIRI_PATH/install (browser-policy helpers), $HEXCIRI_PATH/icons, $HEXCIRI_PATH/logo.txt, $HEXCIRI_PATH/icon.txt"

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
# these wrappers too would duplicate both. Only these two are placed: the
# other applications/*.desktop files are Omarchy web apps (ChatGPT, Herdr,
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
[ -f "$HEXCIRI_PATH/default/hypr/hexciri.lua" ] || die "missing: $HEXCIRI_PATH/default/hypr/hexciri.lua"
[ -f "$HEXCIRI_PATH/default/hypr/hexciri-compat.lua" ] || die "missing: $HEXCIRI_PATH/default/hypr/hexciri-compat.lua"
[ -f "$HEXCIRI_PATH/default/hypr/bootstrap.lua" ] || die "missing: $HEXCIRI_PATH/default/hypr/bootstrap.lua (Hyprland dofiles it first; without it Hyprland trips emergency mode with no binds)"
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
LEFTOVER_OMARCHY_CMDS="$(grep -rInE 'omarchy-[a-z0-9]+' "$HEXCIRI_PATH/default/hypr" "$HOME/.config/hypr" "$HEXCIRI_PATH/shell" "$HEXCIRI_PATH/default/hexciri" 2>/dev/null | grep -v 'omarchy:' || true)"
if [ -n "$LEFTOVER_OMARCHY_CMDS" ]; then
  warn "omarchy-* references remain in placed Hyprland Lua / shell / menu (check whether they are real commands or just comments):"
  printf '%s\n' "$LEFTOVER_OMARCHY_CMDS"
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
  for _cmd in $(grep -rIhoE 'hexciri-[a-z0-9-]+' "$HEXCIRI_PATH/default" "$HEXCIRI_PATH/shell" "$HEXCIRI_PATH/bin" "$HOME/.config/hypr" 2>/dev/null | sort -u); do
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
      info "  forked-tree command present: $_cmd"
    else
      warn "  forked tree calls $_cmd but it is not installed, expect a Command not found popup / dead bind"
    fi
  done
  unset _cmd
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
for _bin in hexciri-system hexciri-dock hexciri-dns hexciri-state hexciri-setup-git hexciri-setup-hostname hexciri-setup-keyboard hexciri-setup-input hexciri-setup-security-fingerprint hexciri-setup-security-fido2 hexciri-setup-security-sshd hexciri-setup-security-ssh-agent hexciri-sudo-passwordless hexciri-security-functions hexciri-apply-lock hexciri-pkg-add hexciri-pkg-missing hexciri-monitor-state hexciri-display-text-size hexciri-network-status hexciri-network-band hexciri-network-wifi-connected hexciri-network-captive-portal hexciri-network-password hexciri-network-qr hexciri-network-speedtest hexciri-region hexciri-font-list hexciri-font-current hexciri-font-set hexciri-show-logo hexciri-show-done hexciri-file-select hexciri-input-method hexciri-git-url-check hexciri-disk-speedtest hexciri-kernel hexciri-language hexciri-locale-session hexciri-locale-generate hexciri-refresh-shell hexciri-refresh-tmux hexciri-refresh-hyprsunset hexciri-refresh-applications hexciri-refresh-config hexciri-device-touchpad hexciri-device-touchscreen hexciri-theme-set-browser-policy hexciri-toggle hexciri-dictation hexciri-default-dictation hexciri-theme-ansi; do
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
# Dead menu rows must be gone from the forked jsonc, not just uncallable.
# NOTE 2026-11-24: '"install.' / '"remove.' must NOT be in this list.
# b0eed823 restored Install/Remove (26 install.* + 20 remove.* rows, all
# with backing bins, verified in sim6), and the broad patterns matched the
# first restored row and killed the install with
#   ERROR: dead menu row still present in hexciri-menu.jsonc: "install.
# Only the subtrees the menu audit actually drops are dead here: the
# _drop_prefix / _drop_exact sets in the menu patch above (AI, services,
# development, terminals, browsers, dictation, windows, preinstalls,
# factory-reset, fido2, sshd, sudoless-docker). Non-Zed editors are
# dropped by the menu patch too, but are covered by the action-token
# check below, not by a grep pattern (there is no grep for "not zed").
for _dead in '"install.ai.' '"install.service.' '"install.development.' '"install.terminal.' '"install.browser.' '"install.dictation.' '"install.windows"' '"install.preinstalls"' '"remove.ai.' '"remove.service.' '"remove.development.' '"remove.dictation.' '"remove.windows"' '"remove.preinstalls"' '"remove.factory-reset"' '"remove.security.fido2"' '"remove.security.sshd"' '"remove.security.sudoless-docker"' '"update.channel' '"update.omarchy"' '"system.screensaver"' '"learn.herdr-keybindings"' '"setup.default.editor.neovim"' '"setup.security.sudoless-docker"' '"appearance.unlock"'; do
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
grep -q 'already updated by eos-update --aur, skipping' "$HEXCIRI_PATH/bin/hexciri-update-aur-pkgs" && die "hexciri-update-aur-pkgs still prints the noisy skipping line"
[ -x "$HEXCIRI_PATH/bin/hexciri-pkg-aur-accessible" ] || die "hexciri-pkg-aur-accessible missing from fork (hexciri-update-aur-pkgs calls it, 2026-11-24 live log: command not found)"
grep -q 'HEXCIRI_UPDATE_REEXECED' "$HEXCIRI_PATH/bin/hexciri-update" || die "hexciri-update does not skip the second confirm on a self-update re-exec"
grep -q '_upgraded' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs does not count real upgrades (it claimed updated (1) after nothing to do)"
grep -q 'endeavouros repo not found' "$HEXCIRI_PATH/bin/hexciri-update-system-pkgs" || die "hexciri-update-system-pkgs has no endeavouros-repo check (EOS pkgs must still update via pacman)"
[ -f "$HEXCIRI_PATH/.fork-fingerprint" ] || die "fork fingerprint missing, hexciri update cannot tell if the fork changed"
[ -f "$HEXCIRI_PATH/.patch-fingerprint" ] || die "patch fingerprint missing, hexciri update cannot tell if the fork patches changed"
grep -q 'upstream_fingerprint' "$INSTALLER_DIR/install.sh" || die "installer has no fork cache (upstream_fingerprint missing)"
grep -q 'patch_fingerprint' "$INSTALLER_DIR/install.sh" || die "installer has no fork cache (patch_fingerprint missing)"
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
if ! grep -rl 'hexciri.menu' "$HEXCIRI_PATH/shell/plugins" --include='manifest.json' >/dev/null 2>&1; then
  warn "no plugin manifest registers hexciri.menu, Super+Alt+Space menu will do nothing"
fi
if ! grep -rl 'hexciri.dock' "$HEXCIRI_PATH/shell/plugins" --include='manifest.json' >/dev/null 2>&1; then
  warn "no plugin manifest registers hexciri.dock, Super+Space apps will do nothing"
fi
info "PASS: placement verified"

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
# Idempotent, best-effort: without an enrolled finger the file is left alone.
step "Configuring SDDM fingerprint (login unlock)"
if command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'; then
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
  info "No fingers enrolled, /etc/pam.d/sddm left alone (enroll one, then re-run the installer or Setup > Security > Fingerprint)"
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
[ "$_boot_found" -eq 0 ] && warn "no systemd-boot loader.conf found (/efi, /boot, /boot/efi), boot timeout unchanged (GRUB or other bootloader?)"
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
  printf '[Theme]\nCurrent=hexciri\n' > "$TMP_SDDM_THEME"
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
    if command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'; then
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
# never installed again. foot and btop were never installed by this
# installer (Kitty over Foot, bottom over btop) but were left over from the
# EndeavourOS base / an earlier install, so they are removed here too.
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
step "Trimming bloat: foot, btop, apostrophe, pandoc-cli / Haskell, ghostwriter, meld, ncspot, neovim, obsidian, pinta, xterm"
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
for _pkg in foot btop apostrophe pandoc-cli ghostwriter meld ncspot neovim obsidian pinta xterm; do
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
info "Installed: hexciri-trim-bloat + post-update hook (foot/btop/apostrophe/pandoc-cli/ghostwriter/meld/ncspot/neovim/obsidian/pinta/xterm stay removed; vim/stoken stay installed, unremovable, entries hidden)"
# First-update marker: the install itself is the first update, so mark it.
# Without this, hexciri-update-available counts every pending pacman update
# on first boot and the update icon never clears.
if [ -x "$HEXCIRI_PATH/bin/hexciri-done" ]; then
  "$HEXCIRI_PATH/bin/hexciri-done" mark first-update 2>/dev/null && info "Marked: first-update done (update icon will not count pending Arch updates)" || warn "could not mark first-update, update icon may show until the first hexciri-update"
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
command -v kitty >/dev/null 2>&1 && hc_info "  terminal: kitty present" || warn "  terminal: kitty NOT installed, terminal binds fall back to xdg-terminal-exec"
command -v udiskie >/dev/null 2>&1 && hc_info "  udiskie: present" || warn "  udiskie: NOT installed, autostart will pop a Command not found error"
if command -v brave-origin >/dev/null 2>&1; then
  hc_info "  browser: Brave Origin present (default: $(xdg-settings get default-web-browser 2>/dev/null || echo unknown))"
else
  warn "  browser: Brave Origin NOT installed, Super+Shift+Return / Super+Shift+B will fail"
fi
if command -v zathura >/dev/null 2>&1; then hc_info "  pdf: zathura present"; else warn "  pdf: zathura NOT installed"; fi
if [ -f /etc/pam.d/hexciri-lock-password ]; then hc_info "  lock PAM: /etc/pam.d/hexciri-lock-password present (System > Lock works)"; else warn "  lock PAM: missing, System > Lock returns missing-pam (run: sudo hexciri-apply-lock)"; fi
if [ -f /etc/sudoers.d/hexciri-theme-browser ]; then hc_info "  browser policy sudoers: present (theme switch repaints Brave)"; else warn "  browser policy sudoers: missing, theme switch reports hexciri-theme-set-browser failed"; fi
command -v fprintd >/dev/null 2>&1 && hc_info "  fingerprint: fprintd present (Setup > Security > Fingerprint)" || warn "  fingerprint: fprintd NOT installed, Setup > Security > Fingerprint will fail"
if command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'; then
  if grep -q 'pam_unix.so try_first_pass likeauth nullok' /etc/pam.d/sddm 2>/dev/null && grep -q pam_fprintd.so /etc/pam.d/sddm 2>/dev/null; then
    hc_info "  fingerprint: SDDM login has pam_unix first, then pam_fprintd (password alone logs in)"
  elif grep -q pam_fprintd.so /etc/pam.d/sddm 2>/dev/null; then
    warn "  fingerprint: /etc/pam.d/sddm has pam_fprintd but no pam_unix-first line (old order: fingerprint demanded after password)"
  else
    warn "  fingerprint: enrolled, but /etc/pam.d/sddm has no pam_fprintd, SDDM login stays password-only"
  fi
fi
if command -v mpv >/dev/null 2>&1; then hc_info "  video: mpv present"; else warn "  video: mpv NOT installed"; fi
if command -v gpu-screen-recorder >/dev/null 2>&1; then hc_info "  screenrecord: gpu-screen-recorder present"; else warn "  screenrecord: gpu-screen-recorder NOT installed, menu Capture > Screenrecord will fail"; fi
if command -v localsend >/dev/null 2>&1; then hc_info "  share: localsend present (localsend-bin)"; else warn "  share: localsend NOT installed, menu Share > Receive will fail (yay -S localsend-bin)"; fi
if command -v fastfetch >/dev/null 2>&1; then hc_info "  fastfetch: present"; else warn "  fastfetch: NOT installed"; fi
if [ -f /etc/fastfetch/config.jsonc ]; then hc_info "  fastfetch config: /etc/fastfetch/config.jsonc present (Hexciri config)"; elif [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then hc_info "  fastfetch config: ~/.config/fastfetch/config.jsonc present"; else warn "  fastfetch config: not placed, stock config in use"; fi
grep -q 'hexciri-launch-about --render' "$HEXCIRI_PATH/bin/hexciri-launch-about" 2>/dev/null && grep -q 'hexciri-launch-or-focus-tui --app-id=org.hexciri.about' "$HEXCIRI_PATH/bin/hexciri-launch-about" 2>/dev/null && grep -q '_about_fit' "$HEXCIRI_PATH/bin/hexciri-launch-about" 2>/dev/null && hc_info "  about: launch-about is the two-mode fastfetch (--render runs inside the terminal, no bash -c quoting trap)" || warn "  about: launch-about is not the two-mode --render script, System > About may open and close at once"
if grep -q 'icon.txt' /etc/fastfetch/config.jsonc 2>/dev/null; then hc_info "  about logo: fastfetch config logo points at icon.txt"; elif grep -q 'hexciri-nb.png' /etc/fastfetch/config.jsonc 2>/dev/null && [ -f "$HOME/.config/fastfetch/hexciri-nb.png" ]; then hc_info "  about logo: fastfetch config logo points at hexciri-nb.png (present)"; else warn "  about logo: fastfetch config logo does not point at icon.txt or hexciri-nb.png, About may render a blank logo column"; fi
if grep -q '^gtk-theme-name=Adwaita$' "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null && ! grep -q 'Adwaita-dark' "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null; then hc_info "  gtk picker: settings.ini theme=Adwaita, no Adwaita-dark (GTK4 dark comes from prefer-dark)"; else warn "  gtk picker: settings.ini still names Adwaita-dark or is missing, file picker will come up light with ghost text"; fi
if command -v dbus-run-session >/dev/null 2>&1; then _gtk_scheme_now="$(dbus-run-session -- gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo unknown)"; if [ "$_gtk_scheme_now" = "'prefer-dark'" ]; then hc_info "  gtk picker: dconf color-scheme=prefer-dark (portal dialog reads dconf on Wayland, not settings.ini)"; else warn "  gtk picker: dconf color-scheme=$_gtk_scheme_now, portal file picker may stay light (expected 'prefer-dark' for a dark theme)"; fi; unset _gtk_scheme_now; fi
[ -x /usr/lib/hexciri/speedtest ] && hc_info "  speedtest: /usr/lib/hexciri/speedtest present (Speed Test > Network works)" || warn "  speedtest: /usr/lib/hexciri/speedtest missing, Speed Test > Network will show speedtest.failed"
command -v btm >/dev/null 2>&1 && hc_info "  activity monitor: btm present (Super+Shift+T)" || warn "  activity monitor: btm NOT installed, Super+Shift+T will fail (package: bottom, binary: btm)"
_boot_hc_ok=1; _boot_hc_seen=0; for _f in /efi/loader/loader.conf /boot/loader/loader.conf /boot/efi/loader/loader.conf; do if [ -f "$_f" ]; then _boot_hc_seen=1; grep -q '^timeout 1$' "$_f" 2>/dev/null || _boot_hc_ok=0; fi; done; if [ "$_boot_hc_seen" -eq 1 ] && [ "$_boot_hc_ok" -eq 1 ]; then hc_info "  boot timeout: every loader.conf says timeout 1"; elif [ "$_boot_hc_seen" -eq 0 ]; then warn "  boot timeout: no loader.conf found (GRUB or other bootloader?)"; else warn "  boot timeout: a loader.conf does not say timeout 1 (grep timeout in /efi/loader/loader.conf /boot/loader/loader.conf /boot/efi/loader/loader.conf)"; fi; _boot_hc_efi=""; [ -r /sys/firmware/efi/efivars/LoaderConfigTimeout-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f ] && _boot_hc_efi="$(tail -c +5 /sys/firmware/efi/efivars/LoaderConfigTimeout-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f 2>/dev/null | tr -d '\0')"; if [ "$_boot_hc_efi" = "1" ]; then hc_info "  boot timeout EFI: LoaderConfigTimeout=1"; elif [ -n "$_boot_hc_efi" ]; then warn "  boot timeout EFI: LoaderConfigTimeout=$_boot_hc_efi, overrides loader.conf (run: sudo bootctl set-timeout 1)"; else hc_info "  boot timeout EFI: no LoaderConfigTimeout variable, loader.conf controls it"; fi; unset _boot_hc_ok _boot_hc_seen _boot_hc_efi _f
command -v strata >/dev/null 2>&1 || [ -x "$HOME/.local/bin/strata" ] || [ -x "$HEXCIRI_PATH/bin/strata" ] && hc_info "  file manager: strata present" || warn "  file manager: strata NOT installed, Super+Shift+F will error until it is"
command -v xdg-terminal-exec >/dev/null 2>&1 && hc_info "  xdg-terminal-exec: present" || warn "  xdg-terminal-exec: not installed, floating terminals use the xdg-terminals.list fast path only"
if command -v spotify >/dev/null 2>&1; then hc_info "  music: spotify present (Super+Shift+M)"; elif command -v spotify-launcher >/dev/null 2>&1; then hc_info "  music: spotify-launcher present (Super+Shift+M via wrapper)"; else warn "  music: Spotify NOT installed, Super+Shift+M will fail"; fi
command -v gnome-calculator >/dev/null 2>&1 && hc_info "  calculator: gnome-calculator present (Super+Shift+Q)" || warn "  calculator: gnome-calculator NOT installed, Super+Shift+Q will fail"
command -v hexciri >/dev/null 2>&1 && hc_info "  cli: hexciri present" || warn "  cli: hexciri NOT on PATH, hexciri plugin list will fail"
command -v checkupdates >/dev/null 2>&1 && hc_info "  update check: checkupdates present (update icon)" || warn "  update check: checkupdates NOT installed, update icon never shows"
command -v eos-update >/dev/null 2>&1 && hc_info "  update engine: eos-update present (repo + AUR, --aur)" || warn "  update engine: eos-update NOT installed, hexciri update falls back to pacman -Syu --noconfirm"
grep -q '^ILoveCandy' /etc/pacman.conf 2>/dev/null && hc_info "  pacman bars: ILoveCandy on (Pac-Man eating dots)" || warn "  pacman bars: ILoveCandy NOT set in /etc/pacman.conf, pacman shows the plain bar"
command -v mise >/dev/null 2>&1 && hc_info "  mise: $(mise --version 2>/dev/null || echo present)" || warn "  mise: NOT installed, Omarchy scripts that call mise will fail"
[ -f /etc/mise/conf.d/hexciri-tools.toml ] && hc_info "  mise tools: /etc/mise/conf.d/hexciri-tools.toml present (node, uv, gh, lazy; no AI agents, no Herdr)" || warn "  mise tools: /etc/mise/conf.d/hexciri-tools.toml missing"
[ -f "$HOME/.config/kitty/kitty.conf" ] && hc_info "  kitty config: ~/.config/kitty/kitty.conf present (theme include)" || warn "  kitty config: not placed, Kitty will not load theme colours"
[ -d "$HEXCIRI_PATH/default/themed" ] && hc_info "  theme templates: default/themed present" || warn "  theme templates: default/themed missing, theme-set generates nothing"
if command -v grim >/dev/null 2>&1 && command -v slurp >/dev/null 2>&1; then hc_info "  screenshot: grim + slurp present (PRINT, hexciri-capture-screenshot)"; else warn "  screenshot: grim/slurp missing, PRINT will fail"; fi
command -v tesseract >/dev/null 2>&1 && hc_info "  OCR: tesseract present (SUPER+CTRL+PRINT capture-text)" || warn "  OCR: tesseract NOT installed, capture-text will fail"
if [ "$HC_FAIL" -eq 0 ]; then
  info "Health check: clean"
else
  warn "Health check: flagged issues above, see the warnings. Reboot may still work, check the logs if it does not."
fi
unset _check

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
  16. Spotify + Arch substitutes: Super+Shift+M opens Spotify, Super+Shift+Q opens the calculator (gnome-calculator), PRINT takes a screenshot (grim + slurp, saved to ~/Pictures/Screenshots). Super+Ctrl+Return (Herdr) is deliberately unbound, herdr is an Omarchy AI-agent app not installed in v2, use Super+Alt+Return for tmux.

  17. hexciri CLI: `hexciri plugin list` works in a terminal, and `hexciri update` runs the Hexciri update (eos-update --aur for repo + AUR, Hexciri self-update syncs nyx with git (tarball fallback) and re-runs the installer when it changed, mise up for mise tools). `hexciri-update` is the same script, and `hexciri update hexciri` re-runs just the Hexciri self-update. foot, btop, apostrophe, ghostwriter, meld, ncspot, neovim, obsidian, pinta, xterm and the Haskell tree are removed and stay removed (post-update hook re-trims on every update). vim and stoken stay installed, they cannot be removed (ex-vi-compat / openconnect depend on them), their entries are hidden instead, and the trim no longer tries them. YAD settings is hidden, yad itself stays (EOS tools depend on it).

  18. Menu audit 2026-11-23: Install and Remove subtrees were deleted then (install-*/remove-* were never in the fork), restored 2026-11-24 where a backing script exists (see item 21). Update > Channel is gone (Hexciri has no channels), Update > Hexciri is back (Phase 2, 2026-11-24, runs hexciri-update in a floating terminal), System > Screensaver is gone (no screensaver binary in v2). Setup > Security > Fingerprint, Setup > Plugin options, System > Lock, System > Logout/Reboot/Shutdown, Appearance > Dock, Setup > Network > DNS, display scale and network data should all work now; the missing bins that broke them are copied. AI menu options are still out on purpose (AI agents are out of scope, Herdr stays removed; mise itself is back in, Phase 2 2026-11-24, for the non-agent tools node, uv, gh). Hide/Show Bar works (bare hexciri-toggle was missing in the sim, now copied). Setup > Defaults > Dictation rows work (no backend installed yet, pick one first). The dock pinned list is Strata, Spotify, Brave Origin, Zed, Kitty (Devi 2026-11-23); hexciri-browser / hexciri-terminal are not pinned, they are wrappers for Brave Origin / Kitty and would duplicate them.

  19. Regression fixes 2026-11-23: socat is installed now (hexciri-shell IPC was failing without it, which broke menu Apps, the bar Arch trigger, theme switching past the background, the background picker, and lock, all at once); Appearance > Icons has the stock icon sets; default terminal reports Kitty, not Foot; vim and stoken are NOT removed (ex-vi-compat / openconnect depend on them, the trim stopped trying them 2026-11-24 after the first full update printed the refusal on every run), their entries are hidden with NoDisplay instead; the app grid no longer shows Browser/Terminal wrappers next to Brave Origin/Kitty; `hexciri` works in a terminal (bare dispatcher was never linked into ~/.local/bin); About fits its window again (fastfetch config moved to /etc/fastfetch, About logo file created). Display and network plugins were working and were not touched.
  20. Remaining fixes 2026-11-23: SDDM login accepts fingerprint (pam_fprintd in /etc/pam.d/sddm, only when a finger is enrolled); Appearance > Icons lists Arcade/Original/Papercraft (vipsthumbnail, ffmpegthumbnailer, rsvg-convert installed, picker thumbnails work); Software Token (small) hidden for real (entry is stoken-gui-small.desktop, and stoken cannot be removed, openconnect depends on it); About is a floating fastfetch window now, fitted to the rendered content at launch (two-mode launch-about, --render measures logo + modules and resizes the window, no fixed 920x480); systemd-boot timeout 1s in every loader.conf AND the LoaderConfigTimeout EFI variable (bootctl set-timeout 1, the variable overrides loader.conf); Super+Shift+T runs btm (bottom package binary); LocalSend file picker is dark (theme name Adwaita in gtk-3.0/gtk-4.0 settings.ini, dconf color-scheme prefer-dark via dbus-run-session, FileChooser=gtk portal; Adwaita-dark is not a theme name); EOS update icon launches kitty --hold -e eos-update --yay (eos-update never called hexciri-update, the Terminal=true launch path was the break).

  21. Remaining fixes 2026-11-24: SDDM fingerprint is password-first now (pam_unix before the gate + pam_fprintd, so a correct password logs in at once and an empty-password Enter uses the reader; the old order demanded a fingerprint after the password, and rerunning the installer repairs a machine that already has the old order); System > About exports a UTF-8 locale for the whole About process (a C-locale session made wc/awk count multibyte glyphs as zero width, so the window came out narrower than the layout); EOS update keeps its icon (read from the EOS desktop file, endeavouros-icon, or system-software-update, instead of the invented eos-update name); Speed Test > Network measures with Hexciri's own curl client at /usr/lib/hexciri/speedtest (the Omarchy speedtest package comes from Omarchy's repo, which Hexciri does not use); Install and Remove menu entries are back (Package, AUR, Web App, TUI, Style, Gaming and their Remove counterparts, kept only where the backing script exists in the fork; AI, services, terminals, Windows, preinstalls and dictation stay out, and install-browser stays out because its helper tree is not copied).

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
  arch-updates EndeavourOS backend, Nyxiri overlay, THPM install. (hexciri-update rework done 2026-11-24: eos-update --aur + Hexciri self-update + mise.)
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
