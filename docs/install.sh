#!/bin/bash
# hexciri dotfiles bring-up — CachyOS + a WM, then this.
#
#   curl -LO https://hexciri.dirty.pizza/install.sh
#   sh install.sh
#
# or: git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
#     ~/.local/opt/hexciri/install.sh
#
# One-shot CachyOS+Niri bring-up: clone, link controllers, root sync pass,
# one-time app swap, per-user Strata + Brave Origin, then the update deploy
# (keybinds adapt, kitty seed, themes). Idempotent; safe to re-run.
# Afterwards sync never touches packages — later manual changes stick.
set -euo pipefail

REPO_URL="https://github.com/Deoxizn/hexciri.git"
DEFAULT_REPO="$HOME/.local/opt/hexciri"

info() { echo "hexciri: $*"; }

# Resolve repo: script's dir if it holds bin/, else clone/default.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -d "$SCRIPT_DIR/bin" && -x "$SCRIPT_DIR/bin/hexciri-sync" ]]; then
  REPO="$SCRIPT_DIR"
else
  REPO="${HEXCIRI_REPO:-$DEFAULT_REPO}"
  if [[ ! -x "$REPO/bin/hexciri-sync" ]]; then
    info "cloning into $REPO"
    mkdir -p "$(dirname "$REPO")"
    git clone "$REPO_URL" "$REPO"
  fi
fi

# Link sweep (same step hexciri-sync owns) so sync itself is on PATH first.
mkdir -p "$HOME/.local/bin"
for f in "$REPO"/bin/*; do
  [[ -f $f && -x $f ]] || continue
  ln -sfn "$f" "$HOME/.local/bin/$(basename "$f")"
done
info "linked controllers into ~/.local/bin"

# Delegate the re-apply; best-effort (sync may need interactive/root steps).
if [[ -x "$REPO/bin/hexciri-sync" ]]; then
  info "re-applying layer via hexciri-sync"
  HEXCIRI_REPO="$REPO" "$REPO/bin/hexciri-sync" || info "sync returned non-zero; re-run after reboot"
fi
# Root pass: ufw/sshd/hides/hook need root. Prompts once here; falls back to
# a manual `sudo hexciri-sync` if sudo isn't available.
if [[ -x "$REPO/bin/hexciri-sync" ]]; then
  info "root pass via hexciri-sync (ufw, sshd, menu hides)"
  sudo HEXCIRI_REPO="$REPO" "$REPO/bin/hexciri-sync" 2>&1 | sed 's/^/  /' || \
    info "root pass skipped — run 'sudo $REPO/bin/hexciri-sync' by hand later"
fi
# One-time light app swap: hexciri's apps in, replaced stock ones out (with
# their config dirs, but only once something is actually absent). Runs here at
# install and nowhere else — sync never touches packages, so later manual
# changes are never reverted or re-applied. Best-effort, never fatal.
# NOTE: removal order matters — the CachyOS niri meta goes first so the portal
# it pins, then nautilus, come out cleanly behind it. vim is force-removed
# below (held by the deliberately kept cachyos-zsh-config; -Rdd breaks only
# that declared dep, reinstalling vim undoes it). fuzzel + gtksourceview5 are
# layer needs (menu would be dead without fuzzel; strata won't launch without
# the lib).
# NOTE: xdg-terminal-exec is NOT in CachyOS repos (aborts the whole transaction
# when named) — blades fall back to hexciri-terminal, which needs only kitty.
_hexciri_wants="kitty zed opencode localsend gtksourceview5 fuzzel gpu-screen-recorder tesseract imv libqalculate"
_hexciri_removals="cachyos-niri-noctalia xdg-desktop-portal-gnome nautilus alacritty firefox meld cachyos-micro-settings micro"
_hexciri_purge="alacritty:$HOME/.config/alacritty firefox:$HOME/.mozilla meld:$HOME/.config/meld micro:$HOME/.config/micro nautilus:$HOME/.config/nautilus"
if command -v pacman >/dev/null 2>&1; then
  info "one-time app swap (wants + removals)"
  sudo pacman -S --needed --noconfirm $_hexciri_wants 2>&1 | sed 's/^/  /' || \
    info "wants skipped/partial — install by hand: pacman -S $_hexciri_wants"
  for _p in $_hexciri_removals; do
    pacman -Q "$_p" >/dev/null 2>&1 || continue
    if sudo pacman -Rns --noconfirm "$_p" 2>&1 | sed 's/^/  /'; then
      info "removed $_p"
    else
      info "kept $_p (something still needs it)"
    fi
  done
  for _m in $_hexciri_purge; do
    _pkg="${_m%%:*}"; _dir="${_m#*:}"
    pacman -Q "$_pkg" >/dev/null 2>&1 || rm -rf "$_dir"
  done
  if pacman -Q vim >/dev/null 2>&1; then
    info "removing vim (forced: breaks only cachyos-zsh-config's declared dep)"
    if sudo pacman -Rdd --noconfirm vim 2>&1 | sed 's/^/  /'; then
      rm -rf "$HOME/.vim" "$HOME/.viminfo"
      info "removed vim"
    else
      info "kept vim (forced removal failed)"
    fi
  fi
  unset _p _m _pkg _dir
fi
unset _hexciri_wants _hexciri_removals _hexciri_purge
# Per-user Strata file manager (GitHub release; sets itself default for
# inode/directory + file chooser). Best-effort: offline boxes still finish.
if [[ -x "$REPO/bin/hexciri-setup" ]]; then
  info "installing Strata file manager (default)"
  "$REPO/bin/hexciri-setup" strata 2>&1 | sed 's/^/  /' || info "Strata skipped (offline?) — run 'hexciri-setup strata' later"
fi
# AUR helper bootstrap (one-time): Brave Origin needs yay or paru, and a
# fresh box has neither. Builds yay via makepkg (needs base-devel+git).
# Best-effort: without it, AUR steps below print their manual fallback.
if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
  if command -v pacman >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    info "bootstrapping yay (AUR helper)"
    sudo pacman -S --needed --noconfirm base-devel git 2>&1 | sed 's/^/  /' || true
    rm -rf /tmp/hexciri-yay && git clone https://aur.archlinux.org/yay.git /tmp/hexciri-yay 2>&1 | sed 's/^/  /' || true
    ( cd /tmp/hexciri-yay 2>/dev/null && makepkg -si --noconfirm 2>&1 | sed 's/^/  /' ) || \
      info "yay bootstrap skipped — install an AUR helper by hand for Brave Origin"
  else
    info "yay bootstrap skipped (no pacman/git) — install an AUR helper by hand for Brave Origin"
  fi
fi
# Brave Origin (not Brave): the hexciri browser. One-time installer step —
# sync never touches packages. Installs via yay/paru as you, then drops the
# brave-bin stand-in once origin is present. Best-effort, never fatal.
if command -v brave-origin >/dev/null 2>&1; then
  info "Brave Origin already present — keeping it, no Brave stand-in wanted"
else
  _aur=""
  for _h in yay paru; do command -v "$_h" >/dev/null 2>&1 && { _aur=$_h; break; }; done
  if [[ -n $_aur ]]; then
    info "installing Brave Origin (via $_aur)"
    "$_aur" -S --needed --noconfirm brave-origin-bin 2>&1 | sed 's/^/  /' || \
      info "Brave Origin skipped — run 'yay -S brave-origin-bin' by hand later"
  else
    info "Brave Origin skipped (no yay/paru) — run 'yay -S brave-origin-bin' by hand later"
  fi
fi
if command -v brave-origin >/dev/null 2>&1 && pacman -Q brave-bin >/dev/null 2>&1; then
  info "removing Brave stand-in (Origin is present)"
  sudo pacman -Rns --noconfirm brave-bin 2>&1 | sed 's/^/  /' || \
    info "kept brave-bin (removal failed) — remove by hand if unwanted"
fi
# Share-menu sender: localsend >= 1.18 ships localsend-cli itself, so keeping
# localsend current delivers it — nothing extra to install. The blades resolve
# localsend-cli || jocalsend live and fail with a clear message otherwise.
# Update deploy (one-time here; afterwards run it by hand or from the menu):
# keybinds adapt, kitty seed, themes, then the full system update it offers.
if [[ -x "$REPO/bin/hexciri-update" ]]; then
  info "update deploy via hexciri-update (keybinds, kitty, themes)"
  "$REPO/bin/hexciri-update" 2>&1 | sed 's/^/  /' || \
    info "update skipped — run 'hexciri-update' by hand later"
fi
info "done — pick a theme ('hexciri-theme set'), then relogin. Update: git -C $REPO pull && sh $REPO/install.sh"
