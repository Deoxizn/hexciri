#!/usr/bin/env bash
# Hexciri v2 theme hook 15: THPM bridge sync (2026-11-25).
# Two Hexciri/THPM path splits break THPM on every theme switch, and
# both live here, in one hook that runs after the theme is staged (10)
# and before THPM applies it (20):
# 1. Template dir: THPM's reconcile_templates() writes its *.tpl files
#    to ~/.config/omarchy/themed, but the forked renderer
#    (hexciri-theme-set-templates) only reads ~/.config/hexciri/themed,
#    so THPM templates were never rendered into the next theme.
#    Fix: ~/.config/hexciri/themed is a symlink to the omarchy dir,
#    so both sides see the same files. Re-asserted every switch, so
#    deleting the link cannot silently break the next theme-set.
#    A real hexciri/themed dir with user templates is merged into the
#    shared dir first (same-name files stay where THPM owns them),
#    never deleted outright.
# 2. Current theme dir: THPM reads generated outputs from
#    ~/.local/state/omarchy/current/theme, but Hexciri stages the
#    rendered theme at ~/.local/state/hexciri/current/theme, and the
#    Strata hook (10) only links theme.name and colors.toml across.
#    Fix: symlink every file the staged theme contains into the
#    omarchy theme dir, and prune stale links that point at files the
#    new theme no longer has. THPM then sees thpm-fish.fish,
#    thpm-fzf.fish, thpm-vencord.theme.css and friends exactly where
#    stock Omarchy puts them, and fish/fzf/discord apply instead of
#    failing "expected theme output was not found".
# Runs on every theme switch and once at install (the installer bashes
# it after deploying the hooks). Skips quietly when no theme is staged
# yet; never dies, never fails the theme switch.
OMARCHY_THEMED="$HOME/.config/omarchy/themed"
HEXCIRI_THEMED="$HOME/.config/hexciri/themed"
mkdir -p "$OMARCHY_THEMED" "$HOME/.config/hexciri" 2>/dev/null || exit 0
if [ -L "$HEXCIRI_THEMED" ]; then
  if [ "$(readlink "$HEXCIRI_THEMED")" != "$OMARCHY_THEMED" ]; then
    ln -sfn "$OMARCHY_THEMED" "$HEXCIRI_THEMED" 2>/dev/null || true
  fi
elif [ -d "$HEXCIRI_THEMED" ]; then
  _left=0
  for _f in "$HEXCIRI_THEMED"/*; do
    [ -e "$_f" ] || continue
    _b="$(basename "$_f")"
    if [ -e "$OMARCHY_THEMED/$_b" ]; then
      _left=1
    elif mv -f "$_f" "$OMARCHY_THEMED/" 2>/dev/null; then
      :
    else
      _left=1
    fi
  done
  if [ "$_left" = "0" ] && rmdir "$HEXCIRI_THEMED" 2>/dev/null; then
    ln -sfn "$OMARCHY_THEMED" "$HEXCIRI_THEMED" 2>/dev/null || true
  elif [ "$_left" = "1" ]; then
    echo "WARN: ~/.config/hexciri/themed holds files that also exist in ~/.config/omarchy/themed, bridge not linked, move them by hand" >&2
  fi
  unset _left _f _b
else
  ln -sfn "$OMARCHY_THEMED" "$HEXCIRI_THEMED" 2>/dev/null || true
fi
unset OMARCHY_THEMED HEXCIRI_THEMED
SRC_DIR="$HOME/.local/state/hexciri/current/theme"
DST_DIR="$HOME/.local/state/omarchy/current/theme"
[ -d "$SRC_DIR" ] || exit 0
mkdir -p "$DST_DIR" 2>/dev/null || exit 0
for _f in "$SRC_DIR"/*; do
  [ -f "$_f" ] || continue
  ln -sfn "$_f" "$DST_DIR/$(basename "$_f")" 2>/dev/null || true
done
for _l in "$DST_DIR"/*; do
  [ -L "$_l" ] || continue
  _t="$(readlink "$_l" 2>/dev/null || echo "")"
  case "$_t" in
    "$SRC_DIR"/*) [ -e "$_t" ] || rm -f "$_l" 2>/dev/null || true ;;
  esac
done
unset _f _l _t SRC_DIR DST_DIR
exit 0
