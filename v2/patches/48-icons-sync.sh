#!/usr/bin/env bash
# Hexciri fork patch 48: generic icon theming sync.
# Hexciri-original feature (no upstream PR).
#
# What it does: scans the installed desktop entries (system
# /usr/share/applications, /usr/local/share/applications, and user
# ~/.local/share/applications) and, for every Icon= value with NO hand-made
# template, generates a themed icon from the app's own icon, so the app grid
# stops showing full brand color for apps upstream never templated (live
# examples: HP Device Manager/Scan, Strata, NVIDIA X Server Settings,
# LibreOffice trio, Firewall, OpenRGB). Two output kinds:
# - SVG source -> a .svg.tpl in the user overlay of the current set
#   (~/.config/hexciri/icons/<set>/<name>.svg.tpl), so the existing
#   hexciri-theme-set-icons renderer recolors it on every theme switch
#   (dark colors -> {{ icon_main }}, light colors -> {{ icon_paper }}).
# - Raster source (PNG/XPM/etc.) -> a recolored PNG placed straight into
#   ~/.local/share/icons/hicolor/scalable/apps/<name>.png via
#   magick -channel RGB +level-colors "<icon_main>,<icon_paper>"
#   (alpha untouched). It cannot be a template, so the sync regenerates it
#   whenever the theme changes.
# Hand-made always wins: built-in template > hand-made user-overlay file >
# generated file. Generated files never clobber hand-made ones (only written
# where no template exists, marked with a first-line comment / tracked in
# ~/.local/state/hexciri/current/icons-generated.tsv) and are pruned when the
# app goes away or a hand-made template for it appears. A user-owned file in
# the hicolor output dir is never touched. Idempotent re-runs: a run that
# changes nothing prints nothing and touches no revision.
#
# Triggers: hexciri-theme-set runs it after the visible icon draw (and in
# the headless branch), hexciri-icons-set runs it after a set change, a
# systemd user path unit watches the applications dirs, and it is directly
# runnable as `hexciri icons sync` (dispatcher routes bin/hexciri-icons-sync
# by its # omarchy:summary= metadata) or `hexciri-icons-sync`. Flags:
# --dry-run (plan only) and --force (regenerate all generated files).
# Under the `original` set the sync only removes its own raster PNGs.
#
# Fork adaptations: none beyond the Hexciri paths (the renderer, palette
# and revision scheme are the fork's own; the revision bump replicates patch
# 28 exactly: two fields <draw_rev> <links_rev>, links field only advances
# when hicolor files are added or removed).
#
# Deliberately NOT included:
# - install.sh placement + enable for the systemd path/service units below
#   (same gap as patches 38/39: the fork never installs FORK_OUT/etc/ to
#   the live system, so the units are inert until install.sh gains a
#   placement step -- install -Dm644 + daemon-reload + enable --now of the
#   path unit. The theme-set / icons-set hooks carry the feature until then).
# - A giant pre-included template list (explicitly rejected by Devi: bloat).
# - Recoloring of SVGs that embed a raster <image> (skipped, logged).
# - A lock: a concurrent icon draw always sees a complete file (atomic
#   temp+rename writes); taking the .icons.lock while calling
#   hexciri-theme-set-icons would deadlock, so the sync takes no lock.
#
# Standalone: bash v2/patches/48-icons-sync.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the three edited/created files are bash, so the
# end-of-patch check is bash -n on each. The sync script itself is never
# executed by this patch (it needs a live HOME + theme + magick).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "48-icons-sync.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  if [ "${IS_RERUN:-0}" = "1" ]; then
    case "$1" in
      Kept*|*already\ present*|*already\ correct*|*already\ current*|Theme\ already\ applied:*|*already\ enabled*)
        printf '[hexciri] %s\n' "$1" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
        return 0
        ;;
    esac
  fi
  printf '[hexciri] %s\n' "$1"
}
warn() { printf 'WARN: %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}
CHANGED=0
# Write a new file from stdin; idempotent via content compare, dies rather
# than clobbering a different existing file. $1 = FORK_OUT-relative path,
# $2 = mode (755 for bin/, 644 for config/drop-ins).
install_new_file() {
  local rel="$1" mode="$2" dest tmp
  dest="$FORK_OUT/$rel"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ]; then
    if cmp -s "$tmp" "$dest"; then
      printf '%s: already present, skipping\n' "$rel" >>"$_patch_log"
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
    die "$rel already exists with different content, refusing to clobber it"
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod "$mode" "$dest"
  CHANGED=$((CHANGED + 1))
  printf 'patched: created %s\n' "$rel" >>"$_patch_log"
}
# --- Generic icon theming sync (Hexciri-original, patch 48) ---
install_new_file "bin/hexciri-icons-sync" 755 <<'HEXCIRI_EOF_ICONS_SYNC'
#!/bin/bash

# omarchy:summary=Generate themed icons for installed apps without a template
# omarchy:args=[--dry-run] [--force]
# omarchy:examples=hexciri icons sync | hexciri icons sync --dry-run

# Generated icons for apps the icon set has no template for.
#
# The set only ships templates for the apps its author drew (papercraft: 94).
# Every other installed app shows its packaged icon, full brand color, while
# the templated ones render flat in the theme's colors. This sync closes that
# gap generically, from the installed applications themselves, instead of
# growing a pre-included template list (which would be bloat on its own).
#
# Two kinds of output, and why each lives where it does:
#
# - SVG source icon -> a .svg.tpl in the user overlay of the current set
#   (~/.config/hexciri/icons/<set>/<name>.svg.tpl). The existing renderer
#   (hexciri-theme-set-icons) then draws it on every theme switch, in the
#   new theme's colors, through the same icon roles ({{ icon_main }},
#   {{ icon_paper }}) the hand-made templates use. A generated template
#   therefore recolors itself on theme change with no sync run at all. The
#   rewrite is deliberately flat: every paint color becomes icon_main when
#   dark, icon_paper when light, which keeps figure and ground apart.
#   (python3 stdlib only; no Pillow, no Inkscape, no CairoSVG in the base.)
# - Raster source icon (PNG and friends) -> a recolored PNG placed straight
#   into ~/.local/share/icons/hicolor/scalable/apps/<name>.png. A raster
#   cannot be a template: the renderer only reads .svg/.svg.tpl, and an
#   embedded raster would carry baked-in colors a theme switch could not
#   change. The monochrome recolor (magick +level-colors, dark parts to
#   icon_main, light parts to icon_paper) is the upstream plymouth technique.
#   The PNG is theme-baked, so the sync regenerates it when the theme
#   changes; which theme it was made for is recorded in the state file.
#   The shell's icon index scans ~/.local/share/icons first and takes SVG
#   before PNG, so a hand-made template still wins over a generated PNG.
#
# Hand-made always wins, in this order, and generated files never clobber it:
# a built-in template beats everything; a hand-made user-overlay file beats a
# generated one; a generated file is only written where no template exists,
# is marked (<!-- hexciri-generated: ... -->) so the sync recognizes its own
# work, and is removed when the app goes away or a hand-made template for it
# appears. Files the user put in hicolor themselves are never touched: the
# sync only ever removes PNGs its own state file lists.
#
# Triggers: hexciri-theme-set runs this after the icon draw (new apps since
# the last switch, raster icons for the new theme), hexciri-icons-set runs it
# after a set change, and a systemd user path unit watches the applications
# directories for installs and removals. It is also directly runnable:
# `hexciri icons sync`. --dry-run prints the plan and changes nothing.
# --force regenerates every generated file even when it looks current.
#
# The `original` set means no theming by design, so under it the sync only
# removes its own raster PNGs (the per-set templates are inert there) and
# exits. Writes are atomic (temp file + rename in the same directory), so a
# concurrent icon draw always sees a complete file and no lock is needed.
# A run that changes nothing prints nothing and touches no revision; a run
# that adds or removes hicolor files bumps icons.revision the way
# hexciri-theme-set-icons does (two fields, links field only when links
# changed), so the shell rescans.

CURRENT="$HOME/.local/state/hexciri/current"
THEME_DIR="$CURRENT/theme"
ICONS_DIR="$CURRENT/icons"
LINKS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
STATE_FILE="$CURRENT/icons-generated.tsv"
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"

DESKTOP_DIRS=("/usr/share/applications" "/usr/local/share/applications" "$HOME/.local/share/applications")
ICON_DIRS=("$HOME/.local/share/icons" "/usr/local/share/icons" "/usr/share/icons" "/usr/share/pixmaps")
# Testing seam: colon-separated overrides for the two lists above.
if [[ -n ${HEXCIRI_ICONS_SYNC_DESKTOP_DIRS:-} ]]; then
  IFS=':' read -ra DESKTOP_DIRS <<<"$HEXCIRI_ICONS_SYNC_DESKTOP_DIRS"
fi
if [[ -n ${HEXCIRI_ICONS_SYNC_ICON_DIRS:-} ]]; then
  IFS=':' read -ra ICON_DIRS <<<"$HEXCIRI_ICONS_SYNC_ICON_DIRS"
fi
RASTER_EXTS=("png" "xpm" "jpg" "jpeg" "bmp" "gif" "webp" "ico")

DRY_RUN=0
FORCE=0
GENERATED=0
RECOLORED=0
REMOVED=0
SKIPPED=0
declare -a SKIP_LINES=()
RENDER_NEEDED=0
LINKS_CHANGED=0
ROLES_LOADED=0
ICON_MAIN=""
ICON_PAPER=""
THEME_NAME=""

shopt -s nullglob

usage() {
  echo "Usage: hexciri-icons-sync [--dry-run] [--force]"
  exit "${1:-1}"
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage 0 ;;
    *) echo "icons-sync: unknown argument: $arg" >&2; usage 1 ;;
  esac
done

skip() {
  # skip <icon-name> <reason>: counted always, detailed only with --dry-run.
  SKIPPED=$((SKIPPED + 1))
  SKIP_LINES+=("would skip $1: $2")
}

# Escape glob characters so an icon name is matched literally by find -name.
glob_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\*/\\*}
  s=${s//\?/\\?}
  s=${s//\[/\\[}
  printf '%s' "$s"
}

# Resolve an icon name to a file: prints "<kind> <path>" (kind svg|raster),
# nothing when no usable file exists. SVG wins; otherwise the largest raster.
resolve_icon_file() {
  local name="$1" esc dir f best best_size size
  esc=$(glob_escape "$name")
  for dir in "${ICON_DIRS[@]}"; do
    [[ -d $dir ]] || continue
    f=$(find "$dir" -name "$esc.svg" -type f 2>/dev/null | head -n 1)
    if [[ -n $f ]]; then
      printf 'svg %s\n' "$f"
      return 0
    fi
  done
  best=""
  best_size=-1
  for dir in "${ICON_DIRS[@]}"; do
    [[ -d $dir ]] || continue
    while IFS= read -r -d '' f; do
      size=$(stat -c %s "$f" 2>/dev/null || echo 0)
      if (( size > best_size )); then
        best_size=$size
        best=$f
      fi
    done < <(find "$dir" \( -iname "$esc.png" -o -iname "$esc.xpm" -o -iname "$esc.jpg" -o -iname "$esc.jpeg" -o -iname "$esc.bmp" -o -iname "$esc.gif" -o -iname "$esc.webp" -o -iname "$esc.ico" \) -type f -print0 2>/dev/null)
  done
  if [[ -n $best ]]; then
    printf 'raster %s\n' "$best"
    return 0
  fi
  return 1
}

# Load icon_main + icon_paper for the current theme, through the same
# palette pipeline the template renderer uses. SVG templates do not need
# this (their placeholders resolve at render time); raster recolor does.
load_roles() {
  local roles
  [[ -f $THEME_DIR/colors.toml ]] || return 1
  roles=$( { hexciri-theme-color --file "$THEME_DIR/colors.toml" --all 2>/dev/null; hexciri-theme-color --file "$THEME_DIR/colors.toml" --raw 2>/dev/null | sed 's/^/raw_/'; } | hexciri-theme-icon-palette 2>/dev/null ) || return 1
  ICON_MAIN=$(awk -F '\t' '$1=="icon_main" {print $2}' <<<"$roles")
  ICON_PAPER=$(awk -F '\t' '$1=="icon_paper" {print $2}' <<<"$roles")
  [[ -n $ICON_MAIN && -n $ICON_PAPER ]] || return 1
  ROLES_LOADED=1
  return 0
}

# Rewrite an SVG's paint colors to the icon roles, flat: dark colors become
# {{ icon_main }}, light ones {{ icon_paper }}. Writes the template to $2
# with the generated marker prepended. Exit 0 wrote it, 2 nothing
# recolorable (skip honestly), 1 parse error (skip honestly).
generate_svg_template() {
  local src="$1" dst="$2" name="$3" marker tmp_svg py_err rc
  GEN_FAIL_REASON=""
  marker="<!-- hexciri-generated: source=$src mtime=$(stat -c %Y "$src" 2>/dev/null || echo 0) kind=svg -->"
  tmp_svg=$(mktemp "${dst%/*}/.icons-sync.XXXXXX") || return 1
  py_err=$(mktemp) || { rm -f "$tmp_svg"; return 1; }
  python3 - "$src" "$tmp_svg" 2>"$py_err" <<'PYEOF'
import re
import sys
import xml.etree.ElementTree as ET

NAMED = {
    "white": "#ffffff", "black": "#000000", "red": "#ff0000",
    "green": "#008000", "blue": "#0000ff", "yellow": "#ffff00",
    "cyan": "#00ffff", "aqua": "#00ffff", "magenta": "#ff00ff",
    "fuchsia": "#ff00ff", "gray": "#808080", "grey": "#808080",
    "silver": "#c0c0c0", "maroon": "#800000", "olive": "#808000",
    "lime": "#00ff00", "navy": "#000080", "teal": "#008080",
    "purple": "#800080", "orange": "#ffa500", "pink": "#ffc0cb",
    "brown": "#a52a2a",
}
HEX_RE = re.compile(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b")
RGB_RE = re.compile(r"rgb\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*\)")


def lum(hexcolor):
    r = int(hexcolor[1:3], 16)
    g = int(hexcolor[3:5], 16)
    b = int(hexcolor[5:7], 16)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255


def parse_color(value):
    value = value.strip()
    if value.startswith("#") and len(value) in (4, 7):
        if len(value) == 4:
            value = "#" + value[1] * 2 + value[2] * 2 + value[3] * 2
        return value.lower()
    m = RGB_RE.match(value)
    if m:
        return "#%02x%02x%02x" % tuple(min(255, int(p)) for p in m.groups())
    if value.lower() in NAMED:
        return NAMED[value.lower()]
    return None


def role_for(value):
    value = value.strip()
    if value == "currentColor":
        return "{{ icon_main }}"
    color = parse_color(value)
    if color is None:
        return None
    return "{{ icon_main }}" if lum(color) < 0.5 else "{{ icon_paper }}"


def recolor_css(text, counter):
    def sub(m):
        role = role_for(m.group(0))
        if role is None:
            return m.group(0)
        counter[0] += 1
        return role

    text = HEX_RE.sub(sub, text)
    text = RGB_RE.sub(sub, text)
    return text


src, dst = sys.argv[1], sys.argv[2]
try:
    tree = ET.parse(src)
except Exception as exc:
    print("cannot parse %s: %s" % (src, exc), file=sys.stderr)
    sys.exit(1)
root = tree.getroot()
for el in root.iter():
    if el.tag.endswith("image"):
        print("%s embeds a raster image" % src, file=sys.stderr)
        sys.exit(2)
rewrites = [0]
for el in root.iter():
    for attr in ("fill", "stroke", "stop-color"):
        value = el.get(attr)
        if value is None:
            continue
        value = value.strip()
        if value in ("none", "") or value.startswith("url("):
            continue
        role = role_for(value)
        if role is None:
            continue
        el.set(attr, role)
        rewrites[0] += 1
    style = el.get("style")
    if style:
        decls = []
        changed = False
        for decl in style.split(";"):
            if ":" not in decl:
                decls.append(decl)
                continue
            key, _, val = decl.partition(":")
            key = key.strip()
            if key in ("fill", "stroke", "stop-color"):
                val = val.strip()
                if val not in ("none", "") and not val.startswith("url("):
                    role = role_for(val)
                    if role is not None:
                        decls.append("%s:%s" % (key, role))
                        changed = True
                        rewrites[0] += 1
                        continue
            decls.append(decl)
        if changed:
            el.set("style", ";".join(decls))
    if el.tag.endswith("style") and el.text:
        el.text = recolor_css(el.text, rewrites)
if rewrites[0] == 0:
    sys.exit(2)
ET.register_namespace("", "http://www.w3.org/2000/svg")
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
svg_bytes = ET.tostring(root, encoding="UTF-8", xml_declaration=True)
with open(dst, "wb") as fh:
    fh.write(svg_bytes)
PYEOF
  local rc=$?
  if (( rc != 0 )); then
    GEN_FAIL_REASON=$(<"$py_err")
    rm -f "$tmp_svg" "$py_err"
    return "$rc"
  fi
  rm -f "$py_err"
  { printf '%s\n' "$marker"; cat "$tmp_svg"; } > "${tmp_svg}.tpl"
  rm -f "$tmp_svg"
  mv "${tmp_svg}.tpl" "$dst"
  return 0
}

# Recolor a raster icon to a two-tone in the theme's icon roles, dark parts
# to icon_main, light parts to icon_paper (magick +level-colors, the
# upstream plymouth technique; alpha is untouched, -channel RGB).
generate_raster_png() {
  local src="$1" dst="$2" tmp_png
  command -v magick >/dev/null 2>&1 || return 3
  (( ROLES_LOADED == 1 )) || return 3
  tmp_png=$(mktemp "${dst%/*}/.icons-sync.XXXXXX") || return 1
  if ! MAGICK_MEMORY_LIMIT=512MiB MAGICK_MAP_LIMIT=0 MAGICK_DISK_LIMIT=0 MAGICK_TIME_LIMIT=10 MAGICK_THREAD_LIMIT=2 magick "$src" -channel RGB +level-colors "$ICON_MAIN,$ICON_PAPER" -strip "$tmp_png" 2>/dev/null; then
    rm -f "$tmp_png"
    return 1
  fi
  mv "$tmp_png" "$dst"
  return 0
}

# Same two-field revision hexciri-theme-set-icons writes (patch 28): the
# draw field always advances; the links field only when hicolor files were
# added or removed, so the shell rescans the icon tree exactly then.
bump_icons_revision() {
  local links_changed="$1" draw_rev links_rev prev_links_rev
  draw_rev=${EPOCHREALTIME//[!0-9]/}
  links_rev=0
  if [[ -r $CURRENT/icons.revision ]]; then
    IFS=$'\t ' read -r _ prev_links_rev _ <"$CURRENT/icons.revision" || true
    [[ $prev_links_rev =~ ^[0-9]+$ ]] && links_rev=$prev_links_rev
  fi
  if (( links_changed )); then
    links_rev=$draw_rev
  fi
  printf '%s\t%s\n' "$draw_rev" "$links_rev" >"$CURRENT/icons.revision"
}

# Is this user-overlay template one this sync generated? Sets MARKED_SOURCE
# and MARKED_MTIME when it is.
is_generated_template() {
  local file="$1" first
  MARKED_SOURCE=""
  MARKED_MTIME=""
  [[ -f $file ]] || return 1
  IFS= read -r first <"$file" || return 1
  [[ $first == "<!-- hexciri-generated: "* ]] || return 1
  local marker_re='source=(.*) mtime=([0-9]+) kind=svg -->'
  if [[ $first =~ $marker_re ]]; then
    MARKED_SOURCE="${BASH_REMATCH[1]}"
    MARKED_MTIME="${BASH_REMATCH[2]}"
  fi
  return 0
}

# --- state file (raster PNGs only; SVG templates carry their own marker) ---

declare -A STATE_SOURCE=()
declare -A STATE_MTIME=()
declare -A STATE_THEME=()
STATE_DIRTY=0

load_state() {
  local name kind source mtime theme
  [[ -f $STATE_FILE ]] || return 0
  while IFS=$'\t' read -r name kind source mtime theme; do
    [[ $kind == "raster" ]] || continue
    STATE_SOURCE["$name"]="$source"
    STATE_MTIME["$name"]="$mtime"
    STATE_THEME["$name"]="$theme"
  done <"$STATE_FILE"
}

save_state() {
  local name tmp
  (( STATE_DIRTY == 1 )) || return 0
  (( DRY_RUN == 0 )) || return 0
  tmp=$(mktemp "${STATE_FILE%/*}/.icons-sync.XXXXXX") || return 1
  : >"$tmp"
  for name in "${!STATE_THEME[@]}"; do
    printf '%s\traster\t%s\t%s\t%s\n' "$name" "${STATE_SOURCE[$name]}" "${STATE_MTIME[$name]}" "${STATE_THEME[$name]}" >>"$tmp"
  done
  mv "$tmp" "$STATE_FILE"
}

record_raster() {
  local name="$1" source="$2"
  STATE_SOURCE["$name"]="$source"
  STATE_MTIME["$name"]=$(stat -c %Y "$source" 2>/dev/null || echo 0)
  STATE_THEME["$name"]="$THEME_NAME"
  STATE_DIRTY=1
}

# Remove my generated raster PNG for a name (state-listed only, regular file
# only; a user-owned file or symlink at the path is never touched).
remove_generated_png() {
  local name="$1" png="$LINKS/$name.png"
  [[ -n ${STATE_THEME[$name]:-} ]] || return 1
  if (( DRY_RUN == 1 )); then
    REMOVED=$((REMOVED + 1))
    LINKS_CHANGED=1
    return 0
  fi
  if [[ -f $png && ! -L $png ]]; then
    rm -f "$png"
    LINKS_CHANGED=1
  fi
  unset 'STATE_SOURCE[$name]' 'STATE_MTIME[$name]' 'STATE_THEME[$name]'
  STATE_DIRTY=1
  REMOVED=$((REMOVED + 1))
  return 0
}

# Remove my generated template for a name (marker-checked by the caller).
remove_generated_tpl() {
  local name="$1" tpl="$USER_SET/$name.svg.tpl"
  if (( DRY_RUN == 1 )); then
    REMOVED=$((REMOVED + 1))
    RENDER_NEEDED=1
    return 0
  fi
  rm -f "$tpl"
  REMOVED=$((REMOVED + 1))
  RENDER_NEEDED=1
  return 0
}

template_covers() {
  local name="$1"
  [[ -f $BUILT_IN_SET/$name.svg || -f $BUILT_IN_SET/$name.svg.tpl || -f $USER_SET/$name.svg || -f $USER_SET/$name.svg.tpl ]]
}

ensure_roles() {
  [[ -n ${ROLES_TRIED:-} ]] && return $(( ROLES_LOADED == 1 ? 0 : 1 ))
  ROLES_TRIED=1
  load_roles
}

# --- main ---

SET=$(hexciri-icons-current --id 2>/dev/null || echo papercraft)
[[ -n $SET ]] || SET=papercraft
THEME_NAME=$(cat "$CURRENT/theme.name" 2>/dev/null || echo unknown)
BUILT_IN_SET="$HEXCIRI_PATH/icons/$SET"
USER_SET="$HOME/.config/hexciri/icons/$SET"

load_state

if [[ $SET == "original" ]]; then
  # No theming by design: only my raster PNGs could still show, so drop them.
  for name in "${!STATE_THEME[@]}"; do
    remove_generated_png "$name"
  done
  save_state
  if (( LINKS_CHANGED == 1 )) && (( DRY_RUN == 0 )); then
    bump_icons_revision 1
  fi
  if (( DRY_RUN == 1 )) || (( REMOVED > 0 )); then
    echo "icons-sync: original set, $REMOVED generated raster icons removed"
  fi
  exit 0
fi

if (( DRY_RUN == 0 )); then
  mkdir -p "$USER_SET" "$LINKS" "$CURRENT"
fi

# Installed applications: one Icon= name per app, byte-exact, deduped.
declare -A installed=()
for dir in "${DESKTOP_DIRS[@]}"; do
  [[ -d $dir ]] || continue
  while IFS= read -r -d '' f; do
    type=$(sed -n 's/^Type=//p' "$f" | head -n 1)
    [[ -z $type || $type == "Application" ]] || continue
    [[ $(sed -n 's/^Hidden=//p' "$f" | head -n 1) == "true" ]] && continue
    [[ $(sed -n 's/^NoDisplay=//p' "$f" | head -n 1) == "true" ]] && continue
    icon=$(sed -n 's/^Icon=//p' "$f" | head -n 1)
    icon=${icon%$'\r'}
    icon=${icon%"${icon##*[![:space:]]}"}
    [[ -z $icon ]] && continue
    [[ $icon == */* ]] && continue
    installed["$icon"]=1
  done < <(find "$dir" -name '*.desktop' -type f -print0 2>/dev/null)
done

for name in "${!installed[@]}"; do
  user_tpl="$USER_SET/$name.svg.tpl"
  # A built-in template beats everything; drop my generated files for it.
  if [[ -f $BUILT_IN_SET/$name.svg || -f $BUILT_IN_SET/$name.svg.tpl ]]; then
    if [[ -f $user_tpl ]] && is_generated_template "$user_tpl"; then
      remove_generated_tpl "$name"
    fi
    remove_generated_png "$name" || true
    continue
  fi
  # A user-overlay file: mine gets regenerated when stale, hand-made is left alone.
  if [[ -f $USER_SET/$name.svg || -f $user_tpl ]]; then
    if [[ -f $user_tpl ]] && is_generated_template "$user_tpl"; then
      stale=0
      if (( FORCE == 1 )); then
        stale=1
      elif [[ -n $MARKED_SOURCE ]]; then
        [[ $(stat -c %Y "$MARKED_SOURCE" 2>/dev/null || echo 0) != "$MARKED_MTIME" ]] && stale=1
      fi
      if (( stale == 1 )); then
        if [[ -z $MARKED_SOURCE ]]; then
          skip "$name" "generated template has no recorded source"
          continue
        fi
        if (( DRY_RUN == 1 )); then
          GENERATED=$((GENERATED + 1))
          RENDER_NEEDED=1
          continue
        fi
        if generate_svg_template "$MARKED_SOURCE" "$user_tpl" "$name"; then
          GENERATED=$((GENERATED + 1))
          RENDER_NEEDED=1
        else
          rc=$?
          (( rc == 1 )) && echo "icons-sync: $GEN_FAIL_REASON" >&2
          skip "$name" "${GEN_FAIL_REASON:-nothing recolorable in $MARKED_SOURCE}"
        fi
      fi
    fi
    continue
  fi
  # Not covered: resolve the app's own icon and generate from it.
  resolved=$(resolve_icon_file "$name") || { skip "$name" "no icon file found"; continue; }
  kind=${resolved%% *}
  src=${resolved#* }
  if [[ $kind == "svg" ]]; then
    if (( DRY_RUN == 1 )); then
      GENERATED=$((GENERATED + 1))
      RENDER_NEEDED=1
      continue
    fi
    if generate_svg_template "$src" "$user_tpl" "$name"; then
      GENERATED=$((GENERATED + 1))
      RENDER_NEEDED=1
    else
      rc=$?
      (( rc == 1 )) && echo "icons-sync: $GEN_FAIL_REASON" >&2
      skip "$name" "${GEN_FAIL_REASON:-nothing recolorable in $src}"
    fi
    continue
  fi
  # Raster: needs roles (theme colors) and magick; regenerate when the theme
  # or the source changed, or --force. An existing PNG for this name is
  # refreshed, not duplicated.
  if [[ -n ${STATE_THEME[$name]:-} ]]; then
    stale=0
    if (( FORCE == 1 )); then
      stale=1
    elif [[ ${STATE_THEME[$name]} != "$THEME_NAME" ]]; then
      stale=1
    elif [[ $(stat -c %Y "${STATE_SOURCE[$name]}" 2>/dev/null || echo 0) != "${STATE_MTIME[$name]}" ]]; then
      stale=1
    fi
    (( stale == 0 )) && continue
    src="${STATE_SOURCE[$name]}"
  fi
  # Never recolor an icon onto itself: a source already sitting in the
  # themed output dir would be destroyed by the recolor and then pruned.
  if [[ $src == "$LINKS/$name.png" ]]; then
    skip "$name" "icon already lives in the themed output dir"
    continue
  fi
  if ! ensure_roles; then
    skip "$name" "theme icon roles unreadable, raster recolor unavailable"
    continue
  fi
  if ! command -v magick >/dev/null 2>&1; then
    skip "$name" "magick not installed, raster recolor unavailable"
    continue
  fi
  if (( DRY_RUN == 1 )); then
    RECOLORED=$((RECOLORED + 1))
    LINKS_CHANGED=1
    continue
  fi
  if generate_raster_png "$src" "$LINKS/$name.png"; then
    RECOLORED=$((RECOLORED + 1))
    LINKS_CHANGED=1
    record_raster "$name" "$src"
  else
    skip "$name" "magick could not recolor $src"
  fi
done

# Prune my generated files for apps no longer installed.
for tpl in "$USER_SET"/*.svg.tpl; do
  [[ -f $tpl ]] || continue
  name=${tpl##*/}
  name=${name%.svg.tpl}
  is_generated_template "$tpl" || continue
  [[ -n ${installed[$name]:-} ]] && continue
  remove_generated_tpl "$name"
done
for name in "${!STATE_THEME[@]}"; do
  [[ -n ${installed[$name]:-} ]] && continue
  remove_generated_png "$name" || true
done

save_state

if (( RENDER_NEEDED == 1 )) && (( DRY_RUN == 0 )); then
  # New or removed templates: draw them now, in the current theme's colors.
  hexciri-theme-set-icons || true
fi
if (( LINKS_CHANGED == 1 )) && (( DRY_RUN == 0 )); then
  bump_icons_revision 1
fi

if (( DRY_RUN == 1 )); then
  echo "icons-sync: dry run, $GENERATED templates to generate, $RECOLORED raster icons to recolor, $REMOVED files to remove"
  printf '%s\n' "${SKIP_LINES[@]}"
elif (( GENERATED + RECOLORED + REMOVED > 0 )); then
  echo "icons-sync: $GENERATED generated, $RECOLORED recolored, $REMOVED removed, $SKIPPED skipped"
fi
HEXCIRI_EOF_ICONS_SYNC
install_new_file "etc/systemd/user/hexciri-icons-sync.path" 644 <<'HEXCIRI_EOF_ICONS_SYNC_PATH'
[Unit]
Description=Regenerate themed icons when installed applications change

[Path]
PathChanged=/usr/share/applications
PathChanged=/usr/local/share/applications
PathChanged=%h/.local/share/applications
Unit=hexciri-icons-sync.service

[Install]
WantedBy=default.target
HEXCIRI_EOF_ICONS_SYNC_PATH
install_new_file "etc/systemd/user/hexciri-icons-sync.service" 644 <<'HEXCIRI_EOF_ICONS_SYNC_SERVICE'
[Unit]
Description=Generate themed icons for applications without a hand-made template

[Service]
Type=oneshot
ExecStart=/usr/share/hexciri/bin/hexciri-icons-sync
HEXCIRI_EOF_ICONS_SYNC_SERVICE
PY_COUNT_FILE="$(mktemp)"
export PY_COUNT_FILE
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import os
import sys

root = sys.argv[1]
changed = []

THEME_SET_REL = "bin/hexciri-theme-set"
ICONS_SET_REL = "bin/hexciri-icons-set"


def edit(rel, replacements):
    try:
        with open(root + "/" + rel) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping" % rel)
        return
    for label, old, new in replacements:
        if new in s:
            print("%s: already present, skipping" % label)
            continue
        if s.count(old) != 1:
            print("ERROR: anchor not found exactly once in %s (count %d): %s" % (rel, s.count(old), label), file=sys.stderr)
            sys.exit(1)
        s = s.replace(old, new, 1)
        changed.append(label)
    with open(root + "/" + rel, "w") as f:
        f.write(s)


# hexciri-theme-set: run the sync after the visible icon draw (normal path)
# and in the headless branch. Sequential, never failing the switch: the
# sync reads the drawn icon dir only through the renderer it calls itself,
# and a failure there must not abort a theme change.
edit(THEME_SET_REL, [
    ("theme-set: run icons-sync after the visible icon draw",
     '  run_parallel "${visible_theme_commands[@]}"\n',
     '  run_parallel "${visible_theme_commands[@]}"\n'
     '  # Generate themed icons for apps with no hand-made template (patch 48).\n'
     '  hexciri-icons-sync || true\n'),
    ("theme-set: run icons-sync in the headless branch",
     '  hexciri-theme-set-icons || true\n',
     '  hexciri-theme-set-icons || true\n'
     '  hexciri-icons-sync || true\n'),
])

# hexciri-icons-set: re-theme generated icons after a set change (the new
# set's user overlay may lack generated files the old set had, and raster
# PNGs are set-independent so they survive, but a set change is the natural
# re-check point).
edit(ICONS_SET_REL, [
    ("icons-set: run icons-sync after a set change",
     '# The theme in use supplies the colors the set is drawn in.\nhexciri-theme-set-icons\n',
     '# The theme in use supplies the colors the set is drawn in.\nhexciri-theme-set-icons\n'
     '# Re-theme generated icons for the new set (patch 48).\n'
     'hexciri-icons-sync || true\n'),
])

with open(os.environ["PY_COUNT_FILE"], "w") as f:
    f.write(str(len(changed)))
for label in changed:
    print("patched: %s" % label)
print("icons-sync python edits: %d" % len(changed))
PY
py_edits="$(cat "$PY_COUNT_FILE")"
rm -f "$PY_COUNT_FILE"
total_edits=$((py_edits + CHANGED))
printf 'icons-sync patch: %d file edits applied\n' "$total_edits" >>"$_patch_log"

# Syntax-check the edited/created files. All three are bash.
bash -n "$FORK_OUT/bin/hexciri-icons-sync" || die "bash -n failed on patched hexciri-icons-sync"
bash -n "$FORK_OUT/bin/hexciri-theme-set" || die "bash -n failed on patched hexciri-theme-set"
bash -n "$FORK_OUT/bin/hexciri-icons-set" || die "bash -n failed on patched hexciri-icons-set"
info "  icons-sync: themed icons are now generated for installed apps with no hand-made template (patch 48; systemd path unit still needs an install.sh placement step)"
