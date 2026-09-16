#!/bin/bash
# hexciri dotfiles bring-up — CachyOS + Niri, then this.
#
#   curl -LO https://hexciri.dirty.pizza/install.sh
#   sh install.sh
#
# or: git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
#     ~/.local/opt/hexciri/install.sh [--yes]
#
# --yes/-y answers the update deploy's "Run system update?" with yes
# (non-interactive bring-up). The reboot offer always still asks.
#
# One-shot CachyOS+Niri bring-up: clone, link controllers, root sync pass,
# one-time app swap, per-user Brave Origin, then the update deploy
# (keybinds adapt, kitty seed, themes). Idempotent; safe to re-run.
# Afterwards sync never touches packages — later manual changes stick.
set -euo pipefail

UPDATE_YES=""
for _a in "$@"; do
  case "$_a" in
    --yes|-y) UPDATE_YES="--yes" ;;
    -h|--help) echo "usage: install.sh [--yes]"; exit 0 ;;
    *) echo "install.sh: unknown arg: $_a (usage: install.sh [--yes])" >&2; exit 1 ;;
  esac
done
unset _a

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
# App set from the list: hexciri's apps in, replaced stock ones out (with
# their config dirs, but only once something is actually absent). The list
# (config/apps/apps.list) is the source of truth — it applies here and via
# `hexciri-apps sync`. The framework sync (hexciri-sync / hexciri-update self)
# still never touches packages (except the tiny layer-critical subset it
# self-heals), so anything you never listed is never reverted or re-applied.
# Best-effort, never fatal.
# NOTE: removal order matters — the CachyOS niri meta goes first so the portal
# it pins comes out cleanly behind it. vim is force-removed
# below (held by the deliberately kept cachyos-zsh-config; -Rdd breaks only
# that declared dep, reinstalling vim undoes it). fuzzel + gtksourceview5 are
# layer needs (menu would be dead without fuzzel; gtksourceview5 covers
# text-viewer libs).
# NOTE: polkit-gnome is a layer need too — niri autostart spawns its agent
# binary, and without it pkexec apps (btrfs-assistant, gparted) silently
# never open: no agent, no password dialog.
# NOTE: adw-gtk-theme ships the adw-gtk3-dark base theme the GTK hook sets
# (hooks/theme-set.d/10-gtk.sh) — without it GTK3/plain-GTK4 apps fall back
# to built-in styling and look unthemed; gtk.css is only an overlay on top.
# NOTE: xdg-terminal-exec is NOT in CachyOS repos (aborts the whole transaction
# when named) — blades fall back to hexciri-terminal, which needs only kitty.
# The swap reads config/apps/apps.list ([pacman] + [aur]); your copy at
# ~/.config/hexciri/apps/apps.list overrides the shipped file, so added lines
# install here and via `hexciri-apps sync` — and deleted lines are removed
# (tracked in ~/.local/state/hexciri/apps-managed; unlisted packages are never
# touched). brave-origin-bin ([aur]) installs below via yay/paru, not pacman.
_hexciri_apps_file="$HOME/.config/hexciri/apps/apps.list"
[[ -f $_hexciri_apps_file ]] || _hexciri_apps_file="$REPO/config/apps/apps.list"
_hexciri_wants=""; _hexciri_listed=" "
if [[ -f $_hexciri_apps_file ]]; then
  _sec=""
  while IFS= read -r _line || [[ -n $_line ]]; do
    _line="${_line%%#*}"
    _line="$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z $_line ]] && continue
    if [[ $_line =~ ^\[(.*)\]$ ]]; then
      _sec="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
      continue
    fi
    case "$_sec" in pacman|aur) ;; *) continue ;; esac
    _pkg="${_line%%[[:space:]]*}"
    [[ -n $_pkg ]] || continue
    _hexciri_listed+="$_pkg "
    [[ $_sec == pacman ]] && _hexciri_wants+="$_pkg "
  done < "$_hexciri_apps_file"
  unset _sec _line _pkg
fi
# Fallback when the list is missing (e.g. partial checkout) — mirrors the
# shipped config/apps/apps.list so bring-up still works.
[[ -n $_hexciri_wants ]] || _hexciri_wants="kitty zed opencode nautilus localsend gtksourceview5 fuzzel gpu-screen-recorder tesseract imv libqalculate polkit-gnome mupdf gnome-keyring seahorse adw-gtk-theme "
# One-time stock removals (not the list — replaced CachyOS defaults, always
# safe to attempt; kept when something still needs them).
_hexciri_stock_rm="cachyos-niri-noctalia xdg-desktop-portal-gnome alacritty firefox meld cachyos-micro-settings micro"
_hexciri_purge="alacritty:$HOME/.config/alacritty firefox:$HOME/.mozilla meld:$HOME/.config/meld micro:$HOME/.config/micro"
if command -v pacman >/dev/null 2>&1; then
  info "one-time app swap (wants from $(basename "$_hexciri_apps_file") + stock removals)"
  # shellcheck disable=SC2086
  sudo pacman -S --needed --noconfirm $_hexciri_wants 2>&1 | sed 's/^/  /' || \
    info "wants skipped/partial — install by hand: pacman -S $_hexciri_wants"
  for _p in $_hexciri_stock_rm; do
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
  # List-truth reconcile: managed packages deleted from the list go too.
  # (No-op on fresh installs — no managed state yet.)
  _hexciri_state="$HOME/.local/state/hexciri/apps-managed"
  if [[ -f $_hexciri_state ]]; then
    while IFS= read -r _p || [[ -n $_p ]]; do
      _p="${_p%%#*}"; _p="$(printf '%s' "$_p" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n $_p ]] || continue
      case "$_hexciri_listed" in *" $_p "*) continue ;; esac
      pacman -Q "$_p" >/dev/null 2>&1 || continue
      info "removing $_p (deleted from the apps list)"
      if [[ $_p == vim ]]; then
        sudo pacman -Rdd --noconfirm vim 2>&1 | sed 's/^/  /' && rm -rf "$HOME/.vim" "$HOME/.viminfo" && \
          info "removed vim" || info "kept vim (removal failed)"
      elif sudo pacman -Rns --noconfirm "$_p" 2>&1 | sed 's/^/  /'; then
        info "removed $_p"
      else
        info "kept $_p (something still needs it)"
      fi
    done < "$_hexciri_state"
    unset _hexciri_listed
  fi
  unset _p _m _pkg _dir _hexciri_state
fi
unset _hexciri_wants _hexciri_listed _hexciri_stock_rm _hexciri_purge _hexciri_apps_file
# Nautilus is the default file manager (pacman package, in _hexciri_wants so a
# fresh box gets it even if the removed niri meta took it). A stale
# Hidden=true override from the Strata era would keep it out of menus, so drop
# it; the stock desktop entry applies again.
if [[ -f $HOME/.local/share/applications/org.gnome.Nautilus.desktop ]]; then
  rm -f "$HOME/.local/share/applications/org.gnome.Nautilus.desktop" && \
    info "unhid nautilus launcher entry (Strata-era override removed)"
fi
xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true
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
# AUR wants ([aur] in the apps list). Installs via yay/paru as you, then drops
# the brave-bin stand-in once origin is present. Best-effort, never fatal.
# (`hexciri-apps sync` re-runs this same list logic on demand.)
_hexciri_aur_file="$HOME/.config/hexciri/apps/apps.list"
[[ -f $_hexciri_aur_file ]] || _hexciri_aur_file="$REPO/config/apps/apps.list"
_hexciri_aur_pkgs=""
if [[ -f $_hexciri_aur_file ]]; then
  _sec=""
  while IFS= read -r _line || [[ -n $_line ]]; do
    _line="${_line%%#*}"
    _line="$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z $_line ]] && continue
    if [[ $_line =~ ^\[(.*)\]$ ]]; then
      _sec="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
      continue
    fi
    [[ $_sec == aur ]] || continue
    _hexciri_aur_pkgs+="${_line%%[[:space:]]*} "
  done < "$_hexciri_aur_file"
  unset _sec _line
fi
[[ -n $_hexciri_aur_pkgs ]] || _hexciri_aur_pkgs="brave-origin-bin "
if command -v brave-origin >/dev/null 2>&1 && [[ $_hexciri_aur_pkgs == *"brave-origin-bin"* ]]; then
  info "Brave Origin already present — keeping it, no Brave stand-in wanted"
  # strip the satisfied want so the helper step below only handles the rest
  _hexciri_aur_pkgs="$(printf '%s' "$_hexciri_aur_pkgs" | tr ' ' '\n' | grep -vx 'brave-origin-bin' | tr '\n' ' ')"
fi
if [[ -n $(printf '%s' "$_hexciri_aur_pkgs" | tr -d ' ') ]]; then
  _aur=""
  for _h in yay paru; do command -v "$_h" >/dev/null 2>&1 && { _aur=$_h; break; }; done
  if [[ -n $_aur ]]; then
    info "installing AUR wants via $_aur: $_hexciri_aur_pkgs"
    # shellcheck disable=SC2086
    "$_aur" -S --needed --noconfirm $_hexciri_aur_pkgs 2>&1 | sed 's/^/  /' || \
      info "AUR wants skipped — run by hand: $_aur -S $_hexciri_aur_pkgs"
  else
    info "AUR wants skipped (no yay/paru) — run by hand: yay -S $_hexciri_aur_pkgs"
  fi
fi
unset _aur _h _hexciri_aur_pkgs _hexciri_aur_file
# Record the managed set (full [pacman]+[aur] union — including any already
# satisfied want stripped above) so `hexciri-apps sync` can tell a deleted
# line from a package it never managed.
if [[ -f $HOME/.config/hexciri/apps/apps.list ]]; then _hexciri_state_src="$HOME/.config/hexciri/apps/apps.list"
else _hexciri_state_src="$REPO/config/apps/apps.list"; fi
if [[ -f $_hexciri_state_src ]]; then
  mkdir -p "$HOME/.local/state/hexciri"
  _hexciri_sec=""; : > "$HOME/.local/state/hexciri/apps-managed.tmp"
  while IFS= read -r _line || [[ -n $_line ]]; do
    _line="${_line%%#*}"
    _line="$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z $_line ]] && continue
    if [[ $_line =~ ^\[(.*)\]$ ]]; then
      _hexciri_sec="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
      continue
    fi
    case "$_hexciri_sec" in pacman|aur) printf '%s\n' "${_line%%[[:space:]]*}" >> "$HOME/.local/state/hexciri/apps-managed.tmp" ;; esac
  done < "$_hexciri_state_src"
  LC_ALL=C sort -u "$HOME/.local/state/hexciri/apps-managed.tmp" | grep -v '^$' > "$HOME/.local/state/hexciri/apps-managed" || true
  rm -f "$HOME/.local/state/hexciri/apps-managed.tmp"
  unset _hexciri_sec _line
fi
unset _hexciri_state_src
if command -v brave-origin >/dev/null 2>&1 && pacman -Q brave-bin >/dev/null 2>&1; then
  info "removing Brave stand-in (Origin is present)"
  sudo pacman -Rns --noconfirm brave-bin 2>&1 | sed 's/^/  /' || \
    info "kept brave-bin (removal failed) — remove by hand if unwanted"
fi
# Image defaults: the browser claims image/* on install, so pin them back to
# imv (only browser-owned slots are touched — a deliberate viewer pick stays).
# Best-effort, never fatal; re-runs heal whatever the browser re-stole.
if [[ -x "$REPO/bin/hexciri-imv-defaults" ]]; then
  info "pinning image/* defaults to imv"
  HEXCIRI_PATH="$REPO" "$REPO/bin/hexciri-imv-defaults" 2>&1 | sed 's/^/  /' || \
    info "imv defaults skipped — pick System > Default Apps > Images by hand"
fi
# PDF default: nothing ships a reader, so PDFs fall through to the browser.
# Same healing-helper shape as images (browser-owned slots only).
if [[ -x "$REPO/bin/hexciri-pdf-defaults" ]]; then
  info "pinning application/pdf default to mupdf"
  "$REPO/bin/hexciri-pdf-defaults" 2>&1 | sed 's/^/  /' || \
    info "pdf default skipped — set it by hand"
fi
# Share-menu sender: localsend >= 1.18 ships localsend-cli itself, so keeping
# localsend current delivers it — nothing extra to install. The blades resolve
# localsend-cli || jocalsend live and fail with a clear message otherwise.
# Theme content (one-time here; afterwards Update > Themes owns it — the
# framework sync deliberately never pulls themes, so system updates stay quiet).
# Best-effort, never fatal.
if [[ -x "$REPO/bin/hexciri-theme-omarchy" ]]; then
  info "syncing omarchy theme defaults"
  HEXCIRI_PATH="$REPO" "$REPO/bin/hexciri-theme-omarchy" 2>&1 | sed 's/^/  /' || \
    info "omarchy themes skipped — run them from Update > Themes later"
fi
if [[ -x "$REPO/bin/hexciri-theme-extras" ]]; then
  info "syncing extra themes"
  HEXCIRI_PATH="$REPO" "$REPO/bin/hexciri-theme-extras" --run sync 2>&1 | sed 's/^/  /' || \
    info "extra themes skipped — run them from Update > Themes later"
fi
# Update deploy (one-time here; afterwards run it by hand or from the menu):
# keybinds adapt, kitty seed, themes, then the full system update it offers.
# Runs attached to the terminal (no pipe): its "Run system update? [y/N]"
# prompt is written without a trailing newline, so piping stdout through sed
# swallows it and the install looks hung at an invisible question.
if [[ -x "$REPO/bin/hexciri-update" ]]; then
  info "update deploy via hexciri-update (keybinds, kitty, themes)"
  # shellcheck disable=SC2086
  "$REPO/bin/hexciri-update" $UPDATE_YES || \
    info "update skipped — run 'hexciri-update' by hand later"
fi
info "done — pick a theme ('hexciri-theme set'), then relogin. Update: git -C $REPO pull && sh $REPO/install.sh"
