#!/usr/bin/env bash
# Hexciri v2 theme hook 21: Dorion (SpikeHD/Dorion, Tauri Discord client).
# 2026-11-25, Devi: local Hexciri-side only, no upstream THPM changes.
# THPM has no Dorion target: its _discord_directories() is upstream code
# (Vencord, Vesktop, Equicord, Equibop + Flatpak paths) and THPM is not
# to be edited. THPM's discord integration renders vencord.theme.css
# into ~/.config/vesktop/themes/; this hook mirrors that one file into
# Dorion's native theme dir so Dorion follows the theme too. Dorion
# themes are BetterDiscord/Vencord CSS, same format as Vesktop, so the
# file needs no conversion (Devi's manual copy already proved that).
# Runs after 20-hexciri-thpm, so the Vesktop file is fresh on every
# switch. Skips quietly when the source is missing or Dorion has never
# run (no ~/.config/dorion); never dies, never fails the theme switch.
# Dorion only loads a theme file whose name is in the `themes` list in
# ~/.config/dorion/config.json: enable vencord.theme.css once in Dorion
# Settings > Themes, then switches apply (restart Dorion if it does not
# hot-reload the file).
SRC="$HOME/.config/vesktop/themes/vencord.theme.css"
DST_DIR="$HOME/.config/dorion/themes"
[ -f "$SRC" ] || exit 0
[ -d "$HOME/.config/dorion" ] || exit 0
mkdir -p "$DST_DIR" 2>/dev/null || exit 0
cp -f "$SRC" "$DST_DIR/vencord.theme.css" 2>/dev/null || exit 0
exit 0
