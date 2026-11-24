#!/usr/bin/env bash
# Hexciri v2 theme hook 20: THPM (Theme Hook Plugin Manager, OldJobobo/thpm).
# 2026-11-24, Devi: modified better Omarchy theme hook, THPM in it.
# THPM itself is installed from GitHub source (./install.sh --no-ui, NOT
# yay/pacman, it was kicked off AUR) by the installer, and its own hook
# lands at ~/.config/omarchy/hooks/theme-set.d/90-thpm, which Hexciri's
# hexciri-hook never reads (it reads ~/.config/hexciri/hooks/theme-set.d/).
# The installer bridges that file here as 90-thpm; this hook is the
# fallback that runs THPM's theme-set event directly, so enabled THPM
# integrations (e.g. steam, via the steam-adwaita checkout at
# ~/.local/share/steam-adwaita) apply on every theme switch even if the
# bridge is missing. THPM integrations are all disabled by default;
# enable one with `thpm enable <id>` and it stays synced after that.
# Skips quietly when thpm is not installed. Never dies: a THPM failure
# must not break the rest of the theme switch.
if ! command -v thpm >/dev/null 2>&1; then
    exit 0
fi
# THPM's own 90-thpm bridge (if present) runs the same event right after
# this file, alphabetically. That is a no-op reapply, not a double theme:
# THPM reports unchanged integrations as unchanged. Run it anyway so a
# missing bridge cannot silently drop the sync.
thpm hook-run theme-set "$@" >&2 || echo "WARN: thpm hook-run theme-set failed, THPM integrations did not re-apply (check: thpm doctor)" >&2
exit 0
