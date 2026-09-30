#!/usr/bin/env bash
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

if ! command -v opencode >/dev/null 2>&1; then
    skipped "opencode"
fi

if ! command -v python3 >/dev/null 2>&1; then
    skipped "python3 (opencode theme needs json merge)"
fi

# accent isn't exported by theme-env.sh — pull with fallback to blue.
accent="$(extract_color "accent")"
[[ -n $accent ]] || accent="$normal_blue"

# Elevated input surfaces must stay dark. selection_background is light in
# some themes (storm-cloud: #d8e1d4) which gives light-on-light composer
# boxes, so element uses lighter_background instead.
bg_element="$(extract_color "lighter_background")"
[[ -n $bg_element ]] || bg_element="$(extract_color "lighter_bg")"
[[ -n $bg_element ]] || bg_element="$normal_black"

# Selected list items render their text over the primary color
# (selectedListItemText; opencode's own fallback is the background color).
# Mirror fuzzel (hexciri-theme-set-templates): selection bg is always the
# accent, text is whichever of background / bright_foreground has the higher
# WCAG contrast ratio. Knife-edge luminance thresholds fail mid-tone accents
# (solitude #798186: light text picked for a medium accent ≈ 1.76:1).
sel_fg="$bright_white"
if [[ $accent =~ ^[0-9a-fA-F]{6}$ && $bright_white =~ ^[0-9a-fA-F]{6}$ && $primary_background =~ ^[0-9a-fA-F]{6}$ ]]; then
  sel_fg="$(python3 - "$accent" "$bright_white" "$primary_background" << 'PY'
import sys
def _lum(h):
    c = h.lstrip('#')
    rgb = [int(c[i:i+2], 16) / 255 for i in (0, 2, 4)]
    rgb = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
def _ratio(a, b):
    x, y = sorted([_lum(a), _lum(b)])
    return (y + 0.05) / (x + 0.05)
accent, bright, bg = sys.argv[1], sys.argv[2], sys.argv[3]
print(bg if _ratio(bg, accent) >= _ratio(bright, accent) else bright, end='')
PY
)"
fi

theme_dir="$HOME/.config/opencode/themes"
tui_file="$HOME/.config/opencode/tui.json"
mkdir -p "$theme_dir"

cat > "$theme_dir/hexciri.json" << EOF
{
  "\$schema": "https://opencode.ai/theme.json",
  "theme": {
    "primary": "#${accent}",
    "secondary": "#${normal_magenta}",
    "accent": "#${accent}",
    "error": "#${normal_red}",
    "warning": "#${normal_yellow}",
    "success": "#${normal_green}",
    "info": "#${normal_cyan}",
    "text": "#${primary_foreground}",
    "textMuted": "#${bright_black}",
    "selectedListItemText": "#${sel_fg}",
    "background": "#${primary_background}",
    "backgroundPanel": "#${normal_black}",
    "backgroundElement": "#${bg_element}",
    "backgroundMenu": "#${normal_black}",
    "borderSubtle": "#${normal_black}",
    "border": "#${bright_black}",
    "borderActive": "#${accent}",
    "diffAdded": "#${normal_green}",
    "diffRemoved": "#${normal_red}",
    "diffContext": "#${bright_black}",
    "diffHunkHeader": "#${bright_black}",
    "diffHighlightAdded": "#${bright_green}",
    "diffHighlightRemoved": "#${bright_red}",
    "diffAddedBg": "#${normal_black}",
    "diffRemovedBg": "#${normal_black}",
    "diffContextBg": "#${normal_black}",
    "diffLineNumber": "#${bright_black}",
    "diffAddedLineNumberBg": "#${normal_black}",
    "diffRemovedLineNumberBg": "#${normal_black}",
    "markdownText": "#${primary_foreground}",
    "markdownHeading": "#${normal_blue}",
    "markdownLink": "#${normal_blue}",
    "markdownLinkText": "#${normal_cyan}",
    "markdownCode": "#${normal_green}",
    "markdownBlockQuote": "#${bright_black}",
    "markdownEmph": "#${normal_yellow}",
    "markdownStrong": "#${primary_foreground}",
    "markdownHorizontalRule": "#${bright_black}",
    "markdownListItem": "#${primary_foreground}",
    "markdownListEnumeration": "#${normal_cyan}",
    "markdownImage": "#${normal_blue}",
    "markdownImageText": "#${normal_cyan}",
    "markdownCodeBlock": "#${primary_foreground}",
    "syntaxComment": "#${bright_black}",
    "syntaxKeyword": "#${normal_magenta}",
    "syntaxFunction": "#${normal_blue}",
    "syntaxVariable": "#${primary_foreground}",
    "syntaxString": "#${normal_green}",
    "syntaxNumber": "#${normal_yellow}",
    "syntaxType": "#${normal_cyan}",
    "syntaxOperator": "#${normal_cyan}",
    "syntaxPunctuation": "#${primary_foreground}"
  }
}
EOF

# Point tui.json at the generated theme, preserving any other keys.
python3 - "$tui_file" << 'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    data = json.loads(p.read_text()) if p.is_file() else {}
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
data["$schema"] = "https://opencode.ai/tui.json"
data["theme"] = "hexciri"
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2) + "\n")
PY

success "opencode theme updated!"
exit 0
