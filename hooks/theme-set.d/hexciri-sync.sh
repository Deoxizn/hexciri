#!/usr/bin/env bash
# hexciri-sync.sh — Session-wide theme bridge: hexciri colors.toml → shell + every installed WM
# Installed to: ~/.config/hexciri/hooks/theme-set.d/
# Triggered automatically by hexciri-theme-set after every theme change.
# (The alpm post-transaction repair hook is a different script, bin/hexciri-sync.)
#
# The theme hook stopped being "the shell sync" and became session-wide:
#   A = WM-independent render (always runs): Noctalia palette + config.toml, qt6ct,
#       wallpaper — identical under every WM.
#   B = per-WM render (loop over installed WMs): the tiny theme surface each WM
#       carries (border/focus-ring colors). Border color writes land on the right
#       per-WM file no matter which compositor you boot.
#
# Niri specifics:
#   0. Migrates a legacy pre-split Niri config (v1/v1.2/v1.3): backs the
#      monolith up to config.bak, then installs the split design so theme
#      border writes + live-reload hit the right files. The .bak is kept
#      byte-for-byte — a user (or an AI) can port personal tweaks from it.
#   3. Updates Niri border/focus ring colors (looknfeel.kdl, the theme-owned
#      fragment — falls back to the legacy monolith when it's still in place)

set -euo pipefail

THEME_DIR="${HEXCIRI_CURRENT_THEME:-$HOME/.local/state/hexciri/current/theme}"
NOCTALIA_DIR="$HOME/.config/noctalia"
NOCTALIA_CFG="$NOCTALIA_DIR/config.toml"
NIRI_CFG="$HOME/.config/niri/config.kdl"

if [[ ! -f "$THEME_DIR/colors.toml" ]]; then
  echo "hexciri-sync: no colors.toml found at $THEME_DIR" >&2
  exit 1
fi

mkdir -p "$NOCTALIA_DIR"
mkdir -p "$NOCTALIA_DIR/palettes"

# ── 0. Niri legacy-monolith migration (v1 → split) ──
# sync.sh owns the upgrade guard (install.sh is fresh-install only). A v1/v1.2/
# v1.3 config.kdl has everything inlined and no `include "..."` lines. Back it
# up to config.bak unchanged, then install the split design so the border color
# write below lands on the right file and niri live-reload works per-fragment.
# Personal tweaks stay safe in config.bak until the user (or an AI) ports them.
NIRI_PATCH_FILE="$NIRI_CFG"
HEXCIRI_ROOT=""
_nb="$(command -v hexciri-theme-set 2>/dev/null || true)"
if [[ -n $_nb ]]; then
  _nb="$(readlink -f "$_nb" 2>/dev/null || true)"
  if [[ -n $_nb ]]; then
    _root="$(dirname "$(dirname "$_nb")")"
    [[ -d "$_root/config/niri" ]] && HEXCIRI_ROOT="$_root"
  fi
fi
NIRI_SPLIT_SRC="${HEXCIRI_NIRI_SPLIT_SRC:-${HEXCIRI_ROOT:+$HEXCIRI_ROOT/config/niri}}"

if [[ -f $NIRI_CFG ]] && ! grep -q '^include "' "$NIRI_CFG"; then
  if [[ -n $NIRI_SPLIT_SRC && -f "$NIRI_SPLIT_SRC/config.kdl" ]]; then
    if [[ ! -f $HOME/.config/niri/config.bak ]]; then
      cp -f "$NIRI_CFG" "$HOME/.config/niri/config.bak"
      echo "hexciri-sync: backed up legacy config.kdl → config.bak"
    fi
    for _f in config cursors env monitors input looknfeel window-rules keybinds autostart; do
      [[ -f "$NIRI_SPLIT_SRC/$_f.kdl" ]] && cp -f "$NIRI_SPLIT_SRC/$_f.kdl" "$HOME/.config/niri/$_f.kdl"
    done
    echo "hexciri-sync: replaced legacy niri monolith with the split design"
  else
    echo "hexciri-sync: legacy config.kdl found but split source missing ($NIRI_SPLIT_SRC) — leaving it untouched" >&2
  fi
fi
# Borders/focus-ring live in looknfeel.kdl after the split; patch that instead
# of the (now include-only) config.kdl. Fall back to config.kdl only if a legacy
# monolith is still the active config.
if [[ -f $HOME/.config/niri/looknfeel.kdl ]]; then
  NIRI_PATCH_FILE="$HOME/.config/niri/looknfeel.kdl"
fi

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
export NIRI_PATCH_FILE

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
niri_patch = Path(os.environ.get("NIRI_PATCH_FILE") or os.environ["NIRI_CFG"])

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
print(f"hexciri-sync: wrote palette → {palette_path}")

# ── 2. Patch Noctalia config.toml to use custom palette ──
# Palette source is the user's independent choice (Themes menu → Palette
# source): a wallpaper/stock palette is preserved — we only force "custom"
# when the section is unset or already on the hexciri custom palette.
if noctalia_cfg.exists():
    cfg = noctalia_cfg.read_text()
    mode = data.get("mode", "dark")
    cur_src = ""
    if '[theme]' in cfg:
        m = re.search(r'^source\s*=\s*"([^"]+)"', cfg.split('[theme]', 1)[1], flags=re.MULTILINE)
        cur_src = m.group(1) if m else ""
    if cur_src in ("", "custom"):
        theme_block = f"""[theme]
source = "custom"
custom_palette = "hexciri"
mode = "{"dark" if mode == "dark" else "light"}\""""
        if '[theme]' in cfg:
            cfg = re.sub(r'\[theme\].*?(?=\n\[|\Z)', theme_block, cfg, flags=re.DOTALL)
        else:
            cfg = theme_block + "\n\n" + cfg
        noctalia_cfg.write_text(cfg)
        print(f"hexciri-sync: patched config.toml → custom palette 'hexciri'")
    else:
        print(f"hexciri-sync: preserving palette source '{cur_src}' (user choice)")
    # Wallpaper directory → hexciri standard, but only when the section is
    # absent entirely; a configured directory is the user's choice and stays.
    if '[wallpaper]' not in cfg:
        cfg = cfg.rstrip('\n') + '\n\n[wallpaper]\nenabled = true\ndirectory = "~/.local/state/hexciri/current/theme/backgrounds"\n'
        noctalia_cfg.write_text(cfg)
        print("hexciri-sync: set wallpaper directory → hexciri standard")

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
print(f"hexciri-sync: wrote Qt color scheme → {(qt6_dir / 'colors' / 'hexciri.conf')}")

# ── 3. Window border/focus-ring colors (niri only) ──
# The tiny theme surface niri carries. Skip niri configs not yet present
# (no-op until a check-out lays them down).
def hex(rgb, alpha="ff"):
    c = rgb.lstrip("#").lower()
    return f"#{alpha}{c}"

def patch_kdl(path, accent, muted):
    if not path.exists():
        return False
    kdl = path.read_text()
    new = re.sub(r'(?<!\w)(active-color\s+)"#[0-9a-fA-F]{6}"', f'\\1"{accent}"', kdl)
    new = re.sub(r'(inactive-color\s+)"#[0-9a-fA-F]{6}"', f'\\1"{muted}"', new)
    if new != kdl:
        path.write_text(new)
        print(f"hexciri-sync: patched {path.name} borders accent={accent} inactive={muted}")
        return True
    return False

# niri: after the split these live in looknfeel.kdl (theme-owned); a legacy
# monolith (pre-split) carries them in config.kdl. Release cron doesn't know
# which — patch whichever file holds them via NIRI_PATCH_FILE.
if niri_patch.exists():
    patch_kdl(niri_patch, accent, muted)

# niri via Noctalia's own include (noctalia.kdl) may hold layout colors too
noct_kdl = Path.home() / ".config" / "niri" / "noctalia.kdl"
if noct_kdl.exists():
    patch_kdl(noct_kdl, accent, muted)

# CachyOS fragment names carry the same theme surface under different files.
cachy_layout = Path.home() / ".config" / "niri" / "cfg" / "layout.kdl"
if cachy_layout.exists():
    patch_kdl(cachy_layout, accent, muted)

# Focus ring + border must stay OFF: niri draws them as solid rectangles that
# cover semitransparent terminals (killing the blur-through look), and niri
# defaults the ring ON when no block exists (the CachyOS tree defines none).
# Insert explicit off blocks once where absent; configured blocks are never
# touched (a deliberate ring is the user's choice).
def ensure_off_in_layout(path):
    # Niri accepts focus-ring/border ONLY nested inside the top-level layout{}
    # block — top-level nodes are a parse error that kills the whole config.
    # Insert missing off blocks there; configured nodes are never touched.
    try:
        t = path.read_text()
    except OSError:
        return False
    missing = [n for n in ("focus-ring", "border")
               if not re.search(r'^\s*%s\s*\{' % n, t, re.M)]
    if not missing:
        return False
    lines = t.split("\n")
    depth, open_idx, close_idx = 0, None, None
    for i, line in enumerate(lines):
        s = line.strip()
        code = re.sub(r'"[^"]*"', '""', line)
        code = re.sub(r'//.*$', '', code)
        if open_idx is None and re.match(r'^layout\s*\{', s) and depth == 0:
            open_idx = i
        depth += code.count('{') - code.count('}')
        if open_idx is not None and depth == 0:
            close_idx = i
            break
    if open_idx is None or close_idx is None:
        print(f"hexciri-sync: {path.name} has no top-level layout block — rings left alone")
        return False
    ins = ["", "// theme-owned: rings off so borders/rings never cover semitransparent terminals"]
    ins += ["%s {\n    off\n}" % n for n in missing]
    lines = lines[:close_idx] + ins + lines[close_idx:]
    path.write_text("\n".join(lines))
    print(f"hexciri-sync: {path.name}: {', '.join(missing)} off for transparency")
    return True

ring_target = None
if cachy_layout.exists():
    ring_target = cachy_layout
else:
    _ours = Path.home() / ".config" / "niri" / "looknfeel.kdl"
    if _ours.exists():
        ring_target = _ours
if ring_target is not None:
    ensure_off_in_layout(ring_target)

# ── 4. Wallpaper sync ──
# If the user has custom wallpapers merged (zz-user-* links from the store or
# extra dirs list), leave the wallpaper alone — a theme switch must not stomp
# their choice. Without customs, apply the new theme's default background.
if os.environ.get("NOCTALIA_SYNC_NO_WALLPAPER") != "1":
    wp_dir = theme_dir / "backgrounds"
    has_custom = False
    if wp_dir.is_dir():
        has_custom = any(p.name.startswith("zz-user-") for p in wp_dir.iterdir())
    if has_custom:
        print("hexciri-sync: custom user wallpapers present — keeping the current wallpaper")
    elif wp_dir.is_dir():
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
            # Tell Noctalia to apply the wallpaper. Guard against empty/missing
            # sources (e.g. a sandbox HOME or a corrupted theme) — sending such
            # a path would leave the desktop + lockscreen on a black image.
            import subprocess
            if dest.exists() and dest.stat().st_size > 0:
                subprocess.run(["noctalia", "msg", "wallpaper-set", str(dest)], check=False)
                print(f"hexciri-sync: wallpaper → {dest}")
            else:
                print(f"hexciri-sync: skipping wallpaper-set ({dest} missing or empty)")

print(f"hexciri-sync: synced theme '{theme_name}'")
PYEOF
