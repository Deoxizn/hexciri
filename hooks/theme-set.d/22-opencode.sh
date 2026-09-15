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
    "selectedListItemText": "#${bright_white}",
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
