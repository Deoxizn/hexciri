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
UPDATE_MODE=false
while (($#)); do
  case "$1" in
    -y|--yes) YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --system-only) SYSTEM_ONLY=true; shift ;;
    --user-only) USER_ONLY=true; shift ;;
    --update) UPDATE_MODE=true; shift ;;
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

export HEXCIRI_PATH="${HEXCIRI_PATH:-$REPO_DIR}"
export PATH="$REPO_DIR/bin:$PATH"

# ── dispatcher: plain invocation on a live system does system (via sudo) then user ──
if ! $SYSTEM_ONLY && ! $USER_ONLY; then
  (( EUID != 0 )) || { err "run as user, not root (or use --system-only)"; exit 1; }
  info "channel: $CHANNEL"
  confirm "Install hexciri ($CHANNEL) on this machine?" || exit 0
  sudo -v || exit 1
  # forward boolean flags verbatim: ${VAR:+word} fires on ANY non-empty VAR
  # ("false" included), so build them explicitly to avoid always-forwarding.
re_exec_flags=""
$DRY_RUN && re_exec_flags+=" --dry-run"
$UPDATE_MODE && re_exec_flags+=" --update"
sudo HEXCIRI_USER="$USER" "$0" --system-only ${YES:+ -y} $re_exec_flags --channel "$CHANNEL" ${KERNEL_PICK:+--kernel "$KERNEL_PICK"}
exec "$0" --user-only ${YES:+ -y} $re_exec_flags --channel "$CHANNEL"
fi

if $SYSTEM_ONLY; then
  (( EUID == 0 )) || { err "--system-only must run as root"; exit 1; }
  TARGET_USER="${HEXCIRI_USER:-${SUDO_USER:-}}"
  [[ -n $TARGET_USER && $TARGET_USER != root ]] || { err "--system-only needs HEXCIRI_USER set to a non-root user"; exit 1; }
  id "$TARGET_USER" &>/dev/null || { err "user $TARGET_USER does not exist"; exit 1; }
  as_user() { run su - "$TARGET_USER" -c "$*"; }

  # ── update mode skips first-install system work (channel/keyring/pacman/
  #    curated packages/AUR/zram/cache hook): those are personal state and must
  #    never be re-asserted on an update. Updates deploy files only. ──
  if ! $UPDATE_MODE; then
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
    niri xwayland-satellite noctalia kitty fish fuzzel zed opencode
    grim slurp wl-clipboard cliphist wtype playerctl brightnessctl mpv v4l-utils jq fzf ffmpeg
    gpu-screen-recorder
    mesa vulkan-icd-loader lib32-mesa lib32-vulkan-icd-loader
    libnotify gtk3 xdg-utils desktop-file-utils
    gtk4 gtksourceview5 poppler-glib bubblewrap ffmpegthumbnailer gst-libav gst-plugins-good graphene xdg-terminal-exec
    polkit-gnome gnome-keyring xdg-desktop-portal-gtk xdg-desktop-portal-gnome
    adw-gtk-theme
    networkmanager openssh sddm fastfetch starship noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd inetutils
    gnome-disk-utility imv mupdf libreoffice-fresh
    cups hplip unzip fprintd
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

  # ── yay (AUR helper): the AUR menu entries (hexciri-pkg-aur-install, the
  #    arch-updater AUR pass, hexciri-gaming's on-demand AUR pulls) all expect
  #    yay present, so fresh installs build yay-bin (prebuilt binary, no Rust
  #    rebuild) as the user and install as root — same boundary as brave. ──
  if ! pacman -Q yay-bin &>/dev/null; then
    info "building yay-bin (AUR, as $TARGET_USER)..."
    run rm -rf /tmp/hexciri-aur
    run mkdir -p /tmp/hexciri-aur
    run chown "$TARGET_USER:$TARGET_USER" /tmp/hexciri-aur
    as_user "cd /tmp/hexciri-aur && git clone -q https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg --noconfirm"
    run pacman -U --noconfirm /tmp/hexciri-aur/yay-bin/*.pkg.tar.zst
    run rm -rf /tmp/hexciri-aur
  fi

  # ── hide noisy utility desktop entries (avahi UI, hwloc, qt/v4l tooling) ──
  # avahi-discover, bssh, bvnc are LAN-discovery tools the average desktop user
  # never opens; lstopo is hwloc's hardware-topology viewer; qv4l2/qvidcap are
  # v4l-utils video-device debuggers; qt6ct is the Qt6 settings config GUI that
  # most users reach via their DE settings or the config file. They only exist
  # in the menu because the packages install plain .desktop files — mark them
  # NoDisplay so they vanish from app menus without uninstalling the packages.
  # Matches on the exact basename and refuses to touch anything else.
  info "hiding avahi/hwloc/qt/v4l utility entries from app menus..."
  for f in avahi-discover.desktop bssh.desktop bvnc.desktop lstopo.desktop \
           qv4l2.desktop qvidcap.desktop qt6ct.desktop; do
    d="/usr/share/applications/$f"
    if [[ -f $d ]] && grep -q '^NoDisplay=true' "$d"; then
      : # already curated
    elif [[ -f $d ]]; then
      run bash -c "printf 'NoDisplay=true\n' >> '$d'"
    else
      info "  $f absent (skipped)"
    fi
  done

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
  fi # ! $UPDATE_MODE

  # ── legacy purge: pre-symlink installs hard-copied every command to
  #    /usr/local/bin and mirrored themes/catalog/default into /usr/share/hexciri.
  #    The runtime is the repo now (~/.local/bin → repo/bin), so clear the stale
  #    root copies; the only /usr/local/bin entry kept is the single hexciri-sync
  #    symlink re-created below for the alpm hook. /usr/share/hexciri survives
  #    only for the root-owned boot-pin file. ──
  run rm -f /usr/local/bin/hexciri-*
  run rm -rf /usr/share/hexciri/themes /usr/share/hexciri/theme-sources \
    /usr/share/hexciri/default /usr/share/hexciri/VERSION

  # ── hexciri system sync: keep boot entries/plymouth/PAM/menu curated across
  #    package upgrades, which routinely clobber them (kernels land with no
  #    systemd-boot entry; mkinitcpio drops 'plymouth' from HOOKS; sddm heals
  #    /etc/pam.d/sddm; avahi/hwloc/v4l-utils/qt6ct restore NoDisplay'd
  #    .desktop files). The Exec path must stay a plain command that works
  #    without a TTY or user env — it runs as root inside the transaction. ──
  run mkdir -p /usr/share/libalpm/hooks
  run install -m644 "$REPO_DIR/default/alpm/hexciri-sync.hook" /usr/share/libalpm/hooks/hexciri-sync.hook
  # The one command the system runs itself (as root, no user env): keep a single
  # /usr/local/bin symlink into the repo checkout so it follows the runtime.
  run mkdir -p /usr/local/bin
  run ln -sfn "$REPO_DIR/bin/hexciri-sync" /usr/local/bin/hexciri-sync
  info "wrote /usr/share/libalpm/hooks/hexciri-sync.hook (PostTransaction hexciri sync)"

  # ── /usr/share/hexciri stays ONLY as the root-owned boot-pin location
  #    (hexciri-kernel / hexciri-gpu record the chosen boot default here; the
  #    alpm hook + updater read it back). The command runtime and theme catalog
  #    live in the repo clone + ~/.local/bin now — no mirror to keep in sync. ──
  run mkdir -p /usr/share/hexciri
  run mkdir -p /usr/share/pixmaps
  run cp -f "$REPO_DIR/branding/logo.png" /usr/share/pixmaps/hexciri.png

  if ! $UPDATE_MODE; then
  # ── services + SDDM (no disk encryption → the login gate lives at the sddm
  #    password/fingerprint prompt itself) ──
  run systemctl enable NetworkManager.service 2>/dev/null || true
  run systemctl enable sshd.service 2>/dev/null || true
  run systemctl enable sddm.service 2>/dev/null || true
  # SSH keys are generated on first start by sshd-keygen.service; enabling
  # without --now is intentional here (we're in the install chroot, no systemd
  # PID 1), so sshd comes up automatically on first real boot.
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

  # ── gnome-keyring: unlock the login keyring at sddm login via pam. Without
  #    this, the "Unlock Login Keyring" popup appears whenever the first app
  #    touches secrets. Deploy the full pam stack (backup-first, idempotent). ──
  if [[ ! -f /etc/pam.d/sddm ]] || ! grep -q 'pam_gnome_keyring.so' /etc/pam.d/sddm; then
    run cp -f /etc/pam.d/sddm "/etc/pam.d/sddm.bak.$(date +%s)" 2>/dev/null || true
    run cp -f "$REPO_DIR/default/pam/sddm" /etc/pam.d/sddm
    info "sddm login: wired pam_gnome_keyring (auto-unlocks 'login' keyring)"
  fi
  # fingerprint-first for sudo/su/login (system-auth also backs sddm via
  # system-login); sufficient → password still works when no print is present
  if [[ ! -f /etc/pam.d/system-auth ]] || ! grep -q 'pam_fprintd.so' /etc/pam.d/system-auth; then
    run cp -f /etc/pam.d/system-auth "/etc/pam.d/system-auth.bak.$(date +%s)" 2>/dev/null || true
    run cp -f "$REPO_DIR/default/pam/system-auth" /etc/pam.d/system-auth
    info "system-auth: fingerprint-first for sudo/su/login"
  fi
  # ── gnome-keyring: PIN the last known-good build. 50.0 has an unfixed
  #    upstream crash (SIGABRT in g_variant_new during concurrent Secret
  #    Service OpenSession/PKCS11 negotiation) that kills the PAM daemon and
  #    leaves a locked replacement → "unlock login keyring" popups. Parking
  #    48.0 with IgnorePkg removes the crashing code entirely — no masks, no
  #    dbus overrides: a healthy daemon stays the sole owner of
  #    org.freedesktop.secrets. Return to a clean upgrade once upstream ships
  #    a fixed 50.x (delete the IgnorePkg line below). ──
  if pacman -Q gnome-keyring 2>/dev/null | grep -q ' 50\.'; then
    gkr_pkg=/var/cache/pacman/pkg/gnome-keyring-1:48.0-1-x86_64.pkg.tar.zst
    if [[ ! -f $gkr_pkg ]]; then
      run curl -fLo "$gkr_pkg" "https://archive.archlinux.org/packages/g/gnome-keyring/gnome-keyring-1%3A48.0-1-x86_64.pkg.tar.zst"
    fi
    run pacman -U --noconfirm "$gkr_pkg"
    info "downgraded gnome-keyring to 48.0 (50.0 crashes; parked until upstream fixes it)"
  fi
  if ! grep -Eq '^IgnorePkg[[:space:]]*=.*gnome-keyring' /etc/pacman.conf; then
    # must live under [options]; appending at EOF lands in the last repo
    # section and pacman conflates directives with repo entries
    run sed -i '/^\[options\]/a IgnorePkg = gnome-keyring' /etc/pacman.conf
    info "parked gnome-keyring via IgnorePkg"
  fi
  fi # ! $UPDATE_MODE

  # ── SDDM theme (emblem + password greeter, Niri preferred) ──
  #    (update mode keeps your installed greeter — user-facing personalization)
  if ! $UPDATE_MODE && ! $DRY_RUN; then
    run mkdir -p /usr/share/sddm/themes/hexciri
    for f in Main.qml metadata.desktop theme.conf; do
      run cp -f "$REPO_DIR/branding/sddm/$f" /usr/share/sddm/themes/hexciri/$f
    done
    # hexciri's own greeter asset set (proven on this hardware)
    for f in logo.png lock.png lock-failed.png entry.png entry-failed.png bullet.png; do
      run cp -f "$REPO_DIR/branding/sddm/$f" /usr/share/sddm/themes/hexciri/$f
    done
    # Prefill the greeter's username field from the install user this session;
    # the SddmComponents user model can be empty/slow on a fresh first boot.
    printf '\nUsername=%s\n' "${TARGET_USER:-}" | run tee -a /usr/share/sddm/themes/hexciri/theme.conf >/dev/null
    run mkdir -p /etc/sddm.conf.d
    printf '[Theme]\nCurrent=hexciri\n' | run tee /etc/sddm.conf.d/10-hexciri-theme.conf >/dev/null
  fi

  # ── version stamp (hexciri-version uses git describe from the repo; the
  #    /usr/share/hexciri mirror is gone, so no brand is written here) ──

  # ── GPU autodetect + single-kernel policy (first-install only) ──
  #    Updates never touch the kernel: the boot kernel you chose is preserved;
  #    nothing reinstalls linux/linux-headers over a custom kernel or reasserts
  #    driver setup. ──
  if ! $UPDATE_MODE; then
  # ── GPU autodetect (runs as root here; installer reboots at the end, not mid-run) ──
  if ! $DRY_RUN; then
    # shellcheck disable=SC2086
    HEXCIRI_NO_REBOOT=1 hexciri-gpu -y ${KERNEL_PICK:+--kernel $KERNEL_PICK} \
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
      # self-heal a possibly-inherited corrupt mkinitcpio.conf before rebuilding
      run "$REPO_DIR/lib/initramfs.sh" repair /etc/mkinitcpio.conf
      rm -f /etc/mkinitcpio.conf.hexciri-changed
      mkinitcpio -P
    else
      warn "$custom_pkg did not install (custom kernels need bleeding) — keeping staged kernel"
    fi
  fi
  fi # ! $UPDATE_MODE

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

# ── commands → ~/.local/bin symlinks to the repo checkout being configured.
#    The repo clone IS the runtime: a later `git pull` (hexciri-update-hexciri /
#    hexciri-update-run) makes script + theme updates live immediately, so repo
#    sync never re-runs install.sh and needs no sudo. ln -sfn also sweeps up
#    renamed/removed commands and replaces any stale /usr/local/bin hard-copy
#    from a pre-symlink install (hexciri-util.fish already puts ~/.local/bin on
#    PATH). ──
run mkdir -p "$HOME/.local/bin"
info "linking hexciri commands → ~/.local/bin"
for f in "$REPO_DIR"/bin/*; do
  [[ -f $f ]] && run ln -sfn "$REPO_DIR/bin/$(basename "$f")" "$HOME/.local/bin/$(basename "$f")"
done
ok "commands linked"

# user branding art (system branding lives in /usr/share)
mkdir -p ~/.config/hexciri/branding
run cp -f "$REPO_DIR/branding/"*.png ~/.config/hexciri/branding/

# ── configs (backup-first) ──
deploy config/niri/config.kdl "$HOME/.config/niri/config.kdl"

# Monitor scaling ships preconfigured in config/niri/config.kdl (eDP-1 scale 2,
# mode/VRR commented) — no runtime detection, nothing to discover in a chroot.

deploy config/noctalia/config.toml "$HOME/.config/noctalia/config.toml"
run mkdir -p "$HOME/.config/fastfetch"
run cp -f "$REPO_DIR/branding/hexciri-nb.png" "$HOME/.config/fastfetch/hexciri-nb.png"
deploy config/fastfetch/config.jsonc "$HOME/.config/fastfetch/config.jsonc"
deploy config/starship/starship.toml "$HOME/.config/starship.toml"
deploy config/fish/conf.d/hexciri-starship.fish "$HOME/.config/fish/conf.d/hexciri-starship.fish"
deploy config/fish/conf.d/hexciri-aliases.fish "$HOME/.config/fish/conf.d/hexciri-aliases.fish"
deploy config/fish/conf.d/hexciri-util.fish "$HOME/.config/fish/conf.d/hexciri-util.fish"
mkdir -p "$HOME/.config/hexciri/hooks/theme-set.d" "$HOME/.config/hexciri/hooks/font-set.d" "$HOME/.config/hexciri/hooks/lib"
run cp -f "$REPO_DIR"/hooks/theme-set.d/*.sh "$HOME/.config/hexciri/hooks/theme-set.d/"
run cp -f "$REPO_DIR"/hooks/font-set.d/*.sh "$HOME/.config/hexciri/hooks/font-set.d/"
run cp -f "$REPO_DIR"/hooks/lib/*.sh "$HOME/.config/hexciri/hooks/lib/"

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
# ── where the source repo lives (hexciri-reinstall / hexciri-update-hexciri) ──
mkdir -p "$HOME/.local/state/hexciri"
run bash -c "printf '%s' '$REPO_DIR' > '$HOME/.local/state/hexciri/repo-path'"
for kv in "terminal=kitty" "shell=fish" "browser=brave-origin" "files=strata" "editor=zed" "agent=opencode" "images=imv"; do
  k="${kv%%=*}"; v="${kv#*=}"
  [[ -f $HOME/.local/state/hexciri/defaults/$k ]] || run bash -c "printf '%s' '$v' > '$HOME/.local/state/hexciri/defaults/$k'"
done
# UI defaults are a FIRST-INSTALL-ONLY setup (like the theme seed): afterwards
# they are user-controlled preferences, so updates must never re-assert them.
# Marker → set once at first run; a user who re-runs install.sh to wipe state
# starts fresh again.
UI_MARKER="$HOME/.local/state/hexciri/ui-defaults-applied"

if [[ ! -f $UI_MARKER ]]; then
  for d in brave-origin.desktop com.brave.Origin.desktop brave-origin-beta.desktop; do
    if [[ -f /usr/share/applications/$d || -f ~/.local/share/applications/$d ]]; then
      run xdg-settings set default-web-browser "$d" 2>/dev/null || true; break
    fi
  done
  run xdg-mime default io.github.lgse.Strata.desktop inode/directory 2>/dev/null || true
  # imv ships NoDisplay=true, which hides it (and Brave wins image defaults by
  # default). Ship a displayable user-level override with a bundled icon (imv's
  # own Icon=multimedia-photo-viewer doesn't exist on Arch) and pin image/* to
  # imv so files open in the image viewer instead of the browser.
  if [[ -f /usr/share/applications/imv.desktop || -f ~/.local/share/applications/imv.desktop ]]; then
    mkdir -p "$HOME/.local/share/applications"
    mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
    run cp -f "$REPO_DIR/branding/imv.png" "$HOME/.local/share/icons/hicolor/256x256/apps/imv.png" 2>/dev/null || true
    run cp -f "$REPO_DIR/branding/imv-dir.png" "$HOME/.local/share/icons/hicolor/256x256/apps/imv-dir.png" 2>/dev/null || true
    run gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" &>/dev/null || true
    run awk '/^NoDisplay=/{next} {print}' /usr/share/applications/imv.desktop | sed 's|^Icon=.*|Icon=imv|' > "$HOME/.local/share/applications/imv.desktop" 2>/dev/null || true
    run awk '/^NoDisplay=/{next} {print}' /usr/share/applications/imv-dir.desktop | sed 's|^Icon=.*|Icon=imv-dir|' > "$HOME/.local/share/applications/imv-dir.desktop" 2>/dev/null || true
    for mt in image/png image/x-png image/jpeg image/jpg image/pjpeg image/gif image/bmp image/x-bmp image/webp image/avif image/heif image/tiff image/tiff-fx image/svg+xml image/x-farbfeld image/jxl image/qoi image/*; do
      run xdg-mime default imv.desktop "$mt" 2>/dev/null || true
    done
  fi
  # hplip's HP Scan entry points Icon at the Ubuntu-only Humanity theme, which
  # vanilla Arch doesn't have — shadow it with a user-level copy that uses an
  # icon that actually exists (Adwaita scanner svg).
  if [[ -f /usr/share/applications/hp-uiscan.desktop ]]; then
    mkdir -p "$HOME/.local/share/applications"
    run sed 's|^Icon=.*|Icon=/usr/share/icons/Adwaita/scalable/devices/scanner.svg|' /usr/share/applications/hp-uiscan.desktop > "$HOME/.local/share/applications/hp-uiscan.desktop" 2>/dev/null || true
  fi
  run touch "$UI_MARKER"
fi

# ── Strata: per-user GitHub release install (~/.local/bin) instead of the
#    [omarchy] repo package (which lags upstream's near-daily releases).
#    First-install-only — updates leave it alone; hexciri-strata-install
#    re-checks at every login via spawn-at-startup. ──
if ! $UPDATE_MODE && (( $(id -u) != 0 )) && [[ $DRY_RUN == false ]]; then
  if ! (hexciri-strata-install 2>/dev/null); then
    warn "strata install deferred (offline?) — will run again at first login"
  fi
fi

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
# First-install-only (see UI_MARKER above) — re-asserting gtk-theme /
# color-scheme on every update would stomp a user's light-mode / theme choice.
if ! $UPDATE_MODE && [[ ! -f $UI_MARKER ]] && command -v gsettings >/dev/null 2>&1 && [[ -d /usr/share/themes/adw-gtk3 ]]; then
  run gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3 2>/dev/null || true
  run gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
  info "gtk: adw-gtk-theme (dark libadwaita)"
fi

# ── audio: pipewire session via user units (vanilla Arch way; Noctalia pulls
#    the libs, these are the daemons that make sound actually route). Update
#    mode leaves your audio enablement alone (personal state). ──
if ! $UPDATE_MODE && command -v pipewire >/dev/null 2>&1; then
  systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
  info "audio: enabled user units (pipewire.socket + pulse + wireplumber)"
fi

# ── seed maiden theme ──
# Non-fatal: runs inside the chroot user phase where no session/compositor is
# up, so it can die partway (theme tree or noctalia palette patch missing).
# hexciri-theme-ensure re-applies it at first login; a failure here must never
# abort the rest of the user phase.
# First install only: once a theme is applied (theme.name exists), updates must
# NOT re-seed — that would reset a user's chosen theme/personalization. Theme
# changes go through the Themes menu (hexciri-theme-set), like noctarchy.
if ! $DRY_RUN && [[ ! -e $HOME/.local/state/hexciri/current/theme.name ]]; then
  HEXCIRI_PATH="$REPO_DIR" hexciri-theme-set sakurazuki \
    || warn "theme seed incomplete — hexciri-theme-ensure will re-apply at first login"
fi

# ── seed the shipped Omarchy theme set ──
# First install only: clone the Omarchy monorepo subsettee into the state dir
# and symlink the 22 default themes into ~/.config/hexciri/themes. Kept current
# by the repo sync (hexciri-update-hexciri → hexciri-theme-omarchy); the extras
# list is seeded separately by the user via the Extra themes menu
# (hexciri-theme-extras — it never touches Omarchy defaults). Non-fatal. ──
if [[ -f "$REPO_DIR/config/theme-sources/omarchy.conf" ]]; then
  if [[ ! -e $HOME/.local/state/hexciri/current/theme.name ]]; then
    HEXCIRI_PATH="$REPO_DIR" "$REPO_DIR/bin/hexciri-theme-omarchy" \
      || warn "Omarchy theme set not seeded — the repo sync will seed it on the next update"
  fi
fi

# ── noctalia arch-updater plugin presets: plugin-level settings are owned by
#    the state dir, so seed the missing keys of the preset into settings.toml
#    (GUI overrides win — existing values are never touched). kitty + the
#    native update_cmd give a real PTY, so no service.luau patch/guard is
#    required on any plugin version that honors these keys.
#    First-install-only: once seeded it is never touched again. ──
if ! $UPDATE_MODE; then
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
fi # ! $UPDATE_MODE

# ── noctalia wallpaper directory: point the wallpaper picker at the active
#    theme's backgrounds. Noctalia's settings.toml (GUI overrides) wins over
#    config.toml, so the repo's config.toml `directory` alone never holds on a
#    fresh box — seed the key so the default actually sticks. Once present it
#    is never re-asserted (the user re-picking a folder is their choice).
#    The path is stable across theme switches (current/theme is re-copied in
#    place by hexciri-theme-set), so no per-theme re-sync is needed. ──
if ! $UPDATE_MODE; then
WP_SEED_DIR="$HOME/.local/state/noctalia/settings.toml"
if [[ $DRY_RUN == true ]]; then
  info "[dry-run] seed noctalia wallpaper directory → active theme's backgrounds"
elif grep -q '^directory[[:space:]]*=' "$WP_SEED_DIR" 2>/dev/null; then
  ok "noctalia wallpaper directory present (left untouched)"
else
  printf '\n[wallpaper]\nenabled = true\ndirectory = "%s"\n' \
    "$HOME/.local/state/hexciri/current/theme/backgrounds" >> "$WP_SEED_DIR"
  info "seeded noctalia wallpaper directory → active theme's backgrounds"
fi
fi # ! $UPDATE_MODE

echo ""
if $UPDATE_MODE; then
  ok "hexciri update applied (channel: $CHANNEL)"
  info "deployed new/changed files — packages, kernels, services and personal config left untouched"
else
  ok "hexciri installed (channel: $CHANNEL, theme: sakurazuki)"
  info "configs: ~/.config/niri/config.kdl ~/.config/noctalia/config.toml (backups in $bak)"
  info "reboot → SDDM greeter → password → Niri (Mod+K for keybindings)"
fi
