#!/usr/bin/env bash
# Hexciri fork patch 29: font-set escaping for special-character font names.
# Forward-port of the font-set slice of omarchy PR #19969
# ("Fix hibernation cleanup, CLI flag loops, font escaping, URI/Taildrop
# bugs", commit 4574aa8bb).
#
# What it does (upstream behavior, unchanged): font names containing
# & < > " ' / or backslash no longer break the terminal-config sed edits
# (alacritty/kitty/ghostty/foot) or the fontconfig XML. New sed_escape /
# xml_escape helpers; every sed -i in hexciri-font-set gains
# --follow-symlinks so symlinked terminal configs stay linked (the kitty
# one already had it). Fork note: Devi's font is "Maple Mono NF CN"
# (spaces only, needs no escaping today), but any user font with & or
# quotes would hit it, and the --follow-symlinks half matters because the
# fork's dotfiles symlink terminal configs.
#
# Fork adaptation: renames only (omarchy- -> hexciri- already applied by
# the installer). One fork difference from upstream: patch 02 added a
# second fontconfig <match> block (JetBrainsMono Nerd Font, the
# system-assigned monospace default), so the <string>$font_name</string>
# line occurs TWICE in the fork file; both get $xml_font_name. The patch
# accepts a count of 1 or 2 for that line and replaces all of them.
#
# Deliberately LEFT OUT of commit 4574aa8bb (not a font-set concern):
#   * bin/omarchy-clipboard-open + omarchy-clipboard-paste-text
#     (--history-index missing-value guard, wtype -- separator)
#   * bin/omarchy-hibernation-remove (Limine resume drop-in cleanup;
#     fork has no Limine/btrfs hibernation)
#   * bin/omarchy-tailscale-receive (symlink/-print0 find fixes)
#   * bin/omarchy-transcode (jq percent-encoding of file:// URIs)
#   * bin/omarchy-theme-color --file without a value now errors instead
#     of silently using empty (one-line guard; NOT ported here so this
#     patch stays the font-set slice only — patch 31's theme-color
#     rewrite does not depend on it: no overlapping anchors)
#   * test/shell.d/* (test/ is not in FORK_OUT)
#
# Standalone: bash v2/patches/29-font-set-escaping.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Validation: bash -n on the edited hexciri-font-set (it is shell code;
# no JS/QML is touched, so node --check / qmllint do not apply).
set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "29-font-set-escaping.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Font-set escaping, omarchy PR #19969 (commit 4574aa8bb, font-set slice) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

FONT_SET = "bin/hexciri-font-set"

HELPERS = r'''sed_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//&/\\\&}
  value=${value//\//\\/}
  printf '%s' "$value"
}

xml_escape() {
  local value="$1"
  value=${value//&/\&amp;}
  value=${value//</\&lt;}
  value=${value//>/\&gt;}
  value=${value//\"/\&quot;}
  value=${value//\'/\&apos;}
  printf '%s' "$value"
}

sed_font_name=$(sed_escape "$font_name")
quoted_font_name=${font_name//\\/\\\\}
quoted_font_name=${quoted_font_name//\"/\\\"}
quoted_sed_font_name=$(sed_escape "$quoted_font_name")'''

REPLACEMENTS = [
    (FONT_SET,
     "fi\n\nif [[ -f ~/.config/alacritty/alacritty.toml ]]; then",
     "fi\n\n" + HELPERS + "\n\nif [[ -f ~/.config/alacritty/alacritty.toml ]]; then",
     "font-set: sed_escape/xml_escape helpers"),
    (FONT_SET,
     r'''  sed -i "s/family = \".*\"/family = \"$font_name\"/g" ~/.config/alacritty/alacritty.toml''',
     r'''  sed --follow-symlinks -i "s/family = \".*\"/family = \"$quoted_sed_font_name\"/g" ~/.config/alacritty/alacritty.toml''',
     "font-set: alacritty escapes + follow-symlinks"),
    (FONT_SET,
     r'''    kitty_font_name=$(printf '%s' "$font_name" | sed 's/[\\&/]/\\&/g')
    sed --follow-symlinks -i -E "s/^[[:space:]]*font_family[[:space:]]+.*/font_family $kitty_font_name/" ~/.config/kitty/kitty.conf''',
     r'''    sed --follow-symlinks -i -E "s/^[[:space:]]*font_family[[:space:]]+.*/font_family $sed_font_name/" ~/.config/kitty/kitty.conf''',
     "font-set: kitty uses sed_font_name"),
    (FONT_SET,
     r'''  sed -i "s/font-family = \".*\"/font-family = \"$font_name\"/g" ~/.config/ghostty/config''',
     r'''  sed --follow-symlinks -i "s/font-family = \".*\"/font-family = \"$quoted_sed_font_name\"/g" ~/.config/ghostty/config''',
     "font-set: ghostty escapes + follow-symlinks"),
    (FONT_SET,
     r'''  sed -i "s/^font=.*/font=$font_name:size=$foot_size/g" ~/.config/foot/foot.ini''',
     r'''  sed --follow-symlinks -i "s/^font=.*/font=$sed_font_name:size=$foot_size/g" ~/.config/foot/foot.ini''',
     "font-set: foot escapes + follow-symlinks"),
    (FONT_SET,
     'fontconfig_file="$HOME/.config/fontconfig/fonts.conf"\nmkdir -p "$(dirname "$fontconfig_file")"',
     'fontconfig_file="$HOME/.config/fontconfig/fonts.conf"\nxml_font_name=$(xml_escape "$font_name")\nmkdir -p "$(dirname "$fontconfig_file")"',
     "font-set: xml-escaped font name for fontconfig"),
]

for rel, old, new, label in REPLACEMENTS:
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if new in s:
        print("%s: already present, skipping" % label)
        continue
    if s.count(old) != 1:
        print("ERROR: anchor not found exactly once in %s (count %d): %s" % (rel, s.count(old), label), file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)
    with open(fp, "w") as f:
        f.write(s)
    changed.append(label)

# The fontconfig <string> line occurs once upstream but TWICE in the fork
# (patch 02's second match block for the system-assigned JetBrainsMono
# Nerd Font default); both emit the chosen family, so both get escaped.
fp = root + "/" + FONT_SET
try:
    with open(fp) as f:
        s = f.read()
except FileNotFoundError:
    s = None
if s is not None:
    fc_old = "      <string>$font_name</string>"
    fc_new = "      <string>$xml_font_name</string>"
    if fc_new in s and fc_old not in s:
        print("font-set: fontconfig family already escaped, skipping")
    elif s.count(fc_old) in (1, 2):
        s = s.replace(fc_old, fc_new)
        with open(fp, "w") as f:
            f.write(s)
        changed.append("font-set: fontconfig family XML-escaped (%d block(s))" % s.count(fc_new))
    else:
        print("ERROR: fontconfig <string> anchor count %d in %s (want 1 or 2)" % (s.count(fc_old), FONT_SET), file=sys.stderr)
        sys.exit(1)

for label in changed:
    print("patched: %s" % label)
print("font-set-escaping patch: %d file edits applied" % len(changed))
PY

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist.
if [ -f "$FORK_OUT/bin/hexciri-font-set" ]; then
  bash -n "$FORK_OUT/bin/hexciri-font-set" || die "bash -n failed on patched hexciri-font-set"
fi
info "  font-set-escaping: font names with & < > \" ' / \\ no longer break terminal configs or fontconfig (#19969)"
