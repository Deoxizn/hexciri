#!/bin/bash
# hexciri dotfiles bring-up — CachyOS (Niri or Hyprland), then this.
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
# One-shot CachyOS bring-up: clone, link controllers, root sync pass,
# one-time app swap, per-user Brave Origin, then the update deploy
# (keybinds adapt — the WM is auto-detected via hexciri-session — kitty seed,
# themes). Idempotent; safe to re-run.
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
# One-time app swap: hexciri's apps in, replaced stock ones out (with
# their config dirs, but only once something is actually absent). The wants
# below are hardcoded — there is no list to curate. The framework sync
# (hexciri-sync / hexciri-update self) still never touches packages (except
# the tiny layer-critical subset it self-heals: polkit-gnome gnome-keyring
# adw-gtk-theme nautilus brightnessctl playerctl fwupd), so your later manual changes stick.
# Best-effort, never fatal.
# NOTE: removal order matters — the CachyOS niri meta goes first so the portal
# it pins comes out cleanly behind it. vim is force-removed
# below (held by the deliberately kept cachyos-zsh-config; -Rdd breaks only
# that declared dep, reinstalling vim undoes it). fuzzel + gtksourceview5 are
# layer needs (menu would be dead without fuzzel; gtksourceview5 covers
# text-viewer libs).
# hexciri could not open. NOTE: polkit-gnome is a layer need too — the
# niri/hyprland autostarts both spawn its agent.
# binary, and without it pkexec apps (btrfs-assistant, gparted) silently
# never open: no agent, no password dialog.
# NOTE: brightnessctl + playerctl are layer needs too — niri keybinds spawn
# them for XF86MonBrightness* / XF86AudioPlay/Next/Prev (Framework F7/F8 +
# media keys). Without them brightness + media keys are dead while volume
# (wpctl) keeps working.
# NOTE: adw-gtk-theme ships the adw-gtk3-dark base theme the GTK hook sets
# (hooks/theme-set.d/10-gtk.sh) — without it GTK3/plain-GTK4 apps fall back
# to built-in styling and look unthemed; gtk.css is only an overlay on top.
# NOTE: fwupd is a layer need too — Update > Firmware runs fwupdmgr update,
# and without it the blade fails with "command not found".
# NOTE: xdg-terminal-exec is NOT in CachyOS repos (aborts the whole transaction
# when named) — blades fall back to hexciri-terminal, which needs only kitty.
# brave-origin-bin installs below via yay/paru, not pacman.
# NOTE: mpv is the default video player — the vlc plugin stack
# (vlc-plugins-all) is removed below; nothing in the layer references it.
# NOTE: cachyos-wallpapers is removed below too — Noctalia shows theme
# backgrounds (plus ~/.config/hexciri/wallpapers), never that pack.
# NOTE: noctalia is a layer need too — the bar, lock screen, launcher and
# notifications are all the shell; CachyOS preinstalls it via the WM meta,
# but a meta removal orphans it and leaves a gray compositor with no shell.
# Explicit here (and in the layer heal + WM switch) so it is never an orphan.
_hexciri_wants="kitty zed opencode localsend fuzzel gpu-screen-recorder tesseract mpv libqalculate polkit-gnome zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb gnome-keyring seahorse adw-gtk-theme brightnessctl playerctl fwupd jq cliphist noctalia "
# Per-WM-native file manager / image viewer: install hexciri's pick only when
# no file manager / viewer serves the box. Hyprland takes strata (per-user
# release, installed below); niri keeps nautilus. qview/imv unchanged. Presence-gated, not WM-gated, so minimal spins stay working.
# WM resolves via hexciri-session (live session → installed compositor →
# niri default; HXC_WM env overrides for testing/bring-up).
_hexciri_install_wm="$("$REPO/bin/hexciri-session" wm 2>/dev/null || echo niri)"
if ! command -v nemo >/dev/null 2>&1 && ! command -v nautilus >/dev/null 2>&1 && ! command -v dolphin >/dev/null 2>&1 && ! command -v thunar >/dev/null 2>&1; then
  if [[ $_hexciri_install_wm == hyprland ]]; then
    _hexciri_wants+="nemo "
  else
    _hexciri_wants+="nautilus "
  fi
fi
command -v qview >/dev/null 2>&1 || _hexciri_wants+="imv "
# KDE platform theme plugin (dolphin reads KDE color schemes ONLY through
# it; ships as an optional dolphin dep). Needed wherever dolphin is kept
# (legacy picks — strata is the hyprland default now).
if command -v dolphin >/dev/null 2>&1 && ! pacman -Q frameworkintegration >/dev/null 2>&1; then
  _hexciri_wants+="frameworkintegration "
fi
# One-time stock removals (not the list — replaced CachyOS defaults, always
# safe to attempt; kept when something still needs them). The hyprland tail
# (gnome-text-editor → zed, gnome-calculator → the fuzzel calc menu script)
# covers the CachyOS hyprland preinstalls niri boxes never had; absent on niri
# they are plain no-ops there.
_hexciri_stock_rm="cachyos-niri-noctalia xdg-desktop-portal-gnome alacritty firefox meld cachyos-micro-settings micro vlc-plugins-all cachyos-wallpapers"
# xwayland-satellite pin (upstream #468): 0.8.2 regressed popup positioning
# (commit 3273a0f) — X11 dropdowns (Steam menus, etc.) spawn offset and lose
# hover on niri. Hold at last-good 0.8.1 until a fixed 0.8.3+ lands, then drop
# this block. Mirrored in bin/hexciri-sync (§6, re-asserts the hold on every
# update) and bin/hexciri-update (hold + downgrade before its Syu).
if command -v pacman >/dev/null 2>&1; then
  if grep -Eq '^IgnorePkg.*xwayland-satellite' /etc/pacman.conf 2>/dev/null; then
    : # already held
  elif grep -Eq '^IgnorePkg[[:space:]]*=' /etc/pacman.conf 2>/dev/null; then
    sudo sed -Ei 's/^(IgnorePkg[^#]*)(#.*)?$/\1 xwayland-satellite \2/' /etc/pacman.conf 2>&1 | sed 's/^/  /' && \
      info "held xwayland-satellite (IgnorePkg)" || \
      info "hold skipped — add by hand: IgnorePkg = xwayland-satellite in /etc/pacman.conf"
  elif grep -Eq '^#IgnorePkg[[:space:]]*=' /etc/pacman.conf 2>/dev/null; then
    sudo sed -Ei '0,/^#IgnorePkg[[:space:]]*=.*/s//IgnorePkg = xwayland-satellite/' /etc/pacman.conf 2>&1 | sed 's/^/  /' && \
      info "held xwayland-satellite (IgnorePkg)" || \
      info "hold skipped — add by hand: IgnorePkg = xwayland-satellite in /etc/pacman.conf"
  else
    printf '\nIgnorePkg = xwayland-satellite\n' | sudo tee -a /etc/pacman.conf >/dev/null 2>&1 && \
      info "held xwayland-satellite (IgnorePkg)" || \
      info "hold skipped — add by hand: IgnorePkg = xwayland-satellite in /etc/pacman.conf"
  fi
  if pacman -Q xwayland-satellite 2>/dev/null | grep -q ' 0\.8\.2'; then
    info "downgrading xwayland-satellite 0.8.2 → 0.8.1 (upstream #468 popup regression)"
    sudo pacman -U --noconfirm https://archive.archlinux.org/packages/x/xwayland-satellite/xwayland-satellite-0.8.1-2-x86_64.pkg.tar.zst 2>&1 | sed 's/^/  /' || \
      info "downgrade skipped — run by hand: sudo pacman -U https://archive.archlinux.org/packages/x/xwayland-satellite/xwayland-satellite-0.8.1-2-x86_64.pkg.tar.zst"
  fi
fi
_hexciri_purge="alacritty:$HOME/.config/alacritty firefox:$HOME/.mozilla meld:$HOME/.config/meld micro:$HOME/.config/micro"
if command -v pacman >/dev/null 2>&1; then
  info "one-time app swap (hexciri wants + stock removals)"
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
  # Desktop faillock bounds (same as the update migration): stock deny=3 /
  # unlock_time=600 turns one typo burst into a reboot-only saga (retries
  # inside the window fail and extend it). deny=5 + unlock_time=60 keeps
  # brute-force protection while capping the cost at a minute. Stock files
  # only — an admin-tuned deny/unlock_time/fail_interval is never touched.
  if [[ -f /etc/security/faillock.conf ]] && ! grep -qE '^[[:space:]]*(deny|unlock_time|fail_interval)[[:space:]]*=' /etc/security/faillock.conf; then
    for _kv in "deny = 5" "unlock_time = 60"; do
      _key="${_kv%% *}"
      if ! grep -qE "^[[:space:]]*$_key[[:space:]]*=" /etc/security/faillock.conf; then
        printf '%s\n' "$_kv" | sudo tee -a /etc/security/faillock.conf >/dev/null 2>&1 && \
          info "faillock $_kv (desktop bounds; stock file only)" || \
          info "faillock tune skipped (no sudo here)"
      fi
    done
    unset _kv _key
  fi
  if pacman -Q vim >/dev/null 2>&1; then
    info "removing vim (forced: breaks only cachyos-zsh-config's declared dep)"
    if sudo pacman -Rdd --noconfirm vim 2>&1 | sed 's/^/  /'; then
      rm -rf "$HOME/.vim" "$HOME/.viminfo"
      info "removed vim"
    else
      info "kept vim (forced removal failed)"
    fi
  fi
  # Stock hyprland editor + calculator (vim precedent): the CachyOS hyprland
  # meta pins them so plain -Rns refuses — -Rdd breaks only the meta's
  # declared dep. The editor goes only when zed (its replacement) is present;
  # the calculator is hexciri's fuzzel menu script, not an app.
  for _p in gnome-text-editor gnome-calculator; do
    pacman -Q "$_p" >/dev/null 2>&1 || continue
    if [[ $_p == gnome-text-editor ]] && ! command -v zeditor >/dev/null 2>&1; then
      info "kept $_p (zed not present yet)"
      continue
    fi
    info "removing $_p (forced: breaks only cachyos-hypr-noctalia's declared dep)"
    if sudo pacman -Rdd --noconfirm "$_p" 2>&1 | sed 's/^/  /'; then
      info "removed $_p"
    else
      info "kept $_p (forced removal failed)"
    fi
  done
  unset _p _m _pkg _dir
fi
unset _hexciri_wants _hexciri_stock_rm _hexciri_purge
# mupdf → zathura migration (one-time; no-op when clean): a re-run of
# install.sh must converge boxes that got mupdf from an older bring-up.
# zathura-pdf-mupdf conflicts with the poppler backend, so that goes first.
if command -v pacman >/dev/null 2>&1; then
  if pacman -Q zathura-pdf-poppler >/dev/null 2>&1; then
    if sudo pacman -Rns --noconfirm zathura-pdf-poppler 2>&1 | sed 's/^/  /'; then
      info "removed zathura-pdf-poppler (mupdf backend is the default)"
    else
      info "kept zathura-pdf-poppler (removal failed)"
    fi
  fi
  if pacman -Q mupdf >/dev/null 2>&1; then
    if sudo pacman -Rns --noconfirm mupdf 2>&1 | sed 's/^/  /'; then
      info "removed mupdf (replaced by zathura)"
    else
      info "kept mupdf (something still needs it)"
    fi
  fi
  if ! pacman -Q mupdf >/dev/null 2>&1 && [[ -f $HOME/.local/share/applications/mupdf.desktop ]]; then
    rm -f "$HOME/.local/share/applications/mupdf.desktop" && \
      info "removed stale mupdf desktop override"
  fi
fi
if [[ $(cat "$HOME/.local/state/hexciri/defaults/pdf" 2>/dev/null || true) == mupdf ]]; then
  mkdir -p "$HOME/.local/state/hexciri/defaults"
  printf '%s' "zathura" > "$HOME/.local/state/hexciri/defaults/pdf" && \
    info "default pdf mupdf → zathura"
fi
# Nautilus is the default file manager (pacman package, in _hexciri_wants so a
# fresh box gets it even if the removed niri meta took it). A stale
# Hidden=true override from the Strata era would keep it out of menus, so drop
# it; the stock desktop entry applies again.
if [[ -f $HOME/.local/share/applications/org.gnome.Nautilus.desktop ]]; then
  rm -f "$HOME/.local/share/applications/org.gnome.Nautilus.desktop" && \
    info "unhid nautilus launcher entry (Strata-era override removed)"
fi
# inode/directory is owned by the mime-defaults table (heal pins the stored
# Files pick when the slot is empty/stale, never over a deliberate pick).
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
# AUR want (Brave Origin). Installs via yay/paru as you, then drops
# the brave-bin stand-in once origin is present. Best-effort, never fatal.
_hexciri_aur_pkgs="brave-origin-bin "
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
unset _aur _h _hexciri_aur_pkgs
if command -v brave-origin >/dev/null 2>&1 && pacman -Q brave-bin >/dev/null 2>&1; then
  info "removing Brave stand-in (Origin is present)"
  sudo pacman -Rns --noconfirm brave-bin 2>&1 | sed 's/^/  /' || \
    info "kept brave-bin (removal failed) — remove by hand if unwanted"
fi
# Per-user Strata install (hyprland file manager): release binary, no pacman
# package — the installer verifies sha256 and skips when current. Needs
# network; deps install via sudo inside. Best-effort, never fatal. niri
# boxes skip it (nautilus serves there).
if [[ ${_hexciri_install_wm:-niri} == hyprland ]] && [[ -x "$REPO/bin/hexciri-strata-install" ]]; then
  info "installing Strata (hyprland file manager, per-user release)"
  "$REPO/bin/hexciri-strata-install" 2>&1 | sed 's/^/  /' || \
    info "Strata install skipped — run by hand: hexciri-strata-install"
fi
# Default-app file associations: one table (images, documents, files,
# browser) pins the stored picks, healing only browser-stolen, empty, or
# stale slots — a deliberate pick stays. Best-effort, never fatal; re-runs
# heal whatever the browser re-stole.
if [[ -x "$REPO/bin/hexciri-mime-defaults" ]]; then
  info "applying default-app file associations"
  HEXCIRI_PATH="$REPO" "$REPO/bin/hexciri-mime-defaults" heal 2>&1 | sed 's/^/  /' || \
    info "mime defaults skipped — pick System > Default Apps by hand"
fi
# aether:// web-apply links: route them through the hexciri handler so one
# click applies in Aether AND follows through to the hexciri theme (bar).
if [[ -x "$REPO/bin/hexciri-aether-url" ]]; then
  info "claiming aether:// links for the hexciri handler"
  "$REPO/bin/hexciri-aether-url" heal 2>&1 | sed 's/^/  /' || \
    info "aether handler skipped — run 'hexciri-aether-url heal' by hand"
fi
# Login-greeter appearance sync authorization (one-time): on greetd boxes the
# login page is noctalia-greeter, and every theme-set pushes the new palette +
# wallpaper there via `noctalia msg greeter-sync` (hooks/theme-set.d/
# 90-greeter-sync.sh). That sync needs admin auth per call unless this narrow
# polkit rule exists — enabling it once makes all future syncs promptless.
# Scoped to the greeter appearance action only (never sudo, never legacy
# paths). Best-effort, never fatal; existing boxes get it from root sync.
if command -v noctalia-greeter >/dev/null 2>&1; then
  info "authorizing passwordless login-greeter sync for $USER"
  sudo noctalia-greeter passwordless-sync enable "$USER" 2>&1 | sed 's/^/  /' || \
    info "greeter sync stays admin-prompted — run by hand: sudo noctalia-greeter passwordless-sync enable $USER"
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
