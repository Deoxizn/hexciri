#!/usr/bin/env bash
# 91-sddm-follow.sh — push the new theme to SDDM (stage + privileged install).
# Stages the live wallpaper + a palette snippet into caller-owned
# /run/user/<uid>/hexciri-sddm, then installs them into the hexciri SDDM theme
# via the constrained root helper (pkexec action org.hexciri.sddm-apply).
# Promptless once root sync has written the site-local allow rule; otherwise
# polkit asks for admin auth, and a refused/failed install just warns here —
# never fatal, never blocking the theme change itself.
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STAGING="$RUNTIME/hexciri-sddm"
HELPER=/usr/local/libexec/hexciri-sddm-apply

if [[ ! -x $HELPER ]]; then
  skipped "SDDM follow (helper not installed — run sudo hexciri-sync)"
fi

rm -rf "$STAGING"
mkdir -p "$STAGING" || { warning "SDDM follow skipped (no runtime dir)"; exit 0; }

# Palette from the just-rendered theme (theme-env exports; hex, no '#').
{
  printf 'Background=#%s\n' "$primary_background"
  printf 'Muted=#%s\n' "$bright_black"
  printf 'Error=#%s\n' "$normal_red"
} > "$STAGING/sddm-theme.conf"

# Wallpaper: the LIVE wallpaper, not the theme default. `noctalia msg
# wallpaper-get` is ground truth (order-proof: this hook sorts before the
# theme bridge that rewrites the `current` symlink, and the user may have
# picked via the Noctalia picker without any theme-set). Falls back to the
# `current` symlink (headless), else colors-only.
SRC=""
if command -v noctalia >/dev/null 2>&1 && command -v pgrep >/dev/null 2>&1 && pgrep -x noctalia >/dev/null 2>&1; then
  SRC="$(noctalia msg wallpaper-get 2>/dev/null | head -n1 || true)"
fi
if [[ -z $SRC ]]; then
  CUR="$HOME/.local/state/noctalia/wallpaper/current"
  if [[ -L $CUR || -f $CUR ]]; then
    SRC="$(readlink -f "$CUR" 2>/dev/null || true)"
  fi
fi
if [[ -n $SRC && -f $SRC && -s $SRC ]]; then
  EXT="${SRC##*.}"; EXT="${EXT,,}"
  case "$EXT" in
    jpg|jpeg|png|webp)
      if cp -f "$SRC" "$STAGING/background.$EXT" 2>/dev/null; then
        printf 'BackgroundFile=%s\n' "background.$EXT" >> "$STAGING/sddm-theme.conf"
      fi ;;
  esac
fi

OUT="$(pkexec "$HELPER" --sync "$STAGING" 2>&1)"; RC=$?
printf '%s\n' "$OUT" | sed 's/^/  /'
if (( RC == 0 )); then
  rm -rf "$STAGING"
  success "SDDM login theme synced!"
else
  rm -rf "$STAGING"
  warning "SDDM follow needs authorization (run once: sudo hexciri-sync)"
fi
