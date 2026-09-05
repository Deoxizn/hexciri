#!/bin/bash
# hexciri installer.
#
# Split phases so no step ever needs sudo without a terminal:
#   --system-only  run as ROOT   (packages, system files, bootloader, services)
#   --user-only    run as USER   (configs, state, theme seed — zero sudo calls)
#   no flags       Already-on-Arch: system via sudo (real terminal), then user.
#
# usage: ./install.sh [-y] [--dry-run] [--channel stable|bleeding] [--kernel stock|lts]
# (kernel defaults to auto: stock, or LTS pinned on legacy NVIDIA; custom kernels are post-install)
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
    grim slurp wl-clipboard cliphist wtype playerctl brightnessctl mpv v4l-utils jq fzf ffmpeg
    gpu-screen-recorder
    mesa vulkan-icd-loader lib32-mesa lib32-vulkan-icd-loader
    libnotify gtk3 xdg-utils desktop-file-utils
    polkit-gnome gnome-keyring xdg-desktop-portal-gtk xdg-desktop-portal-gnome
    adw-gtk-theme
    networkmanager openssh sddm fastfetch starship noto-fonts ttf-jetbrains-mono-nerd
    gnome-disk-utility imv mupdf libreoffice-fresh
    cups hplip unzip
    bluez bluez-utils
    tesseract zbar qrencode fwupd zenity kdialog qt6ct localsend
    pipewire pipewire-pulse wireplumber
    zram-generator pacman-contrib)
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

  # ── maplemono-nf (vendored PKGBUILD): Maple Mono NF — ligature + Nerd Font
  #    icons mono. We vendor a single-variant PKGBUILD (aur/maplemono-nf) instead
  #    of the AUR split base, which would build all 10 subpackages. ──
  if ! pacman -Q maplemono-nf &>/dev/null; then
    info "building maplemono-nf (vendored PKGBUILD, as $TARGET_USER)..."
    run rm -rf /tmp/hexciri-aur
    run mkdir -p /tmp/hexciri-aur
    run chown "$TARGET_USER:$TARGET_USER" /tmp/hexciri-aur
    run cp -r "$REPO_DIR/aur/maplemono-nf" /tmp/hexciri-aur/maplemono-nf
    run chown -R "$TARGET_USER:$TARGET_USER" /tmp/hexciri-aur/maplemono-nf
    run chmod -R u+rwX /tmp/hexciri-aur/maplemono-nf
    as_user "cd /tmp/hexciri-aur/maplemono-nf && makepkg --noconfirm"
    run pacman -U --noconfirm /tmp/hexciri-aur/maplemono-nf/*.pkg.tar.zst
    run rm -rf /tmp/hexciri-aur
  fi

  # ── zram swap: compressed, sized to RAM (no disk swapfile needed) ──
  run mkdir -p /etc/systemd
  if [[ ! -f /etc/systemd/zram-generator.conf ]] || ! grep -q '^\[zram0\]' /etc/systemd/zram-generator.conf; then
    cat > /etc/systemd/zram-generator.conf <<'ZRAM'
[zram0]
zram-size = ram
compression-algorithm = zstd
ZRAM
    info "wrote /etc/systemd/zram-generator.conf (zram0 = 100% of RAM, zstd) — active on next boot"
  else
    ok "zram already configured"
  fi

  # ── pacman cache: prune on every transaction (vanilla Arch-wiki hook; no
  #    omarchy-style pre-update prune step needed) ──
  run mkdir -p /usr/share/libalpm/hooks
  if [[ ! -f /usr/share/libalpm/hooks/hexciri-paccache.hook ]] || \
     ! grep -q 'Exec = /usr/bin/paccache -rk1 -rk0' /usr/share/libalpm/hooks/hexciri-paccache.hook; then
    cat > /usr/share/libalpm/hooks/hexciri-paccache.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Pruning pacman cache (hexciri: paccache -rk1 -rk0)
When = PostTransaction
Exec = /usr/bin/paccache -rk1 -rk0
HOOK
    info "wrote /usr/share/libalpm/hooks/hexciri-paccache.hook (PostTransaction cache prune)"
  else
    ok "paccache hook present"
  fi

  # ── commands → /usr/local/bin (on PATH for SDDM-launched Niri sessions) ──
  info "installing hexciri commands..."
  for f in "$REPO_DIR"/bin/* "$REPO_DIR"/scripts/*; do
    [[ -f $f ]] && run install -m755 "$f" "/usr/local/bin/$(basename "$f")"
  done
  ok "commands installed"

  # ── themes → /usr/share/hexciri + branding (clean copy so re-runs never nest) ──
  run mkdir -p /usr/share/hexciri
  run rm -rf /usr/share/hexciri/themes
  run cp -r "$REPO_DIR/themes" /usr/share/hexciri/themes
  run rm -rf /usr/share/hexciri/default
  run mkdir -p /usr/share/hexciri/default
  run cp -r "$REPO_DIR/default/themed" /usr/share/hexciri/default/themed
  run mkdir -p /usr/share/pixmaps
  run cp -f "$REPO_DIR/branding/logo.png" /usr/share/pixmaps/hexciri.png

  # ── services + SDDM (greeter login with a password; no disk encryption,
  #    so the login gate lives at the sddm prompt itself) ──
  run systemctl enable NetworkManager.service 2>/dev/null || true
  run systemctl enable sshd.service 2>/dev/null || true
  run systemctl enable sddm.service 2>/dev/null || true
  # ── session: sddm rejects login pre-PAM when no session is selectable,
  #    which reads exactly like a wrong password on first try. niri ships its
  #    desktop file; guarantee one exists as a fallback minimal entry ──
  run mkdir -p /usr/share/wayland-sessions
  if [[ ! -f /usr/share/wayland-sessions/niri.desktop ]]; then
    printf '[Desktop Entry]\nName=Niri\nComment=Scrollable-tiling Wayland compositor\nExec=/usr/bin/niri\nType=Application\n' \
      | run tee /usr/share/wayland-sessions/niri.desktop >/dev/null
    ok "niri session file missing — created fallback /usr/share/wayland-sessions/niri.desktop"
  fi
  # ── printing: cups socket activation + HP (hplip); lp/scanner groups let the
  #    user manage queues/admin and access the HP scanner over sane ──
  run systemctl enable --now cups.socket 2>/dev/null || true
  run usermod -aG lp,scanner "$TARGET_USER" 2>/dev/null || true
  # ── bluetooth: bluez stack + rfkill; bar widget + pairing need bluetoothd ──
  run systemctl enable --now bluetooth.service 2>/dev/null || true
  # remove any autologin config: no encryption gate means no free pass
  run rm -f /etc/sddm.conf.d/10-hexciri-autologin.conf 2>/dev/null || true

  # ── gnome-keyring: unlock the login keyring at sddm login via pam. Without
  #    this, the "Unlock Login Keyring" popup appears whenever the first app
  #    touches secrets. Deploy the full pam stack (backup-first, idempotent). ──
  if [[ ! -f /etc/pam.d/sddm ]] || ! grep -q 'pam_gnome_keyring.so' /etc/pam.d/sddm; then
    run cp -f /etc/pam.d/sddm "/etc/pam.d/sddm.bak.$(date +%s)" 2>/dev/null || true
    run cp -f "$REPO_DIR/default/pam/sddm" /etc/pam.d/sddm
    info "sddm login: wired pam_gnome_keyring (auto-unlocks 'login' keyring)"
  fi

  # ── SDDM theme (emblem + password greeter, Niri preferred) ──
  if ! $DRY_RUN; then
    run mkdir -p /usr/share/sddm/themes/hexciri
    for f in Main.qml metadata.desktop theme.conf; do
      run cp -f "$REPO_DIR/branding/sddm/$f" /usr/share/sddm/themes/hexciri/$f
    done
    run cp -f "$REPO_DIR/branding/logo.png" /usr/share/sddm/themes/hexciri/logo.png
    # Prefill the greeter's username field from the install user this session;
    # the SddmComponents user model can be empty/slow on a fresh first boot.
    printf '\nUsername=%s\n' "${TARGET_USER:-}" | run tee -a /usr/share/sddm/themes/hexciri/theme.conf >/dev/null
    run mkdir -p /etc/sddm.conf.d
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
    # theme-packaged proof: if hexciri isn't in the initramfs, plymouth falls
    # back to the stock arch theme ('ARCH LINUX' wordmark) at boot. Fail loudly
    # before reboot instead of shipping a silent fallback.
    for img in /boot/initramfs-*.img; do
      [[ -f $img ]] || continue
      if lsinitcpio -l "$img" 2>/dev/null | grep -qE 'themes/hexciri/hexciri\.plymouth'; then
        ok "plymouth ${img##*/}: hexciri theme packaged"
      else
        warn "hexciri theme missing from ${img##*/} — boot will show the stock arch splash (re-run: mkinitcpio -P)"
      fi
    done
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
deploy() { # <repo-rel> <dest> — never clobber local edits (sha-tracked)
  local src="$REPO_DIR/$1" dest="$2" rel="$1" sf dyn_now dyn_prev=""
  mkdir -p "$(dirname "$dest")"
  local state="$HOME/.local/state/hexciri/configs"
  mkdir -p "$state"
  sf="$state/$(printf '%s' "$rel" | tr '/' '_').sha"
  [[ -f $sf ]] && read -r dyn_prev < "$sf" || true
  dyn_now="$(sha256sum "$dest" 2>/dev/null | cut -d' ' -f1 || true)"
  if [[ -f $dest ]] && ! cmp -s "$src" "$dest"; then
    mkdir -p "$bak/$(dirname "$dest")"; cp -f "$dest" "$bak/$dest"
    if [[ -n $dyn_prev && -n $dyn_now && $dyn_now == "$dyn_prev" ]]; then
      # untouched since our last deploy → safe to update in place
      run cp -f "$src" "$dest"
    else
      # user-modified (or modified by a tool) → keep theirs, ship repo default alongside;
      # hash NOT recorded, so every future run keeps their version too
      run cp -f "$src" "$dest.hexciri"
      info "kept your $dest; repo default written to $dest.hexciri (backup in $bak)"
      return 0
    fi
  else
    run cp -f "$src" "$dest"
  fi
  sha256sum "$dest" | cut -d' ' -f1 > "$sf"
}

# user branding art (system branding lives in /usr/share)
mkdir -p ~/.config/hexciri/branding
run cp -f "$REPO_DIR/branding/"*.png ~/.config/hexciri/branding/

# ── configs (backup-first) ──
deploy config/niri/config.kdl "$HOME/.config/niri/config.kdl"

# ── monitor auto-detect: fill in `output` blocks if none exist yet ──
# Reads connected outputs from the live compositor (preferred mode + refresh
# rate), or sysfs/EDID as a fallback pre-session, and derives a sensible scale
# from the physical size. Never touches outputs that are already configured,
# and leaves user edits alone.
detect_monitors() {
  local sock="" nm mode ph wm hm wpx hpx scale vrr section="" line
  command -v niri >/dev/null 2>&1 && sock="$(ls "/run/user/$(id -u)"/niri.*.sock 2>/dev/null | head -1)"
  if [[ -n $sock ]]; then
    while read -r line; do
      case "$line" in
        Output*) nm="$(sed -n 's/.*(\([^()]*\)).*/\1/p' <<<"$line")" ;;
        *"Current mode:"*)
          mode="$(sed -n 's/.*Current mode: \([0-9]*x[0-9]*\) @ \([0-9.]*\).*/\1@\2/p' <<<"$line")" ;;
        *"Variable refresh rate: supported"*) vrr=1 ;;
        *"Variable refresh rate: not supported"*) vrr=0 ;;
        *"Physical size:"*)
          ph="$(sed -n 's/.*Physical size: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' <<<"$line")"
          wm="${ph% *}"; hm="${ph#* }"
          wpx="${mode%%x*}"; hpx="${mode%@*}"; hpx="${hpx#*x}"
          scale=1
          if (( wpx > 0 && hpx > 0 && wm > 0 && hm > 0 )); then
            scale="$(awk -v W="$wpx" -v H="$hpx" -v WM="$wm" -v HM="$hm" \
              'BEGIN{ ppi=sqrt(W*W+H*H)*25.4/sqrt(WM*WM+HM*HM); s=ppi/160; if(s<1)s=1; if(s>2)s=2;
                      printf "%.2f", int(s*4+0.5)/4 }')"
          fi
          if [[ -n $nm && -n $mode ]] && ! grep -q "^output \"$nm\"" "$niri_cfg"; then
            section+="output \"$nm\" {\n    mode \"$mode\"\n    scale $scale"
            (( vrr == 1 )) && section+="\n    variable-refresh-rate"
            section+="\n}\n\n"
          fi
          vrr=0
          ;;
      esac
    done < <(NIRI_SOCKET="$sock" niri msg outputs 2>/dev/null)
  else
    # fallback: sysfs/EDID (no refresh rates before the compositor is up)
    for line in /sys/class/drm/card*-*; do
      [[ -f $line/status ]] || continue
      [[ "$(cat "$line/status" 2>/dev/null)" == connected ]] || continue
      nm="${line##*/}"; nm="${nm#card*-}"
      grep -q "^output \"$nm\"" "$niri_cfg" && continue
      mode="$(sed -n '1s/^ *//;1s/[[:space:]].*//p' "$line/modes" 2>/dev/null)"
      [[ -n $mode ]] || continue
      wpx="${mode%@*}"; hpx="${wpx#*x}"; wpx="${wpx%x*}"
      read -r wm hm < <(od -An -tu1 -j21 -N2 "$line/edid" 2>/dev/null)
      (( wm *= 10; hm *= 10 )) 2>/dev/null || { wm=0; hm=0; }
      scale=1
      if (( wpx > 0 && hpx > 0 && wm > 0 && hm > 0 )); then
        scale="$(awk -v W="$wpx" -v H="$hpx" -v WM="$wm" -v HM="$hm" \
          'BEGIN{ ppi=sqrt(W*W+H*H)*25.4/sqrt(WM*WM+HM*HM); s=ppi/160; if(s<1)s=1; if(s>2)s=2;
                  printf "%.2f", int(s*4+0.5)/4 }')"
      fi
      section+="output \"$nm\" {\n    mode \"$mode\"\n    scale $scale\n}\n\n"
    done
  fi
  printf "%b" "$section"
}
niri_cfg="$HOME/.config/niri/config.kdl"
if [[ -f $niri_cfg ]] && ! grep -q '^output ' "$niri_cfg"; then
  gen="$(detect_monitors)"
  if [[ -n $gen ]]; then
    printf '\n%s' "$gen" >> "$niri_cfg"
    info "monitor auto-detect: appended output block(s) to $niri_cfg"
  fi
fi

deploy config/noctalia/config.toml "$HOME/.config/noctalia/config.toml"
deploy config/fastfetch/config.jsonc "$HOME/.config/fastfetch/config.jsonc"
deploy config/starship/starship.toml "$HOME/.config/starship.toml"
deploy config/fish/conf.d/hexciri-starship.fish "$HOME/.config/fish/conf.d/hexciri-starship.fish"
deploy config/fish/conf.d/hexciri-aliases.fish "$HOME/.config/fish/conf.d/hexciri-aliases.fish"
deploy config/fish/conf.d/hexciri-util.fish "$HOME/.config/fish/conf.d/hexciri-util.fish"
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
# ── where the source repo lives, so hexciri-repo-sync can pull/reinstall it ──
mkdir -p "$HOME/.local/state/hexciri"
run bash -c "printf '%s' '$REPO_DIR' > '$HOME/.local/state/hexciri/repo-path'"
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

# ── Work folder: create and pin in Strata (Strata reads the standard GTK
#    bookmarks file; entries pointing at missing dirs are dropped, so mkdir first) ──
mkdir -p "$HOME/Work"
book="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$book")"
touch "$book"
work_uri="file://$HOME/Work"
if ! grep -qF "$work_uri" "$book"; then
  printf '%s Work\n' "$work_uri" >> "$book"
  info "pinned ~/Work in Strata sidebar"
fi

# ── keyring: a legacy "Default" store (created by the daemon with its own
#    password before pam was wired in) triggers "unlock keyring" popups.
#    Drop it so the next login recreates the auto-unlocked "login" keyring via
#    pam_gnome_keyring (default/pam/sddm). Backed up, not deleted. ──
kr="$HOME/.local/share/keyrings"
if [[ -f $kr/Default.keyring ]] && [[ ! -f $kr/login.keyring ]]; then
  mv "$kr" "$kr.noprompt.bak"
  info "reset legacy keyring store (Default.keyring); next login recreates auto-unlocked 'login' keyring"
fi

# ── GTK4/libadwaita dark theming: adw-gtk-theme + the dark color-scheme preference ──
if command -v gsettings >/dev/null 2>&1 && [[ -d /usr/share/themes/adw-gtk3 ]]; then
  run gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3 2>/dev/null || true
  run gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
  info "gtk: adw-gtk-theme (dark libadwaita)"
fi

# ── audio: pipewire session via user units (vanilla Arch way; Noctalia pulls the
#    libs, these are the daemons that make sound actually route) ──
if command -v pipewire >/dev/null 2>&1; then
  systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
  info "audio: enabled user units (pipewire.socket + pulse + wireplumber)"
fi

# ── seed maiden theme ──
if ! $DRY_RUN; then
  HEXCIRI_PATH=/usr/share/hexciri hexciri-theme-set sakurazuki
fi

# ── noctalia arch-updater plugin presets: plugin-level settings are owned by
#    the state dir, so seed the missing keys of the preset into settings.toml
#    (GUI overrides win — existing values are never touched). kitty + the
#    native update_cmd give a real PTY, so no service.luau patch/guard is
#    required on any plugin version that honors these keys. ──
mkdir -p "$HOME/.local/state/noctalia"
SEED_TMP="$HOME/.local/state/noctalia/settings.hexciri-seed"
run mkdir -p "$HOME/.local/state/noctalia"
if grep -q '\[plugin_settings."yuuto/arch-updater"\]' "$HOME/.local/state/noctalia/settings.toml" 2>/dev/null; then
  ok "arch-updater plugin presets present (left untouched)"
else
  run bash -c "cp '$REPO_DIR/config/noctalia/arch-updater.toml' '$SEED_TMP'"
  { printf '\n'; cat "$SEED_TMP"; } >> "$HOME/.local/state/noctalia/settings.toml" 2>/dev/null \
    || run bash -c "{ printf '\\n'; cat '$SEED_TMP'; } >> '$HOME/.local/state/noctalia/settings.toml'"
  run rm -f "$SEED_TMP"
  info "seeded arch-updater plugin presets into ~/.local/state/noctalia/settings.toml"
fi

echo ""
ok "hexciri installed (channel: $CHANNEL, theme: sakurazuki)"
info "configs: ~/.config/niri/config.kdl ~/.config/noctalia/config.toml (backups in $bak)"
info "reboot → SDDM greeter → password → Niri (Mod+K for keybindings)"
