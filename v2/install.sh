#!/usr/bin/env bash
# Hexiri 2.0 single installer
# Name: Hexiri
# Base: EndeavourOS, Calamares online install, No Desktop selected
# Shell: forked Omarchy Quickshell shell, renamed hexciri, exact same menu, bar, themes
# Goal: a very minimal almost nothing installed Arch that still has the feel and look of Omarchy.
#
# This is the one command, minus the EndeavourOS install itself.
# It merges the old two Phase 1 scripts into one, in order:
#   1. Preflight, packages, GPU drivers, Quickshell, Hyprland, SDDM plus uwsm
#   2. Download omacom/omarchy at the pinned commit as a tarball (no git, no auth),
#      verify SHA from the tarball top dir, then fork and rename the shell inline
#   4. Place the forked tree to /usr/share/hexciri, ~/.config/hexciri,
#      ~/.local/state/hexciri, and ~/.config/hypr, and wire the compat alias in
#   5. Verify placement, then reboot test checklist
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
#   Apps, GUI preinstalls, Docker, AI agents
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
  pamixer brightnessctl jq bc curl wget git base-devel
  imagemagick inotify-tools grim slurp wl-clipboard hyprpicker hyprsunset ffmpeg unzip
  ripgrep fd fzf eza bat btop starship zoxide fastfetch
  python python-gobject lua51 luarocks
  foot
  noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd woff2-font-awesome terminus-font
  # NOTE 2026-11-23: noto-fonts-cjk-vf and ttf-jetbrains-mono-nerd-basic are
  # Omarchy-repo-only names (Omarchy edge channel / omarchy pkg), NOT Arch.
  # pacman on plain Arch/EndeavourOS fails with "target not found" on both.
  # Arch extra equivalents: noto-fonts-cjk, ttf-jetbrains-mono-nerd.
)

sudo pacman -S --needed --noconfirm "${CORE_PKGS[@]}"

step "Updating user directories"
xdg-user-dirs-update || warn "xdg-user-dirs-update failed, not fatal."

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
    launch-shell | theme-set | theme-set-templates | plugin-add | plugin-catalog | plugin-clone | plugin-disable | plugin-enable | plugin-list | plugin-remove | plugin-update | plugin-validate | bar | bar-text-color | shell | shell-config | migrate | migrate-notify | hook | hook-install | \
      refresh-hyprland | hyprland-reload-guard | notification-send | menu | menu-clipboard | menu-emoji | menu-emoji-insert | menu-file | menu-herdr-keybindings | menu-images | menu-input | menu-keybindings | menu-plugin | menu-region-formats | menu-select | menu-share | menu-timezone | menu-tmux-keybindings | \
      provision-user | provision-first-run | provision-hardware | provision-owner | reinstall-configs | reinstall | reinstall-pkgs | version | version-branch | version-channel | version-pkgs | update | update-* | launch-*)
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

  # All themes, colors.toml + shell.toml, verbatim except path renames applied later. 23 themes at pinned commit.
  copy_subset "$OMARCHY_SRC/themes" "$FORK_OUT/themes" "themes/"

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
    (b"omarchy-menu", b"hexciri-menu"),
    (b"omarchy.lua", b"hexciri.lua"),
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
print("Content rewrite: %d files scanned, %d files changed" % (total_files, changed_files))
PY
  info "Content rewrite complete"
  info "Renames applied: /usr/share/omarchy -> /usr/share/hexciri, ~/.config/omarchy -> ~/.config/hexciri, ~/.local/state/omarchy -> ~/.local/state/hexciri, ~/.local/share/omarchy -> ~/.local/share/hexciri, OMARCHY_PATH -> HEXCIRI_PATH, omarchy.bar etc -> hexciri.bar etc, omarchy-shell -> hexciri-shell, omarchy-theme-set -> hexciri-theme-set, omarchy-launch-* -> hexciri-launch-*, default/hypr/omarchy.lua -> default/hypr/hexciri.lua, config/hypr/hyprland.lua env fallback updated by the same map"
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

copy_subsets
rename_files
rewrite_contents
generate_compat
verify_no_omarchy_files
verify_no_omarchy_paths

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
  if command -v lua5.1 >/dev/null 2>&1; then
    lua5.1 -e 'assert(loadfile(arg[1]))' "$HEXCIRI_LUA" || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (lua5.1 syntax OK)"
  elif command -v luac5.1 >/dev/null 2>&1; then
    luac5.1 -p "$HEXCIRI_LUA" || die "Lua syntax check failed on wired $HEXCIRI_LUA"
    info "Wired: hexciri-compat.lua required from default/hypr/hexciri.lua (luac5.1 syntax OK)"
  else
    warn "No lua5.1/luac5.1 binary found, skipping Lua syntax check on wired hexciri.lua."
  fi
else
  die "default/hypr/hexciri.lua not found in fork output, cannot wire compat require."
fi

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
EOF
sudo install -Dm644 "$TMP_PROFILE" /etc/profile.d/hexciri.sh
rm -f "$TMP_PROFILE"
info "Installed: /etc/profile.d/hexciri.sh"

TMP_UWSM="$(mktemp)"
cat > "$TMP_UWSM" <<'EOF'
HEXCIRI_PATH=/usr/share/hexciri
OMARCHY_PATH=/usr/share/hexciri
EOF
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
for _check in "$HEXCIRI_PATH/bin/hexciri-launch-shell" "$HEXCIRI_PATH/shell/shell.qml" "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hexciri/shell.json" /usr/share/wayland-sessions/hexciri.desktop; do
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
  4. Quickshell starts, stock bar appears: `quickshell --version` in foot if the shell is missing
  5. Network works: `nmcli device status`
  6. Audio works: `wpctl status` (PipeWire ships with EndeavourOS)
  7. Bluetooth works if needed: `bluetoothctl devices`
  8. Theme: `hexciri-theme-set` with a stock theme, check bar and menu recolor
  9. Plugin: install a stock plugin, check it loads, check the alias resolves omarchy.bar to hexciri.bar

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
