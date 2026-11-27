#!/usr/bin/env bash
# Hexciri fork patch 49: icons-sync fixes (three fixes on top of patch 48).
# Hexciri-original (no upstream PR).
#
# Fix 1 — marker placement: patch 48 prepended the <!-- hexciri-generated -->
# marker BEFORE the <?xml ...?> declaration, which is not well-formed XML
# ("XML or text declaration not at start of entity") and Qt's SVG loader
# rejected the file, so 7 apps showed as blank grid cells live (Calculator,
# Firewall, kitty, Passwords and Keys, Polychromatic, Volume Control,
# Zathura). The marker now goes AFTER the declaration, generated output is
# validated as well-formed XML before it is written, and the sync self-heals
# existing patch-48 templates (marker on line 1 forces regeneration). A
# template with no marker at all (e.g. the sed recovery) is treated as
# hand-made and left alone.
#
# Fix 2 — absolute-path Icon=: patch 48 silently skipped entries whose Icon=
# was an absolute path (live: Battle.net, HP Device Manager, HP Scan). The
# icon file at that path is now the source (SVG -> template, raster ->
# magick recolor), keyed by basename-without-extension and deduped by source
# path, so two entries sharing one file generate once. Entries are repointed
# at the themed file: local entries rewritten in place, system entries get
# a local override copy shadowing them (the system file is never edited),
# tracked in icons-abspath.tsv. Theme changes regenerate the themed file at
# the same stable path; removing the app prunes the themed file and any
# sync-created override without touching user-owned files.
#
# Fix 3 — omarchy/current/icons compat symlink: the Nyxiri workspaces bar
# reads themed icons from ~/.local/state/omarchy/current/icons, so the sync
# ensures that icons dir is a symlink to ~/.local/state/hexciri/current/icons.
# ONLY the icons dir is linked: Strata's follow feature reads theme.name and
# theme/colors.toml under omarchy/current (verified against Strata's
# omarchy_state.rs: read-only, symlink-aware), and the whole current/ dir is
# deliberately left exactly as the user set it up in v1. A real directory at
# icons/ is replaced only when empty (rmdir is the guard); a non-empty one
# is left alone with a warning.
#
# What this patch does NOT do: no systemd placement step (same gap as
# patches 38/39/48: the units are inert until install.sh gains a placement
# step; the theme-set / icons-set hooks carry the feature until then), and
# no change to the theme-set / icons-set hook calls (they already run the
# sync). This patch replaces bin/hexciri-icons-sync wholesale: the three
# fixes touch most of the file, so anchored edits would be a dozen fragile
# anchors for no benefit. The replace is guarded: the file must already be
# the patch-48 version (fingerprint line below), otherwise the patch dies
# rather than clobbering unknown content.
#
# Standalone: bash v2/patches/49-icons-sync-fixes.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.
#
# Syntax check note: the replaced file is bash, so the end-of-patch check
# is bash -n on it. The sync script itself is never executed by this patch
# (it needs a live HOME + theme + magick).

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "49-icons-sync-fixes.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
# Replace an existing fork file with new content from stdin; idempotent via
# content compare. $1 = FORK_OUT-relative path, $2 = mode (755 for bin/),
# $3 = fingerprint string that must be present in the current file (proves
# it is the version this patch was written against). A missing file dies
# (patch 48 must be applied first); a present file without the fingerprint
# dies rather than clobbering unknown content.
replace_file() {
  local rel="$1" mode="$2" fingerprint="$3" dest tmp
  dest="$FORK_OUT/$rel"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ ! -f "$dest" ]; then
    rm -f "$tmp"
    die "$rel not found in fork output, patch 48 must be applied first"
  fi
  if cmp -s "$tmp" "$dest"; then
    printf '%s: already present, skipping\n' "$rel" >>"$_patch_log"
    rm -f "$tmp"
    return 0
  fi
  if ! grep -qF "$fingerprint" "$dest"; then
    rm -f "$tmp"
    die "$rel does not look like the patch-48 version, refusing to clobber it"
  fi
  mv "$tmp" "$dest"
  chmod "$mode" "$dest"
  CHANGED=$((CHANGED + 1))
  printf 'patched: replaced %s\n' "$rel" >>"$_patch_log"
}
# --- Icons-sync fixes (Hexciri-original, patch 49) ---
replace_file "bin/hexciri-icons-sync" 755 'cat "$tmp_svg"; } > "${tmp_svg}.tpl"' <<'HEXCIRI_EOF_ICONS_SYNC'
#!/bin/bash

# omarchy:summary=Generate themed icons for installed apps without a template
# omarchy:args=[--dry-run] [--force]
# omarchy:examples=hexciri icons sync | hexciri icons sync --dry-run

# Patch 49 (three fixes on top of patch 48):
# 1. The generated marker now goes AFTER the <?xml ...?> declaration. Patch
#    48 prepended it, which is not well-formed XML ("XML or text
#    declaration not at start of entity") and Qt's SVG loader rejected the
#    file, so 7 apps showed as blank grid cells. The sync also self-heals
#    existing patch-48 templates: a marker on line 1 forces regeneration.
#    Generated output is validated as well-formed XML before it is written.
#    A template with no marker at all (e.g. the sed recovery) is treated
#    as hand-made and left alone.
# 2. Absolute-path Icon= values are no longer skipped: the icon file at
#    that path is the source (SVG -> template, raster -> magick recolor),
#    keyed by basename-without-extension and deduped by source path, so
#    two entries sharing one file (HP Device Manager + HP Scan share
#    hp_logo.png) generate once. The themed file must actually be used,
#    so entries are repointed at it: local entries are rewritten in place,
#    system entries get a local override copy shadowing them (the system
#    file is never edited), and every repoint is tracked in
#    icons-abspath.tsv so theme changes, removals and restores stay exact.
# 3. The Nyxiri workspaces bar reads themed icons from the old path
#    ~/.local/state/omarchy/current/icons, so the sync ensures that icons
#    dir is a symlink to ~/.local/state/hexciri/current/icons. ONLY the
#    icons dir is linked: Strata's follow feature reads theme.name and
#    theme/colors.toml under omarchy/current (verified against Strata's
#    omarchy_state.rs: read-only, symlink-aware), and the whole current/
#    dir is deliberately left exactly as the user set it up. A real
#    directory at icons/ is replaced only when empty (rmdir is the guard).

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
# Every run also ensures the omarchy/current/icons compat symlink (fix 3).
#
# The `original` set means no theming by design, so under it the sync only
# removes its own raster PNGs and restores absolute-path repoints (the
# per-set templates are inert there) and exits. Writes are atomic (temp file
# + rename in the same directory), so a
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
ABS_STATE_FILE="$CURRENT/icons-abspath.tsv"
# The Nyxiri workspaces bar reads themed icons from the old Omarchy state
# path; only the icons dir is linked, never the whole current/ (see the
# patch-49 note above: Strata's follow feature owns theme.name/colors.toml
# under omarchy/current).
OMARCHY_ICONS_LINK="$HOME/.local/state/omarchy/current/icons"
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

USER_APPS_DIR="$HOME/.local/share/applications"
# Absolute-path bookkeeping (patch 49): structures the scan fills and the
# claim phase consumes. Declared here so helpers can reference them.
declare -A KEY_OWNER=()
declare -A abs_entry_source=()
declare -A abs_sources=()
declare -A abs_desktop_for=()
declare -A abs_installed=()

DRY_RUN=0
FORCE=0
GENERATED=0
RECOLORED=0
REMOVED=0
REPOINTED=0
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
# with the generated marker after the XML declaration (patch 49: a marker
# before the declaration is not well-formed XML and Qt rejects the file).
# The emitted bytes are validated as well-formed before they are written.
# Exit 0 wrote it, 2 nothing recolorable (skip honestly), 1 parse error
# (skip honestly).
generate_svg_template() {
  local src="$1" dst="$2" name="$3" marker tmp_svg py_err rc
  GEN_FAIL_REASON=""
  marker="<!-- hexciri-generated: source=$src mtime=$(stat -c %Y "$src" 2>/dev/null || echo 0) kind=svg -->"
  tmp_svg=$(mktemp "${dst%/*}/.icons-sync.XXXXXX") || return 1
  py_err=$(mktemp) || { rm -f "$tmp_svg"; return 1; }
  python3 - "$src" "$tmp_svg" "$marker" 2>"$py_err" <<'PYEOF'
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


src, dst, marker = sys.argv[1], sys.argv[2], sys.argv[3]
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
# Patch 49: the marker goes AFTER the XML declaration. A comment before it
# makes the document not well-formed ("XML or text declaration not at start
# of entity") and Qt's SVG loader rejects the file, which blanked 7 apps.
marker_bytes = marker.encode("UTF-8")
decl_end = svg_bytes.find(b"?>")
if decl_end != -1:
    out = svg_bytes[:decl_end + 2] + b"\n" + marker_bytes + b"\n" + svg_bytes[decl_end + 2:].lstrip(b"\n")
else:
    out = marker_bytes + b"\n" + svg_bytes
# Prove the emitted bytes are well-formed before they ever reach the disk.
ET.fromstring(out)
with open(dst, "wb") as fh:
    fh.write(out)
PYEOF
  local rc=$?
  if (( rc != 0 )); then
    GEN_FAIL_REASON=$(<"$py_err")
    rm -f "$tmp_svg" "$py_err"
    return "$rc"
  fi
  rm -f "$py_err"
  mv "$tmp_svg" "$dst"
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

# Is this user-overlay template one this sync generated? Sets MARKED_SOURCE,
# MARKED_MTIME and MARKED_LINE when it is: 1 means the marker sits before
# the XML declaration (the patch-48 layout Qt rejects: not well-formed),
# 2 means after it (the patch-49 layout). A template with no marker is
# hand-made (or sed-recovered) and is left alone.
is_generated_template() {
  local file="$1" first second marker_re
  MARKED_SOURCE=""
  MARKED_MTIME=""
  MARKED_LINE=0
  [[ -f $file ]] || return 1
  first=$(head -n 1 "$file")
  second=$(sed -n '2p' "$file")
  marker_re='source=(.*) mtime=([0-9]+) kind=svg -->'
  if [[ $first == "<!-- hexciri-generated: "* ]]; then
    MARKED_LINE=1
  elif [[ $second == "<!-- hexciri-generated: "* ]]; then
    MARKED_LINE=2
    first="$second"
  else
    return 1
  fi
  if [[ $first =~ $marker_re ]]; then
    MARKED_SOURCE="${BASH_REMATCH[1]}"
    MARKED_MTIME="${BASH_REMATCH[2]}"
  fi
  return 0
}

# --- state files ---
# icons-generated.tsv: raster PNGs only (name, kind, source, mtime, theme).
# SVG templates carry their own marker. icons-abspath.tsv (patch 49) tracks
# absolute-path repoints, one row per desktop entry (see below).

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

# --- absolute-path state (icons-abspath.tsv, patch 49) ---
# One row per desktop entry the sync repointed, keyed by "<key>|<desktop>":
# key <tab> kind <tab> source <tab> desktop <tab> override <tab> orig_icon
# <tab> sys_desktop <tab> sys_mtime
# kind is svg|raster; desktop is the file carrying the repoint (the local
# entry for override=0, the sync-created override copy for override=1);
# orig_icon is the Icon= value before the repoint, so an in-place repoint
# can be restored; sys_desktop/sys_mtime track the system file an override
# shadows, so a changed or removed system file refreshes or drops it.
declare -A ABS_KIND=()
declare -A ABS_SOURCE=()
declare -A ABS_OVERRIDE=()
declare -A ABS_ORIG=()
declare -A ABS_SYS=()
declare -A ABS_SYS_MTIME=()
ABS_DIRTY=0
ABS_FOUND_KEY=""
ABS_FOUND_DESKTOP=""

load_abs_state() {
  local key kind source desktop override orig sys sys_mtime rk
  [[ -f $ABS_STATE_FILE ]] || return 0
  while IFS=$'\t' read -r key kind source desktop override orig sys sys_mtime; do
    [[ -n $key && -n $desktop ]] || continue
    rk="$key|$desktop"
    ABS_KIND["$rk"]="$kind"
    ABS_SOURCE["$rk"]="$source"
    ABS_OVERRIDE["$rk"]="$override"
    ABS_ORIG["$rk"]="$orig"
    ABS_SYS["$rk"]="$sys"
    ABS_SYS_MTIME["$rk"]="$sys_mtime"
  done <"$ABS_STATE_FILE"
}

save_abs_state() {
  local rk tmp
  (( ABS_DIRTY == 1 )) || return 0
  (( DRY_RUN == 0 )) || return 0
  tmp=$(mktemp "${ABS_STATE_FILE%/*}/.icons-sync.XXXXXX") || return 1
  : >"$tmp"
  for rk in "${!ABS_KIND[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${rk%%|*}" "${ABS_KIND[$rk]}" "${ABS_SOURCE[$rk]}" "${rk#*|}" "${ABS_OVERRIDE[$rk]}" "${ABS_ORIG[$rk]}" "${ABS_SYS[$rk]}" "${ABS_SYS_MTIME[$rk]}" >>"$tmp"
  done
  LC_ALL=C sort -o "$tmp" "$tmp"
  mv "$tmp" "$ABS_STATE_FILE"
}

# Record (or refresh) a repoint row; only marks the state dirty when a
# field actually changed, so a no-op run rewrites nothing.
record_abs_row() {
  local key="$1" kind="$2" source="$3" desktop="$4" override="$5" orig="$6" sys="$7" sys_mtime="$8" rk
  rk="$key|$desktop"
  if [[ ${ABS_KIND[$rk]:-} == "$kind" && ${ABS_SOURCE[$rk]:-} == "$source" && ${ABS_OVERRIDE[$rk]:-} == "$override" && ${ABS_ORIG[$rk]:-} == "$orig" && ${ABS_SYS[$rk]:-} == "$sys" && ${ABS_SYS_MTIME[$rk]:-} == "$sys_mtime" ]]; then
    return 0
  fi
  ABS_KIND["$rk"]="$kind"
  ABS_SOURCE["$rk"]="$source"
  ABS_OVERRIDE["$rk"]="$override"
  ABS_ORIG["$rk"]="$orig"
  ABS_SYS["$rk"]="$sys"
  ABS_SYS_MTIME["$rk"]="$sys_mtime"
  ABS_DIRTY=1
}

drop_abs_row() {
  local rk="$1"
  unset 'ABS_KIND[$rk]' 'ABS_SOURCE[$rk]' 'ABS_OVERRIDE[$rk]' 'ABS_ORIG[$rk]' 'ABS_SYS[$rk]' 'ABS_SYS_MTIME[$rk]'
  ABS_DIRTY=1
}

# Find the row for a desktop file (sets ABS_FOUND_KEY). 0 found, 1 not.
find_abs_row_by_desktop() {
  local desktop="$1" rk
  ABS_FOUND_KEY=""
  for rk in "${!ABS_KIND[@]}"; do
    if [[ ${rk#*|} == "$desktop" ]]; then
      ABS_FOUND_KEY="${rk%%|*}"
      return 0
    fi
  done
  return 1
}

# Find the row shadowing a system file (sets ABS_FOUND_KEY/DESKTOP).
find_abs_row_by_sys() {
  local sys="$1" rk
  ABS_FOUND_KEY=""
  ABS_FOUND_DESKTOP=""
  for rk in "${!ABS_SYS[@]}"; do
    if [[ ${ABS_SYS[$rk]} == "$sys" ]]; then
      ABS_FOUND_KEY="${rk%%|*}"
      ABS_FOUND_DESKTOP="${rk#*|}"
      return 0
    fi
  done
  return 1
}

# First Icon= value of a desktop file, normalized like the main scan does.
read_icon() {
  local v
  v=$(sed -n 's/^Icon=//p' "$1" | head -n 1)
  v=${v%$'\r'}
  v=${v%"${v##*[![:space:]]}"}
  printf '%s' "$v"
}

# Escape a value for the replacement side of a sed s||| command.
sed_repl_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//&/\\&}
  s=${s//|/\\|}
  printf '%s' "$s"
}

# Is this local override copy one this sync created? (First line marker.)
override_is_generated() {
  local first
  [[ -f $1 ]] || return 1
  IFS= read -r first <"$1" || return 1
  [[ $first == "# hexciri-generated-override: "* ]]
}

# Stable output key for an absolute icon source: basename without extension,
# sanitized; suffixed with a short hash of the source path on collision so
# two sources never share one themed file.
key_for_source() {
  local src="$1" base key owner
  base=${src##*/}
  base=${base%.*}
  base=${base//[^A-Za-z0-9._-]/-}
  [[ -n $base ]] || base="icon"
  key="$base"
  owner=${KEY_OWNER[$key]:-}
  if [[ -n $owner && $owner != "path:$src" ]]; then
    key="$base-$(printf '%s' "$src" | sha256sum | cut -c1-8)"
  fi
  KEY_OWNER["$key"]="path:$src"
  printf '%s' "$key"
}

# Generate (or dry-run-plan) an SVG template. 0 ok/planned, 1 skipped.
plan_or_generate_svg() {
  local src="$1" dst="$2" key="$3" rc
  if (( DRY_RUN == 1 )); then
    GENERATED=$((GENERATED + 1))
    RENDER_NEEDED=1
    return 0
  fi
  if generate_svg_template "$src" "$dst" "$key"; then
    GENERATED=$((GENERATED + 1))
    RENDER_NEEDED=1
    return 0
  fi
  rc=$?
  (( rc == 1 )) && echo "icons-sync: $GEN_FAIL_REASON" >&2
  skip "$key" "${GEN_FAIL_REASON:-nothing recolorable in $src}"
  return 1
}

# Recolor (or dry-run-plan) a raster icon. 0 ok/planned, 1 skipped.
plan_or_generate_raster() {
  local src="$1" key="$2"
  if [[ $src == "$LINKS/$key.png" ]]; then
    skip "$key" "icon already lives in the themed output dir"
    return 1
  fi
  if ! ensure_roles; then
    skip "$key" "theme icon roles unreadable, raster recolor unavailable"
    return 1
  fi
  if ! command -v magick >/dev/null 2>&1; then
    skip "$key" "magick not installed, raster recolor unavailable"
    return 1
  fi
  if (( DRY_RUN == 1 )); then
    RECOLORED=$((RECOLORED + 1))
    LINKS_CHANGED=1
    return 0
  fi
  if generate_raster_png "$src" "$LINKS/$key.png"; then
    RECOLORED=$((RECOLORED + 1))
    LINKS_CHANGED=1
    record_raster "$key" "$src"
    return 0
  fi
  skip "$key" "magick could not recolor $src"
  return 1
}

# Repoint one desktop entry at its themed icon. $1 source, $2 key,
# $3 kind (svg|raster), $4 desktop file, $5 themed target path.
# Local entries are rewritten in place; system entries get a local override
# copy shadowing them (the system file is never edited). Only sync-created
# overrides are ever updated or removed. 0 ok, 1 skipped.
repoint_desktop_entry() {
  local src="$1" key="$2" kind="$3" desktop="$4" target="$5"
  local cur override_path desired tmp
  [[ -f $desktop ]] || return 0
  # A row keyed by this desktop with a different key means the key moved
  # (a name-based app claimed the old one): drop the stale row; the prune
  # pass sorts out the old themed file.
  if find_abs_row_by_desktop "$desktop"; then
    if [[ $ABS_FOUND_KEY != "$key" ]]; then
      drop_abs_row "$ABS_FOUND_KEY|$desktop"
    fi
  fi
  if [[ $desktop == "$USER_APPS_DIR/"* ]]; then
    cur=$(read_icon "$desktop")
    if [[ $cur == "$target" ]]; then
      return 0
    fi
    if [[ $cur != "$src" ]]; then
      # The user changed Icon= to something else: stop owning this entry.
      if find_abs_row_by_desktop "$desktop"; then
        drop_abs_row "$ABS_FOUND_KEY|$desktop"
      fi
      return 0
    fi
    if (( DRY_RUN == 1 )); then
      REPOINTED=$((REPOINTED + 1))
      return 0
    fi
    tmp=$(mktemp "${desktop%/*}/.icons-sync.XXXXXX") || return 1
    if ! sed "0,/^Icon=/s|^Icon=.*|Icon=$(sed_repl_escape "$target")|" "$desktop" >"$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    chmod --reference="$desktop" "$tmp"
    mv "$tmp" "$desktop"
    REPOINTED=$((REPOINTED + 1))
    record_abs_row "$key" "$kind" "$src" "$desktop" 0 "$src" "" ""
    return 0
  fi
  # System entry: shadow it with a local override copy.
  override_path="$USER_APPS_DIR/${desktop##*/}"
  # An existing override without our marker is the user's own: never touch.
  if [[ -f $override_path ]] && ! override_is_generated "$override_path"; then
    skip "$key" "local override $override_path is user-owned, leaving it alone"
    return 1
  fi
  # Adopt the row recorded against this system file, if any.
  if find_abs_row_by_sys "$desktop"; then
    if [[ $ABS_FOUND_KEY != "$key" ]]; then
      drop_abs_row "$ABS_FOUND_KEY|${ABS_FOUND_DESKTOP}"
    fi
  fi
  desired=$(mktemp) || return 1
  {
    printf '# hexciri-generated-override: source=%s\n' "$desktop"
    sed "0,/^Icon=/s|^Icon=.*|Icon=$(sed_repl_escape "$target")|" "$desktop"
  } >"$desired" || { rm -f "$desired"; return 1; }
  if [[ -f $override_path ]] && cmp -s "$desired" "$override_path"; then
    rm -f "$desired"
    record_abs_row "$key" "$kind" "$src" "$override_path" 1 "$src" "$desktop" "$(stat -c %Y "$desktop" 2>/dev/null || echo 0)"
    return 0
  fi
  if (( DRY_RUN == 1 )); then
    rm -f "$desired"
    REPOINTED=$((REPOINTED + 1))
    return 0
  fi
  chmod --reference="$desktop" "$desired"
  mv "$desired" "$override_path"
  REPOINTED=$((REPOINTED + 1))
  record_abs_row "$key" "$kind" "$src" "$override_path" 1 "$src" "$desktop" "$(stat -c %Y "$desktop" 2>/dev/null || echo 0)"
  return 0
}

# Restore one repoint record (original set): local entries get their
# original Icon= back, sync-created overrides are removed.
restore_abs_row() {
  local rk="$1" key desktop kind orig target cur tmp
  key=${rk%%|*}
  desktop=${rk#*|}
  kind=${ABS_KIND[$rk]}
  orig=${ABS_ORIG[$rk]}
  if [[ $kind == "svg" ]]; then target="$ICONS_DIR/$key.svg"; else target="$LINKS/$key.png"; fi
  if [[ ${ABS_OVERRIDE[$rk]} == "1" ]]; then
    if [[ -f $desktop ]] && override_is_generated "$desktop"; then
      if (( DRY_RUN == 1 )); then
        REMOVED=$((REMOVED + 1))
      else
        rm -f "$desktop"
        REMOVED=$((REMOVED + 1))
      fi
    fi
  else
    if [[ -f $desktop ]]; then
      cur=$(read_icon "$desktop")
      if [[ $cur == "$target" ]]; then
        if (( DRY_RUN == 1 )); then
          REPOINTED=$((REPOINTED + 1))
        else
          tmp=$(mktemp "${desktop%/*}/.icons-sync.XXXXXX") || return 1
          if sed "0,/^Icon=/s|^Icon=.*|Icon=$(sed_repl_escape "$orig")|" "$desktop" >"$tmp"; then
            chmod --reference="$desktop" "$tmp"
            mv "$tmp" "$desktop"
            REPOINTED=$((REPOINTED + 1))
          else
            rm -f "$tmp"
          fi
        fi
      fi
    fi
  fi
  if (( DRY_RUN == 0 )); then
    drop_abs_row "$rk"
  fi
}

# Ensure ~/.local/state/omarchy/current/icons links at the hexciri rendered
# icons (patch 49, fix 3). The Nyxiri workspaces bar reads themed icons
# from that old path. ONLY the icons dir is linked: Strata's follow feature
# reads theme.name and theme/colors.toml under omarchy/current (verified
# against Strata's omarchy_state.rs: read-only and symlink-aware), and the
# whole current/ dir is deliberately left as the user set it up in v1.
# A dangling link is correct when the hexciri icon draw has not run yet;
# the hexciri side is never created here.
ensure_omarchy_icons_link() {
  local target="$ICONS_DIR" link="$OMARCHY_ICONS_LINK" current
  if [[ -L $link ]]; then
    current=$(readlink "$link")
    if [[ $current == "$target" ]]; then
      return 0
    fi
    if (( DRY_RUN == 1 )); then
      echo "icons-sync: dry run, would repoint $link to $target"
      return 0
    fi
    ln -sfn "$target" "$link"
    echo "icons-sync: repointed $link to $target"
    return 0
  fi
  if [[ -e $link ]]; then
    if [[ -d $link ]]; then
      # Empty directory only: rmdir is the guard, never in a dry run.
      if (( DRY_RUN == 1 )); then
        if find "$link" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
          echo "icons-sync: warning: $link is a non-empty directory, leaving it alone" >&2
          return 0
        fi
        echo "icons-sync: dry run, would replace empty directory $link with a symlink to $target"
        return 0
      fi
      if rmdir "$link" 2>/dev/null; then
        ln -s "$target" "$link"
        echo "icons-sync: replaced empty directory $link with a symlink to $target"
        return 0
      fi
      echo "icons-sync: warning: $link is a non-empty directory, leaving it alone" >&2
      return 0
    fi
    echo "icons-sync: warning: $link exists and is not a directory or symlink, leaving it alone" >&2
    return 0
  fi
  if (( DRY_RUN == 1 )); then
    echo "icons-sync: dry run, would link $link to $target"
    return 0
  fi
  mkdir -p "$(dirname "$link")"
  ln -s "$target" "$link"
  echo "icons-sync: linked $link to $target"
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
load_abs_state

ensure_omarchy_icons_link

if [[ $SET == "original" ]]; then
  # No theming by design: only my raster PNGs could still show, so drop them.
  for name in "${!STATE_THEME[@]}"; do
    remove_generated_png "$name"
  done
  # Repoints would dangle with no themed icons: restore local entries to
  # their original Icon= and drop sync-created overrides.
  for rk in "${!ABS_KIND[@]}"; do
    restore_abs_row "$rk"
  done
  save_state
  save_abs_state
  if (( LINKS_CHANGED == 1 )) && (( DRY_RUN == 0 )); then
    bump_icons_revision 1
  fi
  if (( DRY_RUN == 1 )) || (( REMOVED + REPOINTED > 0 )); then
    echo "icons-sync: original set, $REMOVED generated raster icons removed, $REPOINTED repoints restored"
  fi
  exit 0
fi

if (( DRY_RUN == 0 )); then
  mkdir -p "$USER_SET" "$LINKS" "$CURRENT" "$USER_APPS_DIR"
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
    if [[ $icon == /* ]]; then
      # Absolute-path icon (patch 49): keyed by source path, not by name.
      # An Icon= already pointing at a themed file this sync produced is
      # resolved back to its recorded original through the state file.
      if [[ $icon == "$ICONS_DIR/"* || $icon == "$LINKS/"* ]]; then
        if find_abs_row_by_desktop "$f"; then
          icon="${ABS_ORIG["$ABS_FOUND_KEY|$f"]}"
          [[ -n $icon ]] || continue
        else
          # No record: keep the themed file alive so the entry does not
          # dangle, and say so; the sync cannot regenerate it blind.
          _keep=${icon##*/}
          _keep=${_keep%.svg}
          _keep=${_keep%.png}
          abs_installed["$_keep"]=1
          skip "$_keep" "Icon points into the themed output dir with no sync record, leaving the themed file in place"
          continue
        fi
      fi
      abs_entry_source["$f"]="$icon"
      abs_sources["$icon"]=1
      abs_desktop_for["$icon|$f"]=1
      continue
    fi
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
      elif (( MARKED_LINE == 1 )); then
        # Patch 49 self-heal: marker before the declaration is not
        # well-formed XML; regenerate with the marker after it.
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

# --- absolute-path icons (patch 49) ---
# Name-based entries claim their key first (the key is the icon name);
# absolute sources then claim basename-without-extension, deduped by source
# path, with a -<sha8 of the path> suffix on collision so two sources never
# share one themed file. Order is deterministic: sorted names, then sorted
# sources.
if (( ${#installed[@]} > 0 )); then
  mapfile -t _sorted_names < <(printf '%s\n' "${!installed[@]}" | LC_ALL=C sort)
  for _name in "${_sorted_names[@]}"; do
    KEY_OWNER["$_name"]="name:$_name"
  done
fi
if (( ${#abs_sources[@]} > 0 )); then
  mapfile -t _sorted_sources < <(printf '%s\n' "${!abs_sources[@]}" | LC_ALL=C sort)
else
  _sorted_sources=()
fi
for _src in "${_sorted_sources[@]}"; do
  _ext=${_src##*.}
  _ext=${_ext,,}
  case "$_ext" in
    svg) _kind=svg ;;
    png|xpm|jpg|jpeg|bmp|gif|webp|ico) _kind=raster ;;
    *)
      skip "$(basename "$_src")" "absolute icon $_src has an unsupported type"
      continue
      ;;
  esac
  if [[ ! -f "$_src" ]]; then
    skip "$(basename "$_src")" "absolute icon $_src not found"
    continue
  fi
  _key=$(key_for_source "$_src")
  abs_installed["$_key"]=1
  _tpl="$USER_SET/$_key.svg.tpl"
  if [[ $_kind == "svg" ]]; then
    if [[ -f $USER_SET/$_key.svg || -f $_tpl ]]; then
      if [[ -f $_tpl ]] && is_generated_template "$_tpl"; then
        _stale=0
        if (( FORCE == 1 )); then _stale=1; fi
        if (( MARKED_LINE == 1 )); then _stale=1; fi
        if [[ -z $MARKED_SOURCE ]]; then _stale=1; fi
        if [[ -n $MARKED_SOURCE && $MARKED_SOURCE != "$_src" ]]; then _stale=1; fi
        if [[ -n $MARKED_SOURCE && $(stat -c %Y "$_src" 2>/dev/null || echo 0) != "$MARKED_MTIME" ]]; then _stale=1; fi
        if (( _stale == 1 )) && ! plan_or_generate_svg "$_src" "$_tpl" "$_key"; then
          [[ -f $_tpl ]] || continue
        fi
      fi
      # Otherwise a hand-made or built-in template owns the key; the
      # renderer still draws it, so the repoint below can use it.
    else
      plan_or_generate_svg "$_src" "$_tpl" "$_key" || continue
    fi
    _target="$ICONS_DIR/$_key.svg"
  else
    _need=1
    if [[ -n ${STATE_THEME[$_key]:-} && ${STATE_SOURCE[$_key]:-} == "$_src" ]]; then
      _stale=0
      if (( FORCE == 1 )); then _stale=1; fi
      if [[ ${STATE_THEME[$_key]} != "$THEME_NAME" ]]; then _stale=1; fi
      if [[ $(stat -c %Y "$_src" 2>/dev/null || echo 0) != "${STATE_MTIME[$_key]}" ]]; then _stale=1; fi
      if (( _stale == 0 )); then _need=0; fi
    fi
    if (( _need == 1 )) && ! plan_or_generate_raster "$_src" "$_key"; then
      [[ -f $LINKS/$_key.png ]] || continue
    fi
    _target="$LINKS/$_key.png"
  fi
  # Repoint every desktop entry that uses this source at the themed file.
  for _rk in "${!abs_desktop_for[@]}"; do
    [[ ${_rk%%|*} == "$_src" ]] || continue
    repoint_desktop_entry "$_src" "$_key" "$_kind" "${_rk#*|}" "$_target" || true
  done
done

# Prune my generated files for apps no longer installed.
for tpl in "$USER_SET"/*.svg.tpl; do
  [[ -f $tpl ]] || continue
  name=${tpl##*/}
  name=${name%.svg.tpl}
  is_generated_template "$tpl" || continue
  [[ -n ${installed[$name]:-} ]] && continue
  [[ -n ${abs_installed[$name]:-} ]] && continue
  remove_generated_tpl "$name"
done
for name in "${!STATE_THEME[@]}"; do
  [[ -n ${installed[$name]:-} ]] && continue
  [[ -n ${abs_installed[$name]:-} ]] && continue
  remove_generated_png "$name" || true
done

# Drop repoint records whose desktop entry is gone or moved on. A row is
# kept only while its entry still references the recorded source or the
# themed target; an override row additionally needs its system file to
# still exist and still point at the recorded source.
for _rk in "${!ABS_KIND[@]}"; do
  _key=${_rk%%|*}
  _desktop=${_rk#*|}
  _kind=${ABS_KIND[$_rk]}
  _orig=${ABS_ORIG[$_rk]}
  if [[ $_kind == "svg" ]]; then _target="$ICONS_DIR/$_key.svg"; else _target="$LINKS/$_key.png"; fi
  if [[ ${ABS_OVERRIDE[$_rk]} == "1" ]]; then
    _sys=${ABS_SYS[$_rk]}
    if [[ ! -f "$_sys" ]]; then
      if [[ -f "$_desktop" ]] && override_is_generated "$_desktop"; then
        if (( DRY_RUN == 1 )); then REMOVED=$((REMOVED + 1)); else rm -f "$_desktop"; REMOVED=$((REMOVED + 1)); fi
      fi
      drop_abs_row "$_rk"
      continue
    fi
    if [[ ! -f "$_desktop" ]]; then
      drop_abs_row "$_rk"
      continue
    fi
    if [[ $(read_icon "$_sys") != "$_orig" ]]; then
      if override_is_generated "$_desktop"; then
        if (( DRY_RUN == 1 )); then REMOVED=$((REMOVED + 1)); else rm -f "$_desktop"; REMOVED=$((REMOVED + 1)); fi
      fi
      drop_abs_row "$_rk"
      continue
    fi
    if ! override_is_generated "$_desktop"; then
      drop_abs_row "$_rk"
      continue
    fi
    _cur=$(read_icon "$_desktop")
    if [[ $_cur != "$_orig" && $_cur != "$_target" ]]; then
      drop_abs_row "$_rk"
      continue
    fi
  else
    if [[ ! -f "$_desktop" ]]; then
      drop_abs_row "$_rk"
      continue
    fi
    _cur=$(read_icon "$_desktop")
    if [[ $_cur != "$_orig" && $_cur != "$_target" ]]; then
      drop_abs_row "$_rk"
      continue
    fi
  fi
done

# An absolute-path SVG repoint is only valid once its template is drawn;
# if the rendered file is missing, draw it below.
for _rk in "${!ABS_KIND[@]}"; do
  [[ ${ABS_KIND[$_rk]} == "svg" ]] || continue
  [[ -f $ICONS_DIR/${_rk%%|*}.svg ]] || RENDER_NEEDED=1
done

save_state
save_abs_state

if (( RENDER_NEEDED == 1 )) && (( DRY_RUN == 0 )); then
  # New or removed templates: draw them now, in the current theme's colors.
  hexciri-theme-set-icons || true
fi
if (( LINKS_CHANGED == 1 )) && (( DRY_RUN == 0 )); then
  bump_icons_revision 1
fi

if (( DRY_RUN == 1 )); then
  echo "icons-sync: dry run, $GENERATED templates to generate, $RECOLORED raster icons to recolor, $REMOVED files to remove, $REPOINTED entries to repoint"
  printf '%s\n' "${SKIP_LINES[@]}"
elif (( GENERATED + RECOLORED + REMOVED + REPOINTED > 0 )); then
  echo "icons-sync: $GENERATED generated, $RECOLORED recolored, $REMOVED removed, $REPOINTED repointed, $SKIPPED skipped"
fi
HEXCIRI_EOF_ICONS_SYNC

printf 'icons-sync fixes patch: %d file edits applied\n' "$CHANGED" >>"$_patch_log"

# Syntax-check the replaced file.
bash -n "$FORK_OUT/bin/hexciri-icons-sync" || die "bash -n failed on patched hexciri-icons-sync"
info "  icons-sync fixes: marker after the XML declaration (self-healing), absolute-path Icon= support, omarchy/current/icons compat symlink (patch 49)"
