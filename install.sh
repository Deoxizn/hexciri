#!/bin/bash
# hexciri installer — fresh minimal Arch (archinstall: systemd-boot, NetworkManager)
# → channel + keyring + packages → configs/scripts/themes → seed → login at SDDM/Niri
# usage: ./install.sh [-y] [--dry-run] [--channel stable|bleeding] [--kernel stock|lts|omarchy|bore|muqss]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CHANNEL="stable"
KERNEL_PICK=""
YES=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=true ;;
    --dry-run) DRY_RUN=true ;;
    --channel) shift || true ;;
    --channel=*) CHANNEL="${arg#*=}" ;;
    --kernel=*) KERNEL_PICK="${arg#*=}" ;;
    stable|bleeding) CHANNEL="$arg" ;;
  esac
done
[[ $CHANNEL == stable || $CHANNEL == bleeding ]] || { echo "channel must be stable|bleeding"; exit 1; }
[[ -z $KERNEL_PICK || $KERNEL_PICK =~ ^(stock|lts|omarchy|bore|muqss)$ ]] || { echo "kernel must be stock|lts|omarchy|bore|muqss"; exit 1; }

info() { echo -e "\e[0;36m[hexciri]\e[0m $*"; }
ok()   { echo -e "\e[0;32m[hexciri]\e[0m $*"; }
warn() { echo -e "\e[1;33m[hexciri]\e[0m $*" >&2; }
err()  { echo -e "\e[0;31m[hexciri]\e[0m $*" >&2; }
run() { if $DRY_RUN; then info "[dry-run] $*"; else "$@"; fi; }
srun() { if $DRY_RUN; then info "[dry-run] sudo $*"; else sudo "$@"; fi; }
confirm() { $YES && return 0; read -rp "$1 [y/N] " r; [[ $r =~ ^[Yy]$ ]]; }

[[ -f /etc/arch-release ]] || { err "not Arch — run on a fresh minimal Arch install"; exit 1; }
(( EUID != 0 )) || { err "run as user, not root"; exit 1; }
sudo -v || exit 1

export HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
export PATH="/usr/local/bin:$REPO_DIR/bin:$REPO_DIR/scripts:$PATH"

info "channel: $CHANNEL"
confirm "Install hexciri ($CHANNEL) on this machine?" || exit 0

# ── channel + keyring ──
info "deploying pacman channel..."
srun cp -f /etc/pacman.conf "/etc/pacman.conf.bak.$(date +%s)"
srun cp -f "$REPO_DIR/default/pacman/pacman-$CHANNEL.conf" /etc/pacman.conf
srun cp -f "$REPO_DIR/default/pacman/mirrorlist-$CHANNEL" /etc/pacman.d/mirrorlist
if ! pacman -Qi omarchy-keyring &>/dev/null; then
  info "bootstrapping omarchy-keyring (signs the [omarchy] repo)..."
  srun pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keyserver.ubuntu.com
  srun pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571
fi
run sudo pacman -Syyuu --noconfirm

# ── packages (all repo packages; only Brave needs AUR) ──
PKGS=(niri xwayland-satellite noctalia kitty fish fuzzel zed opencode strata
  grim slurp wl-clipboard cliphist wtype playerctl brightnessctl mpv imv v4l-utils jq ffmpeg
  gpu-screen-recorder
  mesa vulkan-icd-loader lib32-mesa lib32-vulkan-icd-loader
  libnotify gtk3 xdg-utils desktop-file-utils
  polkit-gnome gnome-keyring xdg-desktop-portal-gtk xdg-desktop-portal-gnome
  networkmanager sddm fastfetch starship noto-fonts ttf-jetbrains-mono-nerd)
MISSING=()
for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null || MISSING+=("$p"); done
if ((${#MISSING[@]})); then
  info "installing: ${MISSING[*]}"
  srun pacman -S --noconfirm "${MISSING[@]}"
else
  ok "repo packages present"
fi
if ! pacman -Q brave-origin-bin &>/dev/null && ! pacman -Q brave-origin-beta-bin &>/dev/null; then
  command -v yay &>/dev/null || { info "installing yay..."; srun pacman -S --noconfirm --needed base-devel git; (cd /tmp && rm -rf yay-bin && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm); }
  info "installing brave-origin-bin (AUR)..."
  run yay -S --noconfirm brave-origin-bin
fi

# ── commands → /usr/local/bin (on PATH for SDDM-launched Niri sessions) ──
info "installing hexciri commands..."
for f in "$REPO_DIR"/bin/* "$REPO_DIR"/scripts/*; do
  [[ -f $f ]] && srun install -m755 "$f" "/usr/local/bin/$(basename "$f")"
done
ok "commands installed"

# ── themes → /usr/share/hexciri + branding ──
srun mkdir -p /usr/share/hexciri
srun cp -r "$REPO_DIR/themes" /usr/share/hexciri/themes 2>/dev/null || srun cp -r "$REPO_DIR/themes/." /usr/share/hexciri/themes/
srun mkdir -p /usr/share/pixmaps
srun cp -f "$REPO_DIR/branding/logo.png" /usr/share/pixmaps/hexciri.png
mkdir -p ~/.config/hexciri/branding
cp -f "$REPO_DIR/branding/"*.png ~/.config/hexciri/branding/

# ── configs (backup-first) ──
bak="$HOME/.config/hexciri-backup/$(date +%Y%m%d%H%M%S)"
deploy() { # <repo-rel> <dest>
  if [[ -f $2 ]] && ! cmp -s "$REPO_DIR/$1" "$2"; then
    mkdir -p "$bak/$(dirname "$2")"; cp -f "$2" "$bak/$2"
  fi
  mkdir -p "$(dirname "$2")"
  run cp -f "$REPO_DIR/$1" "$2"
}
deploy config/niri/config.kdl "$HOME/.config/niri/config.kdl"
deploy config/noctalia/config.toml "$HOME/.config/noctalia/config.toml"
deploy config/fastfetch/config.jsonc "$HOME/.config/fastfetch/config.jsonc"
deploy config/starship/starship.toml "$HOME/.config/starship.toml"
deploy config/fish/conf.d/hexciri-starship.fish "$HOME/.config/fish/conf.d/hexciri-starship.fish"
mkdir -p "$HOME/.config/hexciri/hooks/theme-set.d"
run cp -f "$REPO_DIR/hooks/theme-set.d/noctalia-sync.sh" "$HOME/.config/hexciri/hooks/theme-set.d/noctalia-sync.sh"

# ── kitty include → hexciri state (backup-first) ──
if [[ -f $HOME/.config/kitty/kitty.conf ]] && grep -q "state/omarchy/current/theme/kitty.conf" "$HOME/.config/kitty/kitty.conf"; then
  mkdir -p "$bak"; cp -f "$HOME/.config/kitty/kitty.conf" "$bak/kitty.conf"
  run sed -i 's|state/omarchy/current/theme/kitty.conf|state/hexciri/current/theme/kitty.conf|' "$HOME/.config/kitty/kitty.conf"
fi

# ── defaults state (kitty/fish/brave-origin/strata/zed/opencode) ──
mkdir -p "$HOME/.local/state/hexciri/defaults"
for kv in "terminal=kitty" "shell=fish" "browser=brave-origin" "files=strata" "editor=zed" "agent=opencode"; do
  k="${kv%%=*}"; v="${kv#*=}"
  [[ -f $HOME/.local/state/hexciri/defaults/$k ]] || run bash -c "printf '%s' '$v' > '$HOME/.local/state/hexciri/defaults/$k'"
done
for d in brave-origin.desktop com.brave.Origin.desktop brave-origin-beta.desktop; do
  if [[ -f /usr/share/applications/$d || -f ~/.local/share/applications/$d ]]; then
    run xdg-settings set default-web-browser "$d" 2>/dev/null || true; break
  fi
done
run xdg-mime default io.github.lgse.Strata.desktop inode/directory 2>/dev/null || true
if [[ $SHELL != *fish ]] && command -v fish &>/dev/null; then
  if confirm "Switch login shell to fish? (current: $SHELL)"; then srun chsh -s /usr/bin/fish "$USER"; fi
fi

# ── services + SDDM autologin (LUKS passphrase is the gate
# when encrypted, otherwise straight to Niri — no greeter stop) ──
srun systemctl enable NetworkManager.service 2>/dev/null || true
srun systemctl enable sddm.service 2>/dev/null || true
if ! $DRY_RUN; then
  if [[ -f /etc/sddm.conf.d/10-hexciri-autologin.conf ]]; then
    srun cp -f /etc/sddm.conf.d/10-hexciri-autologin.conf "/etc/sddm.conf.d/10-hexciri-autologin.conf.bak.$(date +%s)"
  else
    srun mkdir -p /etc/sddm.conf.d
  fi
  printf '[Autologin]\nUser=%s\nSession=niri.desktop\n' "$USER" | srun tee /etc/sddm.conf.d/10-hexciri-autologin.conf >/dev/null
fi

# ── SDDM theme (emblem + password greeter, Niri preferred) ──
if ! $DRY_RUN; then
  srun mkdir -p /usr/share/sddm/themes/hexciri
  for f in Main.qml metadata.desktop theme.conf; do
    srun cp -f "$REPO_DIR/branding/sddm/$f" /usr/share/sddm/themes/hexciri/$f
  done
  srun cp -f "$REPO_DIR/branding/logo.png" /usr/share/sddm/themes/hexciri/logo.png
  printf '[Theme]\nCurrent=hexciri\n' | srun tee /etc/sddm.conf.d/10-hexciri-theme.conf >/dev/null
fi

# ── Plymouth splash (emblem two-step; LUKS prompt renders graphically) ──
if ! $DRY_RUN; then
  pacman -Q plymouth &>/dev/null || srun pacman -S --noconfirm plymouth
  srun mkdir -p /usr/share/plymouth/themes/hexciri
  for f in hexciri.plymouth watermark.png lock.png; do
    srun cp -f "$REPO_DIR/branding/plymouth/$f" /usr/share/plymouth/themes/hexciri/$f
  done
  if ! grep -q '^Theme=hexciri' /etc/plymouth/plymouthd.conf 2>/dev/null; then
    srun mkdir -p /etc/plymouth
    printf '[Daemon]\nTheme=hexciri\n' | srun tee /etc/plymouth/plymouthd.conf >/dev/null
  fi
  # mkinitcpio: plymouth after udev; plymouth-encrypt instead of encrypt on LUKS
  if ! grep -q ' plymouth' /etc/mkinitcpio.conf 2>/dev/null; then
    srun cp -f /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$(date +%s)"
    if grep -q ' encrypt' /etc/mkinitcpio.conf; then
      srun sed -i 's/ encrypt / plymouth-encrypt /' /etc/mkinitcpio.conf
    elif [[ $(findmnt -no SOURCE / 2>/dev/null) == /dev/mapper/* ]]; then
      # LUKS root (stock HOOKS have no encrypt hook): add plymouth-encrypt after block
      srun sed -i 's/\(HOOKS=([^)]*block\)/\1 plymouth-encrypt/' /etc/mkinitcpio.conf
    fi
    srun sed -i 's/\(HOOKS=([^)]*udev\)/\1 plymouth/' /etc/mkinitcpio.conf
    grep -q ' plymouth' /etc/mkinitcpio.conf || srun sed -i 's/\(HOOKS=(base\)/\1 plymouth/' /etc/mkinitcpio.conf
    srun mkinitcpio -P
  fi
  # splash flag on hexciri-owned boot entries
  for e in /boot/loader/entries/hexciri-*.conf; do
    [[ -f $e ]] || continue
    grep -q 'splash' "$e" || srun sed -i 's/^options \(.*\)/options \1 splash/' "$e"
  done
fi

# ── version stamp (hexciri-version reads this on installed systems) ──
if ! $DRY_RUN; then
  v="$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo unknown)"
  srun mkdir -p /usr/share/hexciri
  printf '%s %s\n' "$v" "$CHANNEL" | srun tee /usr/share/hexciri/VERSION >/dev/null
fi

# ── seed maiden theme ──
if ! $DRY_RUN; then
  HEXCIRI_PATH=/usr/share/hexciri /usr/local/bin/hexciri-theme-set sakurazuki
fi

# ── GPU autodetect (always runs; installer reboots at the end, not mid-run) ──
if ! $DRY_RUN; then
  # shellcheck disable=SC2086
  HEXCIRI_NO_REBOOT=1 /usr/local/bin/hexciri-gpu -y ${KERNEL_PICK:+--kernel $KERNEL_PICK} \
    || warn "GPU setup needs attention — re-run: hexciri-gpu"
fi

# ── close the bootstrap sudo window (belt+suspenders: stage2 traps it too) ──
srun rm -f /etc/sudoers.d/hexciri-install 2>/dev/null || true

echo ""
ok "hexciri installed (channel: $CHANNEL, theme: sakurazuki)"
info "configs: ~/.config/niri/config.kdl ~/.config/noctalia/config.toml (backups in $bak)"
info "reboot → autologin straight into Niri → Mod+Space, Mod+Alt+Space, Mod+K"
