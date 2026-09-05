#!/usr/bin/env bash
# noctalia-sync.sh — Bridge hexciri colors.toml → Noctalia + Niri theme
# Installed to: ~/.config/hexciri/hooks/theme-set.d/
# Triggered automatically by hexciri-theme-set after every theme change.
#
# Reads hexciri's current colors.toml and:
#   1. Generates a Noctalia custom palette JSON from hexciri colors
#   2. Sets Noctalia to use the custom palette
#   3. Updates Niri config.kdl border/focus ring colors
#   4. Syncs wallpaper if the theme ships a backgrounds/ directory.

set -euo pipefail

THEME_DIR="${HEXCIRI_CURRENT_THEME:-$HOME/.local/state/hexciri/current/theme}"
NOCTALIA_DIR="$HOME/.config/noctalia"
NOCTALIA_CFG="$NOCTALIA_DIR/config.toml"
NIRI_CFG="$HOME/.config/niri/config.kdl"

if [[ ! -f "$THEME_DIR/colors.toml" ]]; then
  echo "hexciri noctalia-sync: no colors.toml found at $THEME_DIR" >&2
  exit 1
fi

mkdir -p "$NOCTALIA_DIR"
mkdir -p "$NOCTALIA_DIR/palettes"

THEME_NAME_FILE="$HOME/.local/state/hexciri/current/theme.name"
if [[ -f "$THEME_NAME_FILE" ]]; then
  THEME_NAME=$(<"$THEME_NAME_FILE")
else
  THEME_NAME=$(basename "$THEME_DIR")
fi

export HEXCIRI_CURRENT_THEME="$THEME_DIR"
export NOCTARCHIA_THEME_NAME="$THEME_NAME"
export NOCTALIA_DIR
export NIRI_CFG

python3 <<'PYEOF'
import json
import os
import re
import tomllib
from pathlib import Path

theme_dir = Path(os.environ.get("HEXCIRI_CURRENT_THEME") or Path.home() / ".local/state/hexciri/current/theme")
theme_name = os.environ.get("NOCTARCHIA_THEME_NAME", "unknown")
noctalia_dir = Path(os.environ["NOCTALIA_DIR"])
noctalia_cfg = noctalia_dir / "config.toml"
niri_cfg = Path(os.environ["NIRI_CFG"])

data = tomllib.loads((theme_dir / "colors.toml").read_text())

def hex_color(key, fallback):
    v = data.get(key)
    if isinstance(v, str) and len(v) >= 6:
        return "#" + v.lstrip("#")[:6]
    return "#" + fallback

accent          = hex_color("accent",           "7c3aed")
background      = hex_color("background",       "1a1a2e")
dark_background = hex_color("dark_background",  "11111b")
dark_bg         = hex_color("dark_bg",          "15181a")
darker_bg       = hex_color("darker_bg",        "0e1012")
lighter_bg      = hex_color("lighter_bg",       "333639")
foreground      = hex_color("foreground",       "c0d0e0")
muted           = hex_color("muted",            "586070")
bright_fg       = hex_color("bright_foreground", "eeeeee")
selection       = hex_color("selection",         "292e42")
red             = hex_color("red",               "f7768e")
green           = hex_color("green",             "9ece6a")
yellow          = hex_color("yellow",            "e0af68")
blue            = hex_color("blue",              "7aa2f7")
magenta         = hex_color("magenta",           "bb9af7")
cyan            = hex_color("cyan",              "7dcfff")

# ── 1. Generate custom palette JSON ──
palette = {
    "dark": {
        "mPrimary": accent,
        "mOnPrimary": background,
        "mSecondary": muted,
        "mOnSecondary": foreground,
        "mTertiary": blue,
        "mOnTertiary": background,
        "mError": red,
        "mOnError": background,
        "mSurface": dark_background,
        "mOnSurface": foreground,
        "mSurfaceVariant": lighter_bg,
        "mOnSurfaceVariant": foreground,
        "mOutline": muted,
        "mShadow": darker_bg,
        "mHover": darker_bg,
        "mOnHover": foreground,
        "terminal": {
            "background": background,
            "foreground": foreground,
            "cursor": foreground,
            "cursorText": background,
            "selectionBg": selection,
            "selectionFg": foreground,
            "normal": {
                "black": dark_background,
                "red": red,
                "green": green,
                "yellow": yellow,
                "blue": blue,
                "magenta": magenta,
                "cyan": cyan,
                "white": foreground
            },
            "bright": {
                "black": muted,
                "red": red,
                "green": green,
                "yellow": yellow,
                "blue": blue,
                "magenta": magenta,
                "cyan": cyan,
                "white": bright_fg
            }
        }
    }
}

palette_path = noctalia_dir / "palettes" / "hexciri.json"
palette_path.write_text(json.dumps(palette, indent=2) + "\n")
print(f"noctalia-sync: wrote palette → {palette_path}")

# ── 2. Patch Noctalia config.toml to use custom palette ──
if noctalia_cfg.exists():
    cfg = noctalia_cfg.read_text()
    mode = data.get("mode", "dark")
    # Replace [theme] section
    theme_block = f"""[theme]
source = "custom"
custom_palette = "hexciri"
mode = "{"dark" if mode == "dark" else "light"}\""""
    if '[theme]' in cfg:
        cfg = re.sub(r'\[theme\].*?(?=\n\[|\Z)', theme_block, cfg, flags=re.DOTALL)
    else:
        cfg = theme_block + "\n\n" + cfg
    noctalia_cfg.write_text(cfg)
    print(f"noctalia-sync: patched config.toml → custom palette 'hexciri'")

# ── 3b. Qt theming (qt6ct): QPalette color scheme from theme colors ──
qt6_dir = Path.home() / ".config" / "qt6ct"
(qt6_dir / "colors").mkdir(parents=True, exist_ok=True)

def arr(c):
    return "#ff" + c.lstrip("#")

# 21 roles per line. Live-verified against qt6ct: tokens map by the REAL
# QPalette enum index order (0=WindowText, 9=Base, 10=Window, 12=Highlight,
# 13=HighlightedText, 16=AlternateBase, 18=ToolTipBase, 20=PlaceholderText).
roles = [
    foreground,              # 0  WindowText
    background,              # 1  Button
    lighter_bg,              # 2  Light
    lighter_bg,              # 3  Midlight
    darker_bg,               # 4  Dark
    dark_background,         # 5  Mid
    foreground,              # 6  Text
    bright_fg,               # 7  BrightText
    foreground,              # 8  ButtonText
    dark_background,         # 9  Base       (list/field background)
    background,              # 10 Window     (dialog background)
    darker_bg,               # 11 Shadow
    accent,                  # 12 Highlight
    background,              # 13 HighlightedText
    accent,                  # 14 Link
    muted,                   # 15 LinkVisited
    darker_bg,               # 16 AlternateBase
    background,              # 17 NoRole
    dark_background,         # 18 ToolTipBase
    foreground,              # 19 ToolTipText
    muted,                   # 20 PlaceholderText
]
active = ", ".join(arr(c) for c in roles)
disabled = ", ".join("#80" + c.lstrip("#") for c in roles)
(qt6_dir / "colors" / "hexciri.conf").write_text(
    "[ColorScheme]\n"
    f"active_colors={active}\n"
    f"disabled_colors={disabled}\n"
    f"inactive_colors={active}\n"
)
(qt6_dir / "qt6ct.conf").write_text(
    "[Appearance]\n"
    "style=Fusion\n"
    "custom_palette=true\n"
    f"color_scheme_path={qt6_dir / 'colors' / 'hexciri.conf'}\n"
    "standard_dialogs=0\n"
)
print(f"noctalia-sync: wrote Qt color scheme → {(qt6_dir / 'colors' / 'hexciri.conf')}")

# ── 3. Patch Niri config.kdl borders ──
if niri_cfg.exists():
    kdl = niri_cfg.read_text()
    kdl = re.sub(r'(?<!\w)(active-color\s+)"#[0-9a-fA-F]{6}"', f'\\1"{accent}"', kdl)
    kdl = re.sub(r'(inactive-color\s+)"#[0-9a-fA-F]{6}"', f'\\1"{muted}"', kdl)
    niri_cfg.write_text(kdl)
    print(f"noctalia-sync: patched config.kdl borders accent={accent} inactive={muted}")

# ── 4. Wallpaper sync ──
if os.environ.get("NOCTALIA_SYNC_NO_WALLPAPER") != "1":
    wp_dir = theme_dir / "backgrounds"
    if wp_dir.is_dir():
        imgs = sorted(
            p for p in wp_dir.iterdir()
            if p.is_file() and p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
        )
        pick = next(
            (p for p in imgs if theme_name.lower() in p.name.lower()),
            imgs[0] if imgs else None,
        )
        if pick:
            target = pick.resolve()
            # Copy to noctalia wallpaper dir so it persists
            state_dir = Path.home() / ".local" / "state" / "noctalia" / "wallpaper"
            state_dir.mkdir(parents=True, exist_ok=True)
            dest = state_dir / target.name
            if not dest.exists() or dest.read_bytes() != target.read_bytes():
                import shutil
                shutil.copy2(str(target), str(dest))
            (state_dir / "path.txt").write_text(str(dest) + "\n")
            cur = state_dir / "current"
            if cur.is_symlink() or cur.exists():
                cur.unlink()
            cur.symlink_to(dest)
            # Tell Noctalia to apply the wallpaper
            import subprocess
            subprocess.run(["noctalia", "msg", "wallpaper-set", str(dest)], check=False)
            print(f"noctalia-sync: wallpaper → {dest}")

print(f"noctalia-sync: synced theme '{theme_name}'")
PYEOF
