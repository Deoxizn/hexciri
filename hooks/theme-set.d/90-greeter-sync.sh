#!/usr/bin/env bash
# 90-greeter-sync.sh — push the new theme to the login screen.
# On greetd boxes the login page is noctalia-greeter, which only learns a new
# appearance (palette + wallpaper + font + scale) through Noctalia's greeter
# sync. Trigger it after every theme-set so login follows the desktop.
# Authorization is the one-time `sudo noctalia-greeter passwordless-sync
# enable <user>` (owned by install.sh + root hexciri-sync); without it
# Noctalia falls back to a polkit admin prompt, and a refused/failed sync
# just skips here — never fatal, never blocking the theme change itself.
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

if ! command -v noctalia >/dev/null 2>&1 || ! command -v pgrep >/dev/null 2>&1 || ! pgrep -x noctalia >/dev/null 2>&1; then
  skipped "Greeter sync (no live Noctalia session)"
fi
if [[ ! -x /usr/bin/noctalia-greeter-apply-appearance ]]; then
  skipped "Greeter sync (no noctalia-greeter install)"
fi

if noctalia msg greeter-sync >/dev/null 2>&1; then
  success "Login greeter appearance synced!"
else
  warning "Greeter sync needs authorization (run once: sudo noctalia-greeter passwordless-sync enable $USER)"
fi
