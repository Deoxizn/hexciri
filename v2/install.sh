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
#      verify SHA from the tarball top dir, then fork and rename the shell inline
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
#   Theme engine merge, arch-updates EndeavourOS backend, hexciri-update rework
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
for _a in "$@"; do
  case "$_a" in
    --yes|-y) UPDATE_YES="--yes" ;;
    --reboot) AUTO_REBOOT=1 ;;
    -h|--help) echo "usage: install.sh [--yes] [--reboot]"; exit 0 ;;
    *) printf 'install.sh: unknown arg: %s (usage: install.sh [--yes] [--reboot])\n' "$_a" >&2; exit 1 ;;
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
info() { printf '[hexciri] %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

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
sudo pacman -Sy --noconfirm

# --- Kernel headers helper (needed for dkms Nvidia drivers) ---

install_kernel_headers() {
  local kernel
  kernel="$(uname -r)"
  echo "Running kernel: $kernel"
  if [[ "$kernel" == *lts* ]]; then
    sudo pacman -S --needed --noconfirm linux-lts-headers
  else
    sudo pacman -S --needed --noconfirm linux-headers
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
  pamixer brightnessctl jq bc curl wget git base-devel pacman-contrib # checkupdates, for hexciri-update-available (update icon)
  imagemagick inotify-tools grim slurp wl-clipboard hyprpicker hyprsunset ffmpeg unzip
  ripgrep fd fzf eza bat starship zoxide fastfetch
  # NOTE 2026-11-23: no btop here, v1 removes it, bottom (in APP_PKGS below)
  # is the Hexciri system monitor instead. fastfetch's Hexciri config is
  # placed in the default apps step below (config/fastfetch/config.jsonc).
  python python-gobject lua51 luarocks
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

sudo pacman -S --needed --noconfirm "${CORE_PKGS[@]}"

# xdg-terminal-exec is NOT in stable extra and NOT in the AUR (only
# extra-testing 0.14.4-1), so it must never go in the pacman CORE_PKGS call
# above, and yay -S xdg-terminal-exec can never succeed: do not try it.
# launch-terminal's fast path (xdg-terminals.list, kitty first) works
# without it, and the binary is usually already present on EndeavourOS.
# If it is missing, enable extra-testing and install it from there; until
# then floating/presentation terminals fall back to the fast path.
if ! command -v xdg-terminal-exec >/dev/null 2>&1; then
  warn "xdg-terminal-exec not installed (only in Arch extra-testing, not AUR), terminal launches use the xdg-terminals.list fast path only. Install later from extra-testing if a floating terminal needs it."
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
#   cliamp (Music TUI, SUPER+SHIFT+ALT+M) -> ncspot (Spotify TUI).
#   omawrite (SUPER+SHIFT+W) -> ghostwriter (writing app, Qt6, no Haskell).
#   herdr (SUPER+CTRL+RETURN, Omarchy AI-agent terminal) -> bind removed,
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
  # Bind/menu-called: neovim (Super+Shift+N, launch-editor falls back to
  # nvim), tmux (Super+Alt+Return), obsidian (Super+Shift+O),
  # gpu-screen-recorder + wf-recorder fallback (menu Capture > Screenrecord),
  # zbar (capture-qr decodes with zbarimg), localsend is AUR localsend-bin (own step below, menu Share > Receive),
  # mpv (v1 default video player), zathura + plugins (v1 PDF pick),
  # imv (v1 image viewer pick), zed (v1 editor pick), playerctl (v1 layer
  # need, media keys), bottom (v1 pick, replaces btop), seahorse (keyring
  # GUI), fwupd (menu Update > Firmware), adw-gtk-theme (v1 layer need, GTK
  # apps unthemed without it), tesseract-data-eng (OCR data) + tesseract
  # itself (capture-text OCR, SUPER+CTRL+PRINT, needs the binary, it was
  # NOT in CORE_PKGS despite an old comment saying so), cliphist (v1 want), libqalculate
  # (v1 want, ships the qalc CLI), libreoffice-fresh + pinta +
  # gnome-disk-utility (Omarchy default apps), lazygit, yt-dlp, gvfs
  # (file-manager trash/network backends), qrencode, eject (XF86Eject bind).
  # Arch substitutes for Omarchy-repo-only apps (2026-11-23, Devi: most
  # Omarchy apps can just substitute with Arch defaults/alternatives, do
  # NOT try to install the Omarchy-repo-only ones): gnome-calculator for
  # omacalc (SUPER+SHIFT+Q, XF86Calculator), ncspot for cliamp (Music TUI,
  # SUPER+SHIFT+ALT+M, a Spotify TUI, Arch extra), ghostwriter for omawrite
  # (SUPER+SHIFT+W, a writing app, Arch extra). Screenshot (omasnap) is
  # substituted in the fork patch step below: hexciri-capture-screenshot is
  # rewritten to grim + slurp, both already in CORE_PKGS. Spotify is NOT
  # here, it is AUR (yay -S spotify) in its own step below.
  neovim tmux obsidian gpu-screen-recorder wf-recorder
  mpv zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb
  zed playerctl bottom seahorse fwupd adw-gtk-theme tesseract tesseract-data-eng
  cliphist libqalculate libreoffice-fresh pinta gnome-disk-utility
  lazygit yt-dlp gvfs zbar qrencode imv eject
  gnome-calculator ncspot ghostwriter
)
if ! sudo pacman -S --needed --noconfirm "${APP_PKGS[@]}"; then
  warn "Bulk default-apps install failed, retrying per package (best-effort)."
  for _pkg in "${APP_PKGS[@]}"; do
    if sudo pacman -S --needed --noconfirm "$_pkg" 2>/dev/null; then
      info "  installed: $_pkg"
    else
      warn "  NOT installed: $_pkg (install by hand: sudo pacman -S $_pkg)"
    fi
  done
  unset _pkg
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
# patch step below repoints at ncspot. Super+Shift+M = Spotify is Devi's
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
# zathura, images imv, editor zed (neovim fallback). Files (Strata) is
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
  printf '%s' "brave-origin" > "$HOME/.local/state/hexciri/defaults/browser"
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
  printf '%s' "zathura" > "$HOME/.local/state/hexciri/defaults/pdf"
  xdg-mime default org.pwmt.zathura.desktop application/pdf application/epub+zip application/postscript image/vnd.djvu 2>/dev/null || warn "xdg-mime could not pin zathura for documents"
  info "Default PDF reader: zathura"
fi
if command -v zeditor >/dev/null 2>&1; then
  printf '%s' "zeditor" > "$HOME/.local/state/hexciri/defaults/editor"
  info "Default editor: zed (zeditor)"
elif command -v zed >/dev/null 2>&1; then
  printf '%s' "zed" > "$HOME/.local/state/hexciri/defaults/editor"
  info "Default editor: zed"
elif command -v nvim >/dev/null 2>&1; then
  printf '%s' "nvim" > "$HOME/.local/state/hexciri/defaults/editor"
  info "Default editor: neovim (zed not installed)"
fi
if command -v imv >/dev/null 2>&1; then
  printf '%s' "imv" > "$HOME/.local/state/hexciri/defaults/images"
  info "Default image viewer: imv"
fi

# --- fastfetch config (Hexciri's, from the repo tree) ---
# fastfetch itself is already in CORE_PKGS above (Arch extra). Its config
# lives in v1 at config/fastfetch/config.jsonc, and its logo at
# branding/hexciri-nb.png, both present on nyx. Place both under
# ~/.config/fastfetch/ so `fastfetch` shows Hexciri's layout, not the stock
# one. Best-effort, never fatal: a missing config still leaves a working
# fastfetch. An existing config is backed up first, like place_user_file
# does for the Hyprland templates below.
mkdir -p "$HOME/.config/fastfetch"
if [ -f "$HEXCIRI_REPO_ROOT/config/fastfetch/config.jsonc" ]; then
  if [ -f "$HOME/.config/fastfetch/config.jsonc" ] && ! cmp -s "$HEXCIRI_REPO_ROOT/config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"; then
    cp -a "$HOME/.config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc.hexciri.bak"
    info "Backed up existing ~/.config/fastfetch/config.jsonc to config.jsonc.hexciri.bak"
  fi
  cp -a "$HEXCIRI_REPO_ROOT/config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
  info "Placed: ~/.config/fastfetch/config.jsonc (Hexciri fastfetch config)"
else
  warn "config/fastfetch/config.jsonc not found in the installer tree, fastfetch keeps its stock config."
fi
if [ -f "$HEXCIRI_REPO_ROOT/branding/hexciri-nb.png" ]; then
  cp -a "$HEXCIRI_REPO_ROOT/branding/hexciri-nb.png" "$HOME/.config/fastfetch/hexciri-nb.png"
  info "Placed: ~/.config/fastfetch/hexciri-nb.png (fastfetch logo)"
else
  warn "branding/hexciri-nb.png not found in the installer tree, fastfetch logo will be missing (the config references it)."
fi

# --- Quickshell ---

step "Installing Quickshell from Arch extra (stock first, NOT quickshell-git by default)"
if sudo pacman -S --needed --noconfirm quickshell; then
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
  sudo pacman -S --needed --noconfirm mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon amd-ucode linux-firmware
fi

if [ "$HAS_NVIDIA" -eq 1 ]; then
  if echo "$GPU_INFO" | grep -qiE 'RTX|GTX 16|GTX 20|GTX 30|GTX 40'; then
    step "Nvidia Turing or newer detected (RTX 4080 Super path). Installing nvidia-open."
    install_kernel_headers
    sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  elif echo "$GPU_INFO" | grep -qiE 'GTX 10'; then
    step "Nvidia Pascal detected (GTX 1080 Ti, 10xx path). Installing nvidia-580xx from AUR."
    warn "Pascal is legacy. nvidia-580xx is the legacy branch, end of support is coming. Do NOT install nvidia-open on this card."
    install_kernel_headers
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils
  else
    warn "Nvidia GPU found but model not matched as Turing+ or Pascal 10xx. Check lspci output above."
    warn "Defaulting to nvidia-open. If this is a Pascal 10xx card, remove nvidia-open and install nvidia-580xx-dkms and nvidia-580xx-utils from AUR instead."
    install_kernel_headers
    sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  fi
fi

if [ "$HAS_AMD" -eq 0 ] && [ "$HAS_NVIDIA" -eq 0 ] && [ -n "$GPU_INFO" ]; then
  step "No AMD or Nvidia GPU matched. Installing generic Intel Mesa stack."
  sudo pacman -S --needed --noconfirm mesa vulkan-intel lib32-mesa lib32-vulkan-intel
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
cat /usr/share/wayland-sessions/hexciri.desktop

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
systemctl is-enabled NetworkManager bluetooth power-profiles-daemon firewalld sddm || warn "One or more services above did not report enabled. Check systemctl status for that service."

# --- Download Omarchy at the pinned commit as a tarball, no git, no auth ---

step "Downloading Omarchy, branch $PINNED_BRANCH, pinned commit $PINNED_SHA ($PINNED_DATE)"
step "No git clone, no username or password prompt: public codeload tarball via curl"
for cmd in curl python3 tar grep find cp mkdir rm; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done
OMARCHY_TARBALL="$TMP_WORK/omarchy.tar.gz"
info "Omarchy tarball is about 94 MB, this can take a minute on a slow connection"
curl --progress-bar -fSL --max-time 300 -o "$OMARCHY_TARBALL" "$OMARCHY_TARBALL_URL" || die "curl download of omacom/omarchy tarball failed. Fix networking, then rerun."
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

# --- Fork and rename, inline (was fork-shell.sh) ---
# Phase 1 only: extract the listed subsets verbatim, then rename. No Phase 2 Hexciri edits.
# Stock Lua only. Lua double backslashes are preserved byte-safe:
# a regex dot is \\. in Lua, and this script never collapses \\ to \.
# It uses Python byte replacement, not sed, for content rewrites.

copy_subset() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    info "Copied: $label ($src -> $dest)"
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
    info "Copied: $label ($src -> $dest)"
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
    info "Copied: $label ($src -> $dest)"
    return 0
  fi
  return 1
}

is_allowed_bin() {
  local name="$1"
  case "$name" in
    launch-shell | omarchy | done | restart-* | theme-set | theme-set-templates | plugin-add | plugin-catalog | plugin-clone | plugin-disable | plugin-enable | plugin-list | plugin-remove | plugin-update | plugin-validate | bar | bar-text-color | shell | shell-config | migrate | migrate-notify | hook | hook-install | \
      refresh-hyprland | hyprland-reload-guard | notification-send | menu | menu-clipboard | menu-emoji | menu-emoji-insert | menu-file | menu-herdr-keybindings | menu-images | menu-input | menu-keybindings | menu-plugin | menu-region-formats | menu-select | menu-share | menu-timezone | menu-tmux-keybindings | \
      provision-user | provision-first-run | provision-hardware | provision-owner | reinstall-configs | reinstall | reinstall-pkgs | version | version-branch | version-channel | version-pkgs | update | update-* | launch-* | \
      cmd-* | default-terminal | action | i18n | notification-wait | software-rendering | toggle-enabled | hyprland-toggle-enabled | hyprland-software-rendering | hw-software-rendering | powerprofiles-init | powerprofiles-set | powerprofiles-floor | powerprofiles-list | hyprland-monitor-watch | hyprland-monitor-clamshell | hyprland-monitor-modeless | hyprland-monitor-external-active | hyprland-monitor-identity | hyprland-monitor-internal | hyprland-monitor-internal-mirror | hyprland-monitor-laptop | hyprland-workspace-layout-current | hyprland-workspace-layout-toggle | hyprland-workspace-layout-default | hw-laptop | hw-clamshell | hw-external-monitors | system-lid-inhibit | restart-hyprctl | \
      capture-* | system-* | hyprland-* | notification-* | toggle-* | icons-* | hw-* | region-* | hibernation-* | sleep-* | audio-* | battery-* | bluetooth-* | brightness-* | clipboard-* | branding-* | default-* | theme-* | agent | agent-* | pkg-present | cmd-present | reminder | transcode | osd)
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
      # disabled checks), reminder, transcode, osd. Deliberately still NOT
      # included: install-*, remove-*, channel-*, mirror-*, keyring-*,
      # upgrade-* (app installers and Omarchy repo machinery, out of the
      # shell-only Phase 1 scope). Menu install/remove rows will fail if
      # clicked, that is intended; their when/disabled checks use
      # pkg-present, which IS included, so they still read as not installed.
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
      dest_name="hexciri-$stripped"
      cp -a "$src_file" "$FORK_OUT/bin/$dest_name"
      copied_bin=$((copied_bin + 1))
      info "Copied bin: $base -> bin/$dest_name"
    else
      skipped_bin=$((skipped_bin + 1))
      info "Skipped bin (not called by shell): $base"
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
  python3 - "$FORK_OUT" <<'PY'
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
  info "File and directory rename complete"
}

rewrite_contents() {
  step "Rewriting contents with rename map (Python byte replacement, Lua safe)"
  info "Lua safety: replacements are exact byte matches only, so \\\\ in Lua stays \\\\ and is never collapsed to \\"
  python3 - "$FORK_OUT" <<'PY'
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
    # Generic hyphen rule: autostart.lua calls omarchy-hyprland-monitor-watch,
    # omarchy-powerprofiles-init, omarchy-hyprland-software-rendering and
    # omarchy-provision-first-run, and none of those matched any rule above
    # (they are not omarchy-shell/-menu/-launch-/-theme-set), so they survived
    # the rename while bin/ renamed them to hexciri-*, and uwsm-app reported
    # "Command not found" at login. Safe where a bare omarchy catch-all is
    # not: Lua identifiers cannot contain hyphens, so _G.omarchy_default_bindings
    # and table keys like value.omarchy are untouched by this rule.
    (b"omarchy-", b"hexciri-"),
    # File manager: Devi's default is Strata (GitHub release, installed by
    # bin/hexciri-strata-install), not Omarchy's Folio. Targeted to the
    # uwsm-app invocation only: window-class rules in windows.lua/system.lua
    # match the class name, and Strata's app ID was not verified, so a global
    # folio -> strata rename would break those rules.
    (b"-- folio", b"-- strata"),
    # Terminal: Devi chose Kitty over Omarchy's default Foot. The terminals
    # list (default/xdg-terminal-exec/hyprland-xdg-terminals.list) names
    # foot.desktop; rename it so launch-terminal's fast path opens Kitty.
    (b"foot.desktop", b"kitty.desktop"),
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
    # internal namespace, not a file, path, or CLI name.
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
print("Content rewrite: %d files scanned, %d files changed" % (total_files, changed_files))
PY
  info "Content rewrite complete"
  info "Renames applied: /usr/share/omarchy -> /usr/share/hexciri, ~/.config/omarchy -> ~/.config/hexciri, ~/.local/state/omarchy -> ~/.local/state/hexciri, ~/.local/share/omarchy -> ~/.local/share/hexciri, OMARCHY_PATH -> HEXCIRI_PATH, omarchy.bar etc -> hexciri.bar etc, omarchy-shell -> hexciri-shell, omarchy-theme-set -> hexciri-theme-set, omarchy-launch-* -> hexciri-launch-*, default/hypr/omarchy.lua -> default/hypr/hexciri.lua, config/hypr/hyprland.lua env fallback updated by the same map, omarchy-* commands -> hexciri-* (generic hyphen rule), folio -> strata (launch-files only), foot.desktop -> kitty.desktop, menu trigger Omarchy logo glyph -> Arch Nerd Font glyph U+F303"
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
info "Fork output: $FORK_OUT"
info "Files: $(find "$FORK_OUT" -type f | wc -l | tr -d ' '), dirs: $(find "$FORK_OUT" -type d | wc -l | tr -d ' '), themes: $(find "$FORK_OUT/themes" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '), bin scripts: $(find "$FORK_OUT/bin" -type f 2>/dev/null | wc -l | tr -d ' ')"
find "$FORK_OUT" -mindepth 1 -maxdepth 2 -print | sort

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
# 2. Omarchy-repo-only apps are substituted with Arch defaults, per Devi
#    2026-11-23 ("most omarchy apps we can just substitute with arch
#    defaults/alternatives"), instead of leaving dead binds:
#      omacalc -> gnome-calculator, cliamp -> ncspot, omawrite -> ghostwriter,
#      herdr bind removed (AI agent, out of v2 scope; tmux is on
#      Super+Alt+Return), omasnap -> grim + slurp in the capture script.
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

# 3. Music TUI: cliamp (Omarchy-repo-only) -> ncspot (Arch extra, Spotify TUI).
if '{ tui = "cliamp", focus = true }' in s:
    s = s.replace('{ tui = "cliamp", focus = true }', '{ tui = "ncspot", focus = true }')
    changed.append("cliamp -> ncspot (Super+Shift+Alt+M Music TUI)")

# 4. Writing app: omawrite (Omarchy-repo-only) -> ghostwriter (Arch extra, Qt6, no pandoc/Haskell).
old_write = 'o.bind("SUPER + SHIFT + W", "Omawrite", { launch = "omawrite" })'
new_write = 'o.bind("SUPER + SHIFT + W", "Writing (Ghostwriter)", { launch = "ghostwriter", focus = "^ghostwriter$" })'
if old_write in s:
    s = s.replace(old_write, new_write)
    changed.append("omawrite -> ghostwriter (Super+Shift+W)")

# 5. Herdr: Omarchy AI-agent terminal, not installed in v2 (AI agents are
# out of scope). Remove the bind instead of leaving a terminal that errors
# with "herdr: command not found". Tmux is already on Super+Alt+Return.
old_herdr = '  o.bind("SUPER + CTRL + RETURN", "Herdr", { omarchy = "terminal-herdr" })'
if old_herdr in s:
    s = s.replace(old_herdr, '  -- Hexciri: Herdr bind removed, herdr is an Omarchy AI-agent app not installed in v2, use Super+Alt+Return for tmux.')
    changed.append("Herdr bind removed (AI agent, out of v2 scope)")

# 5b. Activity TUI: btop (removed, v1 stock removal, never installed) ->
# bottom (Arch extra, the Hexciri monitor). The old bind opened a terminal
# that errored with "btop: command not found".
utils = root + "/default/hypr/bindings/utilities.lua"
with open(utils) as f:
    u = f.read()
u_orig = u
if '{ tui = "btop" }' in u:
    u = u.replace('{ tui = "btop" }', '{ tui = "bottom" }')
    changed.append("btop -> bottom (Super+Shift+T Activity TUI)")
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
info "Bind patch done: Super+Space apps / Super+Alt+Space menu swap, Super+Shift+M Spotify, gnome-calculator, ncspot, ghostwriter, bottom, Herdr removed, screenshot via grim+slurp, touchpad bottom-right = right click"

# --- Place the forked tree to its install targets ---
# sudo is used ONLY for the /usr/share and /etc steps below. Everything else
# runs as the normal user.

step "Placing forked tree: /usr/share/hexciri (sudo), ~/.config, ~/.local/state"

sudo rm -rf "$HEXCIRI_PATH"
sudo mkdir -p "$HEXCIRI_PATH"
sudo cp -a "$FORK_OUT/shell" "$FORK_OUT/default" "$FORK_OUT/themes" "$FORK_OUT/bin" "$HEXCIRI_PATH/"
sudo chmod +x "$HEXCIRI_PATH"/bin/* 2>/dev/null || true
info "Installed: $HEXCIRI_PATH/shell, $HEXCIRI_PATH/default, $HEXCIRI_PATH/themes, $HEXCIRI_PATH/bin"

mkdir -p "$HOME/.config/hypr" "$HOME/.config/hexciri" \
  "$HOME/.local/state/hexciri/current" "$HOME/.local/state/hexciri/toggles/hypr" \
  "$HOME/.local/state/hexciri/migrations" "$HOME/.local/share/hexciri" \
  "$HOME/.config/hexciri/plugins" "$HOME/.config/hexciri/themes" "$HOME/.config/hexciri/hooks" \
  "$HOME/.local/bin"

place_user_file() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp -a "$dest" "$dest.hexciri.bak"
    info "Backed up existing $dest to $dest.hexciri.bak"
  fi
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

# hexciri CLI on PATH everywhere, not just login shells: /usr/local/bin is
# on the default PATH for login and non-login shells alike, and Kitty runs
# bash non-login, so profile.d alone left `hexciri plugin list` as
# "command not found" in a terminal. Also append ~/.local/bin and
# /usr/share/hexciri/bin to the interactive shell rc files, so the
# hexciri-* symlinks work there too.
if [ -x "$HEXCIRI_PATH/bin/hexciri" ]; then
  sudo ln -sf "$HEXCIRI_PATH/bin/hexciri" /usr/local/bin/hexciri 2>/dev/null && info "Linked: /usr/local/bin/hexciri" || warn "could not link /usr/local/bin/hexciri, hexciri CLI needs ~/.local/bin on PATH"
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
  cp -a "$HEXCIRI_PATH/default/xdg-terminal-exec/hyprland-xdg-terminals.list" "$HOME/.config/xdg-terminal-exec/hyprland-xdg-terminals.list"
  cp -a "$HEXCIRI_PATH/default/xdg-terminal-exec/hyprland-xdg-terminals.list" "$HOME/.config/xdg-terminals.list"
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
  place_user_file "$FORK_OUT/config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  if grep -q '^# font_family' "$HOME/.config/kitty/kitty.conf"; then
    sed -i 's/^# font_family .*/font_family JetBrainsMono Nerd Font/' "$HOME/.config/kitty/kitty.conf"
  elif ! grep -q '^font_family' "$HOME/.config/kitty/kitty.conf"; then
    printf 'font_family JetBrainsMono Nerd Font\n' >> "$HOME/.config/kitty/kitty.conf"
  fi
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
  printf 'PATH=/usr/share/hexciri/bin:%s/.local/bin:%s\n' "$HOME" "$PATH"
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
# remove-* are also excluded: those menu rows are out of the shell-only
# scope and are expected to fail if clicked.
if [ -d "$HEXCIRI_PATH" ]; then
  for _cmd in $(grep -rIhoE 'hexciri-[a-z0-9-]+' "$HEXCIRI_PATH/default" "$HEXCIRI_PATH/shell" "$HEXCIRI_PATH/bin" "$HOME/.config/hypr" 2>/dev/null | sort -u); do
    case "$_cmd" in
      hexciri-install-* | hexciri-remove-* | hexciri-channel-* | hexciri-mirror-* | hexciri-keyring-* | hexciri-upgrade-*) continue ;;
      hexciri-compat) continue ;;
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

# Menu / dock / terminal / file manager essentials: Super+Space, Super+Alt+Space,
# Super+Return and Super+Shift+F all go through these.
for _bin in hexciri hexciri-menu hexciri-shell hexciri-launch-terminal hexciri-launch-files hexciri-launch-files-cwd hexciri-done hexciri-restart-terminal hexciri-update-available; do
  [ -x "$HEXCIRI_PATH/bin/$_bin" ] || die "missing bin (Super+Space apps / Super+Alt+Space menu / update will fail): $_bin"
done
unset _bin
[ -f "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" ] || die "missing: default/hexciri/hexciri-menu.jsonc, Super+Alt+Space menu has no routes"
if ! grep -rl 'hexciri.menu' "$HEXCIRI_PATH/shell/plugins" --include='manifest.json' >/dev/null 2>&1; then
  warn "no plugin manifest registers hexciri.menu, Super+Alt+Space menu will do nothing"
fi
if ! grep -rl 'hexciri.dock' "$HEXCIRI_PATH/shell/plugins" --include='manifest.json' >/dev/null 2>&1; then
  warn "no plugin manifest registers hexciri.dock, Super+Space apps will do nothing"
fi
info "PASS: placement verified"

# --- Apply a default theme, like v1 does its theme sync ---
# v1 finishes with a theme applied, not just themes installed. Pick the
# first theme dir, so no theme name is guessed. Best-effort, never fatal:
# if theme-set cannot run before a login, the stock bar still starts and
# the user can set a theme after reboot.

step "Applying a default theme"
THEME_DIRS=("$HEXCIRI_PATH"/themes/*/)
if [ "${#THEME_DIRS[@]}" -ge 1 ] && [ -d "${THEME_DIRS[0]}" ]; then
  DEFAULT_THEME="$(basename "${THEME_DIRS[0]}")"
  info "Default theme: $DEFAULT_THEME"
  if [ -x "$HEXCIRI_PATH/bin/hexciri-theme-set" ]; then
    if "$HEXCIRI_PATH/bin/hexciri-theme-set" "$DEFAULT_THEME"; then
      info "Theme applied: $DEFAULT_THEME"
    else
      warn "hexciri-theme-set $DEFAULT_THEME failed, not fatal. Set a theme after reboot: hexciri-theme-set <theme>"
    fi
  else
    warn "hexciri-theme-set not found, skipping theme apply. Set a theme after reboot."
  fi
else
  warn "No themes found to apply, skipping theme apply."
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
  for _colors in "$HOME/.local/state/hexciri/current/theme/colors.toml" "$HEXCIRI_PATH/themes/${DEFAULT_THEME:-}/colors.toml"; do
    if [ -f "$_colors" ]; then
      SDDM_BG="$(grep -m1 -E '^[[:space:]]*background[[:space:]]*=' "$_colors" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || true)"
      [ -n "$SDDM_BG" ] && break
    fi
  done
  unset _colors
  if [[ "$SDDM_BG" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    TMP_SDDM_CONF="$(mktemp)"
    printf '[General]\nBackground=%s\n' "$SDDM_BG" > "$TMP_SDDM_CONF"
    if sudo install -Dm644 "$TMP_SDDM_CONF" /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null; then
      info "SDDM theme background set to the ${DEFAULT_THEME:-current} theme background: $SDDM_BG"
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
    printf '%s' "strata" > "$HOME/.local/state/hexciri/defaults/files"
    xdg-mime default io.github.lgse.Strata.desktop inode/directory 2>/dev/null && info "Default file manager: Strata" || warn "xdg-mime could not pin Strata for inode/directory"
  fi
else
  warn "strata binary not found at ~/.local/bin/strata after install step, Super+Shift+F will error until it is installed"
fi

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
# packages; apostrophe is replaced by ghostwriter (Qt6, no pandoc), so the
# tree is removed here and never installed again (apostrophe is out of
# APP_PKGS, ghostwriter is in). foot and btop were never installed by this
# installer (Kitty over Foot, bottom over btop) but were left over from the
# EndeavourOS base / an earlier install, so they are removed here too.
# Reinstall is prevented three ways: the packages are out of every list
# (CORE_PKGS / APP_PKGS here, v2/hexciri-base.packages), this step removes
# them if present, and a post-update hook (below) re-runs the trim on every
# hexciri-update, so a future -Syu that would pull one back as a dependency
# gets it removed again right after. pacman -Syu itself never installs new
# packages, so the hook is the backstop, not the mechanism.
step "Trimming bloat: foot, btop, apostrophe, pandoc-cli / Haskell"
cat > "$HOME/.local/bin/hexciri-trim-bloat" <<'TRIM_EOF'
#!/bin/bash
# Hexciri 2.0: remove packages Devi does not want, best-effort, idempotent.
# Runs at install time and from the post-update hook, so an update can never
# leave them installed again. pacman -Rns refuses if something still depends
# on a package, so a removal here is always safe. sudo -n never prompts.
for _pkg in foot btop apostrophe pandoc-cli; do
  if pacman -Q "$_pkg" >/dev/null 2>&1; then
    if sudo -n pacman -Rns --noconfirm "$_pkg" 2>/dev/null; then
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
    sudo -n pacman -Rns --noconfirm $_hs 2>/dev/null && echo "trim-bloat: removed orphaned Haskell packages" || echo "trim-bloat: Haskell orphan removal refused" >&2
  fi
  unset _hs
fi
unset _orphans
TRIM_EOF
chmod +x "$HOME/.local/bin/hexciri-trim-bloat"
sudo ln -sf "$HOME/.local/bin/hexciri-trim-bloat" "$HEXCIRI_PATH/bin/hexciri-trim-bloat" 2>/dev/null || warn "could not link hexciri-trim-bloat into $HEXCIRI_PATH/bin"
"$HOME/.local/bin/hexciri-trim-bloat" || warn "trim-bloat run failed, not fatal"
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
info "Installed: hexciri-trim-bloat + post-update hook (foot/btop/apostrophe/pandoc-cli stay removed)"
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
if command -v systemctl >/dev/null 2>&1; then
  FAILED_UNITS="$(systemctl --failed --no-legend 2>/dev/null || true)"
  if [ -z "$FAILED_UNITS" ]; then
    info "  systemd: no failed units"
  else
    warn "  systemd: FAILED units present:"
    printf '%s\n' "$FAILED_UNITS"
    HC_FAIL=1
  fi
fi
for _check in "$HEXCIRI_PATH/bin/hexciri-launch-shell" "$HEXCIRI_PATH/bin/hexciri-menu" "$HEXCIRI_PATH/bin/hexciri-shell" "$HEXCIRI_PATH/shell/shell.qml" "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hexciri/shell.json" /usr/share/wayland-sessions/hexciri.desktop; do
  if [ -e "$_check" ]; then
    info "  present: $_check"
  else
    warn "  MISSING: $_check"
    HC_FAIL=1
  fi
done
if command -v quickshell >/dev/null 2>&1; then
  if quickshell --version >/dev/null 2>&1; then
    QS_VER="$(quickshell --version 2>/dev/null || true)"
    info "  quickshell: $QS_VER"
  else
    warn "  quickshell binary exists but --version failed"
    HC_FAIL=1
  fi
else
  warn "  quickshell binary not found"
  HC_FAIL=1
fi
if systemctl is-enabled --quiet sddm 2>/dev/null; then
  info "  sddm: enabled"
else
  warn "  sddm: not enabled"
  HC_FAIL=1
fi
if [ -f /usr/share/sddm/themes/hexciri/Main.qml ]; then
  info "  sddm theme: /usr/share/sddm/themes/hexciri (Main.qml present)"
else
  warn "  sddm theme: hexciri theme not installed, SDDM uses its default theme (cosmetic only, login still works)"
fi
command -v kitty >/dev/null 2>&1 && info "  terminal: kitty present" || warn "  terminal: kitty NOT installed, terminal binds fall back to xdg-terminal-exec"
command -v udiskie >/dev/null 2>&1 && info "  udiskie: present" || warn "  udiskie: NOT installed, autostart will pop a Command not found error"
if command -v brave-origin >/dev/null 2>&1; then
  info "  browser: Brave Origin present (default: $(xdg-settings get default-web-browser 2>/dev/null || echo unknown))"
else
  warn "  browser: Brave Origin NOT installed, Super+Shift+Return / Super+Shift+B will fail"
fi
if command -v zathura >/dev/null 2>&1; then info "  pdf: zathura present"; else warn "  pdf: zathura NOT installed"; fi
if command -v obsidian >/dev/null 2>&1; then info "  notes: obsidian present"; else warn "  notes: obsidian NOT installed, Super+Shift+O will fail"; fi
if command -v mpv >/dev/null 2>&1; then info "  video: mpv present"; else warn "  video: mpv NOT installed"; fi
if command -v gpu-screen-recorder >/dev/null 2>&1; then info "  screenrecord: gpu-screen-recorder present"; else warn "  screenrecord: gpu-screen-recorder NOT installed, menu Capture > Screenrecord will fail"; fi
if command -v localsend >/dev/null 2>&1; then info "  share: localsend present (localsend-bin)"; else warn "  share: localsend NOT installed, menu Share > Receive will fail (yay -S localsend-bin)"; fi
if command -v fastfetch >/dev/null 2>&1; then info "  fastfetch: present"; else warn "  fastfetch: NOT installed"; fi
if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then info "  fastfetch config: ~/.config/fastfetch/config.jsonc present"; else warn "  fastfetch config: not placed, stock config in use"; fi
command -v strata >/dev/null 2>&1 || [ -x "$HOME/.local/bin/strata" ] || [ -x "$HEXCIRI_PATH/bin/strata" ] && info "  file manager: strata present" || warn "  file manager: strata NOT installed, Super+Shift+F will error until it is"
command -v xdg-terminal-exec >/dev/null 2>&1 && info "  xdg-terminal-exec: present" || warn "  xdg-terminal-exec: not installed, floating terminals use the xdg-terminals.list fast path only"
if command -v spotify >/dev/null 2>&1; then info "  music: spotify present (Super+Shift+M)"; elif command -v spotify-launcher >/dev/null 2>&1; then info "  music: spotify-launcher present (Super+Shift+M via wrapper)"; else warn "  music: Spotify NOT installed, Super+Shift+M will fail"; fi
command -v gnome-calculator >/dev/null 2>&1 && info "  calculator: gnome-calculator present (Super+Shift+Q)" || warn "  calculator: gnome-calculator NOT installed, Super+Shift+Q will fail"
command -v ncspot >/dev/null 2>&1 && info "  music TUI: ncspot present (Super+Shift+Alt+M)" || warn "  music TUI: ncspot NOT installed, Super+Shift+Alt+M will fail"
command -v ghostwriter >/dev/null 2>&1 && info "  writing: ghostwriter present (Super+Shift+W)" || warn "  writing: ghostwriter NOT installed, Super+Shift+W will fail"
command -v hexciri >/dev/null 2>&1 && info "  cli: hexciri present" || warn "  cli: hexciri NOT on PATH, hexciri plugin list will fail"
command -v checkupdates >/dev/null 2>&1 && info "  update check: checkupdates present (update icon)" || warn "  update check: checkupdates NOT installed, update icon never shows"
[ -f "$HOME/.config/kitty/kitty.conf" ] && info "  kitty config: ~/.config/kitty/kitty.conf present (theme include)" || warn "  kitty config: not placed, Kitty will not load theme colours"
[ -d "$HEXCIRI_PATH/default/themed" ] && info "  theme templates: default/themed present" || warn "  theme templates: default/themed missing, theme-set generates nothing"
if command -v grim >/dev/null 2>&1 && command -v slurp >/dev/null 2>&1; then info "  screenshot: grim + slurp present (PRINT, hexciri-capture-screenshot)"; else warn "  screenshot: grim/slurp missing, PRINT will fail"; fi
command -v tesseract >/dev/null 2>&1 && info "  OCR: tesseract present (SUPER+CTRL+PRINT capture-text)" || warn "  OCR: tesseract NOT installed, capture-text will fail"
if [ "$HC_FAIL" -eq 0 ]; then
  info "Health check: clean"
else
  warn "Health check: flagged issues above, see the warnings. Reboot may still work, check the logs if it does not."
fi
unset _check

# --- Final checklist ---

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
  10. Apps / menu: Super+Space opens the apps (dock apps), Super+Alt+Space opens the menu (Arch logo at the bar's left end). These now go through Hyprland global shortcuts (default/hexciri/shortcuts), not spawned commands, so they should work even if PATH is off.
  11. File manager: Super+Shift+F opens Strata, terminal opens Kitty
  12. Clock popup shows the real month and weekday names, not clock.monthYear / clock.weekShort
  13. Workspace 1 shows 1 / its mode glyph, and SDDM shows the Hexciri emblem, not Omarchy logos
  14. Default apps: Super+Shift+Return opens Brave Origin (default browser), Super+Shift+N opens Zed, Super+Shift+O opens Obsidian, Super+Alt+Return opens tmux in Kitty, menu Capture > Screenrecord records (gpu-screen-recorder), menu Share > Receive opens LocalSend
  15. fastfetch: run `fastfetch` in Kitty, Hexciri logo + layout, not stock, WM shows Hyprland | Quickshell, not Niri | Noctalia
  16. Spotify + Arch substitutes: Super+Shift+M opens Spotify, Super+Shift+Q opens the calculator (gnome-calculator), PRINT takes a screenshot (grim + slurp, saved to ~/Pictures/Screenshots), Super+Shift+Alt+M opens the music TUI (ncspot), Super+Shift+W opens the writing app (Ghostwriter). Super+Ctrl+Return (Herdr) is deliberately unbound, herdr is an Omarchy AI-agent app not installed in v2, use Super+Alt+Return for tmux.

  17. hexciri CLI: `hexciri plugin list` works in a terminal, and `hexciri update` runs the Hexciri update. foot, btop, apostrophe and the Haskell tree are removed and stay removed (post-update hook re-trims on every update).

If Super+Alt+Space (menu) still does nothing after reboot, run this in a terminal and report what it prints:
  hexciri-menu toggle root
If Super+Space (apps) still does nothing, run this instead:
  hexciri-shell "hexciri.dock" "apps"
That tells whether the menu command is missing (PATH), the shell IPC is unreachable, or the menu plugin did not load.

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
  arch-updates EndeavourOS backend, hexciri-update rework, Nyxiri overlay, THPM install.
EOF

# --- Reboot offer, like v1 ---
# Never auto-reboots unless --reboot was passed. Never hangs: with
# --reboot it reboots outright, with a TTY it asks (default No),
# otherwise it just notes a relogin is needed.
# This is the end of the install: v1 does everything up to this point,
# then you just reboot and it is all setup.

step "Reboot?"
if [ "$AUTO_REBOOT" -eq 1 ]; then
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
info "done, Hexiri 2.0 is installed. Pick Hexiri at SDDM after reboot, then pick a theme with hexciri-theme-set if you want a different one."
