#!/usr/bin/env bash
# Hexciri v2 theme hook 22: Zed editor.
# 2026-11-25, Devi: Zed never got a Hexciri theme. Two stacked causes:
# 1. The fork ships hooks/theme-set.d/20-zed.sh, but v2's installer never
#    deploys fork hooks into ~/.config/hexciri/hooks/theme-set.d/ (only the
#    Hexciri-side hooks 10/11/20 are installed there), so 20-zed.sh never
#    ran on a theme switch.
# 2. The dotfiles hook `omazed set` cannot work on Hexciri: omazed is an
#    Omarchy-repo package that does not exist on Arch, and Hexciri
#    deliberately dropped it from install-editor-zed, so that hook fails
#    every switch with command not found. THPM's zed-extra cannot cover
#    it either: it needs an authored zed.json/aether.zed.json in the
#    theme, and stock themes like Solitude do not ship one.
# This hook is the Hexciri-side replacement: it generates the dynamic
# "Hexciri" Zed theme from the active palette (same template as the
# fork's 20-zed.sh) into ~/.config/zed/themes/hexciri.json, and selects
# it in settings.json when Zed has no theme selected yet. Zed watches
# its themes dir and live-reloads the active theme when the file
# changes, so after the one-time selection every theme switch re-themes
# Zed live. If the active theme ships its own zed.json, that authored
# asset wins over the generated one, like THPM does.
# Skips quietly when Zed is not installed; never dies, never fails the
# theme switch.
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}" 2>/dev/null || exit 0

if ! command -v zeditor >/dev/null 2>&1 && ! command -v zed >/dev/null 2>&1; then
    exit 0
fi

# Appearance follows the staged theme (light.mode file, else mode key).
APPEARANCE="dark"
if [ -f "$THPM_CURRENT_THEME_DIR/light.mode" ]; then
    APPEARANCE="light"
elif [ -f "$THPM_CURRENT_THEME_DIR/colors.toml" ] && grep -q '^mode[[:space:]]*=[[:space:]]*"light"' "$THPM_CURRENT_THEME_DIR/colors.toml" 2>/dev/null; then
    APPEARANCE="light"
fi

GEN_FILE="${THPM_STATE_DIR:-$HOME/.local/state/hexciri/theme-hook}/zed-hexciri.json"
mkdir -p "$(dirname "$GEN_FILE")" "$HOME/.config/zed/themes" 2>/dev/null || exit 0

create_dynamic_theme() {
cat > "$GEN_FILE" << EOF
    {
      "\$schema": "https://zed.dev/schema/themes/v0.1.0.json",
      "name": "Hexciri",
      "author": "@bypass_",
      "themes": [
        {
          "name": "Hexciri",
          "appearance": "$APPEARANCE",
          "style": {
            "background": "#${primary_background}90",
            "editor.background": "#${primary_background}90",
            "editor.foreground": "#${primary_foreground}",
            "text": "#${primary_foreground}",
            "text.muted": "#${primary_foreground}70",
            "text.ignored": "#${primary_foreground}40",
            "text.placeholder": "#${primary_foreground}50",
            "ignored": "#${primary_foreground}30",
            "element.hover": "#${primary_foreground}30",
            "ghost_element.hover": "#${bright_black}30",
            "ghost_element.selected": "#${bright_black}30",
            "ghost_element.active": "#${bright_black}60",
            "border": "#${normal_black}",
            "editor.highlighted_line.background": "#${bright_black}10",
            "editor.active_line.background": "#${bright_black}10",
            "panel.background": "#${normal_black}90",
            "title_bar.background": "#${normal_black}90",
            "title_bar.inactive_background": "#${normal_black}90",
            "status_bar.background": "#${normal_black}90",
            "drop_target.background": "#${normal_black}90",
            "elevated_surface.background": "#${normal_black}",
            "toolbar.background": "#${normal_black}90",
            "tab_bar.background": "#${normal_black}90",
            "tab.inactive_background": "#${normal_black}90",
            "tab.active_background": "#${bright_black}30",
            "scrollbar.track.background": "transparent",
            "scrollbar.track.border": "#${normal_black}",
            "scrollbar.thumb.background": "#${primary_foreground}",
            "editor.gutter.background": "#${normal_black}90",
            "terminal.background": "#${normal_black}10",
            "terminal.foreground": "#${primary_foreground}",
            "terminal.dim_foreground": "#${primary_foreground}",
            "terminal.bright_foreground": "#${primary_foreground}",
            "terminal.ansi.black": "#${normal_black}",
            "terminal.ansi.red": "#${normal_red}",
            "terminal.ansi.green": "#${normal_green}",
            "terminal.ansi.yellow": "#${normal_yellow}",
            "terminal.ansi.blue": "#${normal_blue}",
            "terminal.ansi.magenta": "#${normal_magenta}",
            "terminal.ansi.cyan": "#${normal_cyan}",
            "terminal.ansi.white": "#${normal_white}",
            "terminal.ansi.bright_black": "#${bright_black}",
            "terminal.ansi.bright_red": "#${bright_red}",
            "terminal.ansi.bright_green": "#${bright_green}",
            "terminal.ansi.bright_yellow": "#${bright_yellow}",
            "terminal.ansi.bright_blue": "#${bright_blue}",
            "terminal.ansi.bright_magenta": "#${bright_magenta}",
            "terminal.ansi.bright_cyan": "#${bright_cyan}",
            "terminal.ansi.bright_white": "#${bright_white}",
            "modified": "#${normal_red}",
            "syntax": {
              "attribute": {
                "color": "#${normal_white}"
              },
              "boolean": {
                "color": "#${normal_green}"
              },
              "comment": {
                "color": "#${bright_black}"
              },
              "comment.doc": {
                "color": "#${bright_black}"
              },
              "constant": {
                "color": "#${bright_green}"
              },
              "function": {
                "color": "#${bright_cyan}"
              },
              "keyword": {
                "color": "#${normal_blue}"
              },
              "number": {
                "color": "#${normal_magenta}"
              },
              "operator": {
                "color": "#${normal_blue}"
              },
              "string": {
                "color": "#${normal_red}"
              },
              "variable": {
                "color": "#${normal_green}"
              }
            },
            "players": [
              {
                "cursor": "#${primary_foreground}",
                "background": "#${normal_black}",
                "selection": "#${primary_foreground}30"
              }
            ]
          }
        }
      ]
    }
EOF
}

# Authored asset wins: a zed.json shipped with the active theme is used
# as-is (renamed to Hexciri), otherwise generate from the palette.
if [ -f "$THPM_CURRENT_THEME_DIR/zed.json" ]; then
    cp -f "$THPM_CURRENT_THEME_DIR/zed.json" "$HOME/.config/zed/themes/hexciri.json" 2>/dev/null || exit 0
else
    create_dynamic_theme
    cp -f "$GEN_FILE" "$HOME/.config/zed/themes/hexciri.json" 2>/dev/null || exit 0
fi

# Select "Hexciri" once: only when settings.json has no theme key at all.
# If a theme is already selected, leave the user's choice alone (select
# Hexciri once in Zed's theme picker instead). JSONC-safe: plain text
# insert, no JSON rewrite, so comments and formatting survive.
SETTINGS="$HOME/.config/zed/settings.json"
if [ ! -f "$SETTINGS" ]; then
    printf '{\n  "theme": "Hexciri"\n}\n' > "$SETTINGS" 2>/dev/null || true
elif ! grep -q '"theme"' "$SETTINGS" 2>/dev/null; then
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$SETTINGS" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
if '"theme"' not in text:
    idx = text.find("{")
    if idx >= 0:
        open(p, "w", encoding="utf-8").write(text[:idx + 1] + '\n  "theme": "Hexciri",' + text[idx + 1:])
PYEOF
    fi
fi

exit 0
