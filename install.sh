#!/bin/bash
# hexciri installer.
#
# Split phases so no step ever needs sudo without a terminal:
#   --system-only  run as ROOT   (packages, system files, bootloader, services)
#   --user-only    run as USER   (configs, state, theme seed — zero sudo calls)
#   no flags       Already-on-Arch: system via sudo (real terminal), then user.
#
# usage: ./install.sh [-y] [--dry-run] [--channel stable|bleeding] [--kernel stock|lts|omarchy|bore|muqss]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CHANNEL="stable"
KERNEL_PICK=""
YES=false
DRY_RUN=false
SYSTEM_ONLY=false
USER_ONLY=false
while (($#)); do
  case "$1" in
    -y|--yes) YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --system-only) SYSTEM_ONLY=true; shift ;;
    --user-only) USER_ONLY=true; shift ;;
    --channel=*) CHANNEL="${1#*=}"; shift ;;
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --kernel=*) KERNEL_PICK="${1#*=}"; shift ;;
    --kernel) KERNEL_PICK="${2:-}"; shift 2 ;;
    stable|bleeding) CHANNEL="$1"; shift ;;
    --) shift ;;
    *) shift ;;
  esac
done
[[ $CHANNEL == stable || $CHANNEL == bleeding ]] || { echo "channel must be stable|bleeding"; exit 1; }
# accept short keys or full package names (linux-omarchy-bore -> bore)
case "${KERNEL_PICK,,}" in
  ""|"auto") KERNEL_PICK="" ;;
  stock|linux) KERNEL_PICK=stock ;;
  lts|linux-lts) KERNEL_PICK=lts ;;
  omarchy|linux-omarchy) KERNEL_PICK=omarchy ;;
  bore|linux-omarchy-bore) KERNEL_PICK=bore ;;
  muqss|linux-omarchy-muqss) KERNEL_PICK=muqss ;;
esac
[[ -z $KERNEL_PICK || $KERNEL_PICK =~ ^(stock|lts|omarchy|bore|muqss)$ ]] || { echo "kernel must be stock|lts|omarchy|bore|muqss"; exit 1; }

info() { echo -e "\e[0;36m[hexciri]\e[0m $*"; }
ok()   { echo -e "\e[0;32m[hexciri]\e[0m $*"; }
warn() { echo -e "\e[1;33m[hexciri]\e[0m $*" >&2; }
err()  { echo -e "\e[0;31m[hexciri]\e[0m $*" >&2; }
run() { if $DRY_RUN; then info "[dry-run] $*"; else "$@"; fi; }
confirm() { $YES && return 0; read -rp "$1 [y/N] " r; [[ $r =~ ^[Yy]$ ]]; }

[[ -f /etc/arch-release ]] || { err "not Arch — run on a fresh minimal Arch install"; exit 1; }

export HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
export PATH="/usr/local/bin:$REPO_DIR/bin:$REPO_DIR/scripts:$PATH"

# ── dispatcher: plain invocation on a live system does system (via sudo) then user ──
if ! $SYSTEM_ONLY && ! $USER_ONLY; then
  (( EUID != 0 )) || { err "run as user, not root (or use --system-only)"; exit 1; }
  info "channel: $CHANNEL"
  confirm "Install hexciri ($CHANNEL) on this machine?" || exit 0
  sudo -v || exit 1
  sudo HEXCIRI_USER="$USER" "$0" --system-only ${YES:+ -y} ${DRY_RUN:+--dry-run} --channel "$CHANNEL" ${KERNEL_PICK:+--kernel "$KERNEL_PICK"}
  exec "$0" --user-only ${YES:+ -y} ${DRY_RUN:+--dry-run} --channel "$CHANNEL"
fi

if $SYSTEM_ONLY; then
  (( EUID == 0 )) || { err "--system-only must run as root"; exit 1; }
  TARGET_USER="${HEXCIRI_USER:-${SUDO_USER:-}}"
  [[ -n $TARGET_USER && $TARGET_USER != root ]] || { err "--system-only needs HEXCIRI_USER set to a non-root user"; exit 1; }
  id "$TARGET_USER" &>/dev/null || { err "user $TARGET_USER does not exist"; exit 1; }
  as_user() { run su - "$TARGET_USER" -c "$*"; }

  # ── channel + keyring ──
  info "deploying pacman channel..."
  cp -f /etc/pacman.conf "/etc/pacman.conf.bak.$(date +%s)"
  cp -f "$REPO_DIR/default/pacman/pacman-$CHANNEL.conf" /etc/pacman.conf
  cp -f "$REPO_DIR/default/pacman/mirrorlist-$CHANNEL" /etc/pacman.d/mirrorlist
  if ! pacman -Qi omarchy-keyring &>/dev/null; then
    info "bootstrapping omarchy-keyring (signs the [omarchy] repo)..."
    pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571
  fi
  run pacman -Syyuu --noconfirm

  # ── packages (all repo packages; Brave built from AUR as the user, installed as root) ──
  PKGS=(base-devel git gnupg
    niri xwayland-satellite noctalia kitty fish fuzzel zed opencode strata
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
    run pacman -S --noconfirm --needed "${MISSING[@]}"
  else
    ok "repo packages present"
  fi
  if ! pacman -Q brave-origin-bin &>/dev/null && ! pacman -Q brave-origin-beta-bin &>/dev/null; then
    info "building brave-origin-bin (AUR, as $TARGET_USER)..."
    run rm -rf /tmp/hexciri-aur
    run mkdir -p /tmp/hexciri-aur
    run chown "$TARGET_USER:$TARGET_USER" /tmp/hexciri-aur
    as_user "cd /tmp/hexciri-aur && git clone -q https://aur.archlinux.org/brave-origin-bin.git && cd brave-origin-bin && makepkg --noconfirm"
    run pacman -U --noconfirm /tmp/hexciri-aur/brave-origin-bin/*.pkg.tar.zst
    run rm -rf /tmp/hexciri-aur
  fi

  # ── commands → /usr/local/bin (on PATH for SDDM-launched Niri sessions) ──
  info "installing hexciri commands..."
  for f in "$REPO_DIR"/bin/* "$REPO_DIR"/scripts/*; do
    [[ -f $f ]] && run install -m755 "$f" "/usr/local/bin/$(basename "$f")"
  done
  ok "commands installed"

  # ── themes → /usr/share/hexciri + branding ──
  run mkdir -p /usr/share/hexciri
  run cp -r "$REPO_DIR/themes" /usr/share/hexciri/themes 2>/dev/null || run cp -r "$REPO_DIR/themes/." /usr/share/hexciri/themes/
  run mkdir -p /usr/share/pixmaps
  run cp -f "$REPO_DIR/branding/logo.png" /usr/share/pixmaps/hexciri.png

  # ── services + SDDM (greeter login; autologin returns with LUKS) ──
  run systemctl enable NetworkManager.service 2>/dev/null || true
  run systemctl enable sddm.service 2>/dev/null || true
  # remove any autologin config: no encryption gate means no free pass
  run rm -f /etc/sddm.conf.d/10-hexciri-autologin.conf 2>/dev/null || true

  # ── SDDM theme (emblem + password greeter, Niri preferred) ──
  if ! $DRY_RUN; then
    run mkdir -p /usr/share/sddm/themes/hexciri
    for f in Main.qml metadata.desktop theme.conf; do
      run cp -f "$REPO_DIR/branding/sddm/$f" /usr/share/sddm/themes/hexciri/$f
    done
    run cp -f "$REPO_DIR/branding/logo.png" /usr/share/sddm/themes/hexciri/logo.png
    printf '[Theme]\nCurrent=hexciri\n' | run tee /etc/sddm.conf.d/10-hexciri-theme.conf >/dev/null
  fi

  # ── Plymouth splash (emblem two-step) ──
  if ! $DRY_RUN; then
    pacman -Q plymouth &>/dev/null || run pacman -S --noconfirm plymouth
    run mkdir -p /usr/share/plymouth/themes/hexciri
    for f in hexciri.plymouth watermark.png lock.png; do
      run cp -f "$REPO_DIR/branding/plymouth/$f" /usr/share/plymouth/themes/hexciri/$f
    done
    if ! grep -q '^Theme=hexciri' /etc/plymouth/plymouthd.conf 2>/dev/null; then
      run mkdir -p /etc/plymouth
      printf '[Daemon]\nTheme=hexciri\n' | run tee /etc/plymouth/plymouthd.conf >/dev/null
    fi
    # mkinitcpio: plymouth after udev for splash
    if ! grep -q ' plymouth' /etc/mkinitcpio.conf 2>/dev/null; then
      run cp -f /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$(date +%s)"
      run sed -i 's/\(HOOKS=([^)]*udev\)/\1 plymouth/' /etc/mkinitcpio.conf
      grep -q ' plymouth' /etc/mkinitcpio.conf || run sed -i 's/\(HOOKS=(base\)/\1 plymouth/' /etc/mkinitcpio.conf
      run mkinitcpio -P
    fi
    # splash flag on hexciri-owned boot entries
    for e in /boot/loader/entries/hexciri-*.conf; do
      [[ -f $e ]] || continue
      grep -q 'splash' "$e" || run sed -i 's/^options \(.*\)/options \1 splash/' "$e"
    done
  fi

  # ── version stamp (hexciri-version reads this on installed systems) ──
  if ! $DRY_RUN; then
    v="$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo unknown)"
    run mkdir -p /usr/share/hexciri
    printf '%s %s\n' "$v" "$CHANNEL" | run tee /usr/share/hexciri/VERSION >/dev/null
  fi

  # ── GPU autodetect (runs as root here; installer reboots at the end, not mid-run) ──
  if ! $DRY_RUN; then
    # shellcheck disable=SC2086
    HEXCIRI_NO_REBOOT=1 /usr/local/bin/hexciri-gpu -y ${KERNEL_PICK:+--kernel $KERNEL_PICK} \
      || warn "GPU setup needs attention — re-run: hexciri-gpu"
  fi

  # ── single-kernel policy: a custom pick replaces the staged base kernel ──
  if [[ $KERNEL_PICK == omarchy || $KERNEL_PICK == bore || $KERNEL_PICK == muqss ]] && ! $DRY_RUN; then
    case $KERNEL_PICK in
      omarchy) custom_pkg=linux-omarchy ;;
      bore) custom_pkg=linux-omarchy-bore ;;
      muqss) custom_pkg=linux-omarchy-muqss ;;
    esac
    if pacman -Q "$custom_pkg" &>/dev/null; then
      for k in linux linux-lts; do
        if pacman -Q "$k" &>/dev/null; then
          info "removing staged $k (single-kernel policy)..."
          pacman -Rns --noconfirm "$k"
          pacman -Q "$k-headers" &>/dev/null && pacman -Rns --noconfirm "$k-headers" || true
          rm -f "/boot/loader/entries/hexciri-$k.conf"
        fi
      done
      mkinitcpio -P
    else
      warn "$custom_pkg did not install (custom kernels need bleeding) — keeping staged kernel"
    fi
  fi

  ok "system phase complete (channel: $CHANNEL)"
  exit 0
fi

# ── USER phase: runs as the user, makes zero sudo calls ──
(( EUID != 0 )) || { err "--user-only must not run as root"; exit 1; }
bak="$HOME/.config/hexciri-backup/$(date +%Y%m%d%H%M%S)"
deploy() { # <repo-rel> <dest>
  if [[ -f $2 ]] && ! cmp -s "$REPO_DIR/$1" "$2"; then
    mkdir -p "$bak/$(dirname "$2")"; cp -f "$2" "$bak/$2"
  fi
  mkdir -p "$(dirname "$2")"
  run cp -f "$REPO_DIR/$1" "$2"
}

# user branding art (system branding lives in /usr/share)
mkdir -p ~/.config/hexciri/branding
run cp -f "$REPO_DIR/branding/"*.png ~/.config/hexciri/branding/

# ── configs (backup-first) ──
deploy config/niri/config.kdl "$HOME/.config/niri/config.kdl"
deploy config/noctalia/config.toml "$HOME/.config/noctalia/config.toml"
deploy config/fastfetch/config.jsonc "$HOME/.config/fastfetch/config.jsonc"
deploy config/starship/starship.toml "$HOME/.config/starship.toml"
deploy config/fish/conf.d/hexciri-starship.fish "$HOME/.config/fish/conf.d/hexciri-starship.fish"
mkdir -p "$HOME/.config/hexciri/hooks/theme-set.d"
run cp -f "$REPO_DIR/hooks/theme-set.d/noctalia-sync.sh" "$HOME/.config/hexciri/hooks/theme-set.d/noctalia-sync.sh"

# ── kitty: default config on fresh installs, include migration on converts ──
if [[ ! -f $HOME/.config/kitty/kitty.conf ]]; then
  deploy config/kitty/kitty.conf "$HOME/.config/kitty/kitty.conf"
elif grep -q "state/omarchy/current/theme/kitty.conf" "$HOME/.config/kitty/kitty.conf"; then
  mkdir -p "$bak"; cp -f "$HOME/.config/kitty/kitty.conf" "$bak/kitty.conf"
  run sed -i 's|state/omarchy/current/theme/kitty.conf|state/hexciri/current/theme/kitty.conf|' "$HOME/.config/kitty/kitty.conf"
elif ! grep -q "state/hexciri/current/theme/kitty.conf" "$HOME/.config/kitty/kitty.conf"; then
  mkdir -p "$bak"; cp -f "$HOME/.config/kitty/kitty.conf" "$bak/kitty.conf"
  run sed -i '1i include ~/.local/state/hexciri/current/theme/kitty.conf' "$HOME/.config/kitty/kitty.conf"
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

# ── seed maiden theme ──
if ! $DRY_RUN; then
  HEXCIRI_PATH=/usr/share/hexciri hexciri-theme-set sakurazuki
fi

echo ""
ok "hexciri installed (channel: $CHANNEL, theme: sakurazuki)"
info "configs: ~/.config/niri/config.kdl ~/.config/noctalia/config.toml (backups in $bak)"
info "reboot → SDDM greeter → password → Niri (Mod+K for keybindings)"
