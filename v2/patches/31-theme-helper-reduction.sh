#!/usr/bin/env bash
# Hexciri fork patch 31: theme-helper fork reduction (perf).
# Forward-port of the theme-helper slice of omarchy PR #20131
# ("Eliminate redundant subprocess spawns on Hyprland reload and theme
# helpers", commit c8217b831).
#
# What it does (upstream behavior, unchanged except fork notes below):
#   * hexciri-theme-color: mix_color() rewritten from awk to pure-bash
#     integer math (result via REPLY, not stdout), so every derived
#     shade stops forking awk; `dirname` replaced by parameter
#     expansion; background-luminance sum via 16# arithmetic. The
#     callers in resolve_theme_colors switch from $(mix_color ...) to
#     mix_color ...; VAR="$REPLY". Rounding parity against the awk
#     version was verified in sim (see README): identical over the fork
#     themes' palettes for every amount the callers use (20/25/50%);
#     32 one-off (+1 in one channel) cases at 30%/0.30 where awk's float
#     error rounds a true .5 boundary down and bash matches exact decimal
#     rounding; negative amounts abort with a bash arithmetic error where
#     awk clamped to 0 (no caller passes negatives — amounts are the
#     hardcoded 20/25/50% in resolve_theme_colors). End-to-end --all is
#     byte-identical for all five shipped themes.
#   * hexciri-theme-set-glass: when glassy is off, one `grep -lF`
#     over all theme files instead of a fork per file on every theme
#     switch; glassy-on path unchanged.
#   * hexciri-theme-set-gnome: one `dconf dump` up front, `gsettings
#     set` only when the value changed.
#
# Fork adaptations:
#   * No renames needed in the theme-color/glass hunks beyond the ones
#     the installer already applied ($HEXCIRI_PATH, "# hexciri-glass
#     begin"); this patch ports them as-is.
#   * gnome: the fork's theme-set-gnome is NOT upstream's file — patch
#     07 rewrote it whole (writes gtk-3.0/gtk-4.0 settings.ini, Adwaita
#     in both modes, dconf via dbus-run-session when there is no live
#     bus). Upstream's gsettings if/else block no longer exists, so the
#     hunk is re-expressed on the fork's _set_gtk(): a _current_dconf
#     dump (via dbus-run-session when there is no bus) plus a
#     _set_if_changed helper; _set_gtk calls it for the three keys.
#     When there is neither a bus nor dbus-run-session nothing is
#     written, exactly as before.
#   * Herdr hunk SKIPPED: the fork ships no Herdr (no herdr binary, no
#     theme sync); bin/hexciri-theme-set-herdr-machines exists in the
#     tree but its early-exit/lazy-listing change has nothing to sync.
#
# Deliberately LEFT OUT of commit c8217b831 (out of the theme area,
# belongs to other workers / not a theme helper):
#   * default/hypr/apps.lua (static module list replaces require_all)
#   * default/hypr/bindings/dictation.lua, default/hypr/dictation-backend.lua,
#     default/hypr/require_all.lua (dictation backend read from a file)
#   * test/shell.d/* (test/ is not in FORK_OUT)
#
# Ordering: port AFTER patch 29 (its theme-color base — the --file guard
# from #19969 is deliberately not in patch 29, and patch 31 does not
# depend on it: no overlapping anchors) and patch 30 (glass symlinks:
# patch 31 reworks the glassy-off path around patch 30's
# --follow-symlinks seds; the symlink handling survives — remove_block
# still uses --follow-symlinks).
#
# Standalone: bash v2/patches/31-theme-helper-reduction.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Validation: bash -n on every edited shell file (they are shell code;
# no JS/QML is touched, so node --check / qmllint do not apply).
set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "31-theme-helper-reduction.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Theme-helper reduction, omarchy PR #20131 (commit c8217b831, theme slice) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

COLOR = "bin/hexciri-theme-color"
GLASS = "bin/hexciri-theme-set-glass"
GNOME = "bin/hexciri-theme-set-gnome"

OLD_MIX = r'''# Mix two hex colors. Amount may be a fraction (0.30) or percentage (30%).
mix_color() {
  local start="${1#\#}"
  local end="${2#\#}"
  local amount="$3"

  awk -v start="$start" -v end="$end" -v amount="$amount" '
    function hex_value(char) {
      return index("0123456789abcdef", tolower(char)) - 1
    }

    function hex_pair_to_int(hex, idx) {
      return hex_value(substr(hex, idx, 1)) * 16 + hex_value(substr(hex, idx + 1, 1))
    }

    BEGIN {
      if (amount ~ /%$/) {
        sub(/%$/, "", amount)
        amount = amount / 100
      } else {
        amount += 0
        if (amount > 1) amount = amount / 100
      }

      if (amount < 0) amount = 0
      if (amount > 1) amount = 1

      start_r = hex_pair_to_int(start, 1)
      start_g = hex_pair_to_int(start, 3)
      start_b = hex_pair_to_int(start, 5)
      end_r = hex_pair_to_int(end, 1)
      end_g = hex_pair_to_int(end, 3)
      end_b = hex_pair_to_int(end, 5)

      red = int(start_r * (1 - amount) + end_r * amount + 0.5)
      green = int(start_g * (1 - amount) + end_g * amount + 0.5)
      blue = int(start_b * (1 - amount) + end_b * amount + 0.5)

      printf "#%02x%02x%02x\n", red, green, blue
    }
  '
}'''

NEW_MIX = r'''# Mix two hex colors into REPLY. Amount may be a fraction (0.30) or percentage (30%).
mix_color() {
  local start="${1#\#}"
  local end="${2#\#}"
  local amount="${3%%%}"
  local scaled=0 int_part frac_part start_r start_g start_b end_r end_g end_b red green blue

  [[ $start =~ ^[0-9A-Fa-f]{6}$ ]] || start="000000"
  [[ $end =~ ^[0-9A-Fa-f]{6}$ ]] || end="000000"

  if [[ $3 == *% ]]; then
    if [[ $amount == *.* ]]; then
      int_part=${amount%%.*}
      frac_part="${amount#*.}00"
      scaled=$(( 10#${int_part:-0} * 100 + 10#${frac_part:0:2} ))
    else
      scaled=$(( 10#${amount:-0} * 100 ))
    fi
  elif [[ $amount == *.* ]]; then
    int_part=${amount%%.*}
    frac_part="${amount#*.}0000"
    scaled=$(( 10#${int_part:-0} * 10000 + 10#${frac_part:0:4} ))
    if (( scaled > 10000 )); then
      scaled=$(( scaled / 100 ))
    fi
  else
    scaled=$(( 10#${amount:-0} * 100 ))
    if (( scaled == 100 )); then
      scaled=10000
    fi
  fi

  (( scaled < 0 )) && scaled=0
  (( scaled > 10000 )) && scaled=10000

  start_r=$(( 16#${start:0:2} ))
  start_g=$(( 16#${start:2:2} ))
  start_b=$(( 16#${start:4:2} ))
  end_r=$(( 16#${end:0:2} ))
  end_g=$(( 16#${end:2:2} ))
  end_b=$(( 16#${end:4:2} ))

  red=$(( (start_r * (10000 - scaled) + end_r * scaled + 5000) / 10000 ))
  green=$(( (start_g * (10000 - scaled) + end_g * scaled + 5000) / 10000 ))
  blue=$(( (start_b * (10000 - scaled) + end_b * scaled + 5000) / 10000 ))

  printf -v REPLY '#%02x%02x%02x' "$red" "$green" "$blue"
}'''

OLD_GNOME_SET_GTK = r'''_set_gtk() {
  if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    gsettings set org.gnome.desktop.interface color-scheme "$_scheme"
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
    gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
  elif command -v dbus-run-session >/dev/null 2>&1; then
    dbus-run-session -- gsettings set org.gnome.desktop.interface color-scheme "$_scheme"
    dbus-run-session -- gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
    dbus-run-session -- gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
  fi
}'''

NEW_GNOME_SET_GTK = r'''# One dconf dump up front; gsettings writes only when the value differs
# (#20131: a theme switch used to fork gsettings once per key, unconditionally).
_current_dconf=""
if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  _current_dconf=$(dconf dump /org/gnome/desktop/interface/ 2>/dev/null || true)
elif command -v dbus-run-session >/dev/null 2>&1; then
  _current_dconf=$(dbus-run-session -- dconf dump /org/gnome/desktop/interface/ 2>/dev/null || true)
fi
_set_if_changed() {
  local key="$1" value="$2"
  [[ $'\n'$_current_dconf$'\n' == *$'\n'"$key='$value'"$'\n'* ]] && return 0
  if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    gsettings set org.gnome.desktop.interface "$key" "$value"
  elif command -v dbus-run-session >/dev/null 2>&1; then
    dbus-run-session -- gsettings set org.gnome.desktop.interface "$key" "$value"
  fi
}
_set_gtk() {
  _set_if_changed color-scheme "$_scheme"
  _set_if_changed gtk-theme "Adwaita"
  _set_if_changed icon-theme "Adwaita"
}'''

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    (COLOR,
     'COLORS_DIR=$(dirname "$COLORS_FILE")',
     'if [[ $COLORS_FILE == */* ]]; then\n  COLORS_DIR=${COLORS_FILE%/*}\n  [[ -n $COLORS_DIR ]] || COLORS_DIR="/"\nelse\n  COLORS_DIR="."\nfi',
     "theme-color: dirname fork replaced by parameter expansion"),
    (COLOR,
     OLD_MIX,
     NEW_MIX,
     "theme-color: mix_color awk rewritten as bash integer math"),
    (COLOR,
     '    lum=$(( $(printf "%d" "0x${bg_hex:0:2}") + $(printf "%d" "0x${bg_hex:2:2}") + $(printf "%d" "0x${bg_hex:4:2}") ))',
     '    lum=$(( 16#${bg_hex:0:2} + 16#${bg_hex:2:2} + 16#${bg_hex:4:2} ))',
     "theme-color: luminance sum via 16# arithmetic"),
    (COLOR,
     '  [[ ${THEME_COLORS[brown]} ]]      || THEME_COLORS[brown]=$(mix_color "${THEME_COLORS[orange]}" "#000000" 50%)',
     '  if [[ -z ${THEME_COLORS[brown]} ]]; then mix_color "${THEME_COLORS[orange]}" "#000000" 50%; THEME_COLORS[brown]="$REPLY"; fi',
     "theme-color: brown uses REPLY, no command substitution"),
    (COLOR,
     '  [[ ${THEME_COLORS[dark_background]} ]]   || THEME_COLORS[dark_background]=$(mix_color "${THEME_COLORS[background]}" "#000000" 25%)',
     '  if [[ -z ${THEME_COLORS[dark_background]} ]]; then mix_color "${THEME_COLORS[background]}" "#000000" 25%; THEME_COLORS[dark_background]="$REPLY"; fi',
     "theme-color: dark_background uses REPLY"),
    (COLOR,
     '  [[ ${THEME_COLORS[darker_background]} ]] || THEME_COLORS[darker_background]=$(mix_color "${THEME_COLORS[background]}" "#000000" 50%)',
     '  if [[ -z ${THEME_COLORS[darker_background]} ]]; then mix_color "${THEME_COLORS[background]}" "#000000" 50%; THEME_COLORS[darker_background]="$REPLY"; fi',
     "theme-color: darker_background uses REPLY"),
    (COLOR,
     '  [[ ${THEME_COLORS[bright_red]} ]]    || THEME_COLORS[bright_red]=$(mix_color "${THEME_COLORS[red]}" "#ffffff" 20%)',
     '  if [[ -z ${THEME_COLORS[bright_red]} ]]; then mix_color "${THEME_COLORS[red]}" "#ffffff" 20%; THEME_COLORS[bright_red]="$REPLY"; fi',
     "theme-color: bright_red uses REPLY"),
    (COLOR,
     '  [[ ${THEME_COLORS[bright_yellow]} ]] || THEME_COLORS[bright_yellow]=$(mix_color "${THEME_COLORS[yellow]}" "#ffffff" 20%)',
     '  if [[ -z ${THEME_COLORS[bright_yellow]} ]]; then mix_color "${THEME_COLORS[yellow]}" "#ffffff" 20%; THEME_COLORS[bright_yellow]="$REPLY"; fi',
     "theme-color: bright_yellow uses REPLY"),
    (COLOR,
     '  [[ ${THEME_COLORS[bright_green]} ]]  || THEME_COLORS[bright_green]=$(mix_color "${THEME_COLORS[green]}" "#ffffff" 20%)',
     '  if [[ -z ${THEME_COLORS[bright_green]} ]]; then mix_color "${THEME_COLORS[green]}" "#ffffff" 20%; THEME_COLORS[bright_green]="$REPLY"; fi',
     "theme-color: bright_green uses REPLY"),
    (COLOR,
     '  [[ ${THEME_COLORS[bright_cyan]} ]]   || THEME_COLORS[bright_cyan]=$(mix_color "${THEME_COLORS[cyan]}" "#ffffff" 20%)',
     '  if [[ -z ${THEME_COLORS[bright_cyan]} ]]; then mix_color "${THEME_COLORS[cyan]}" "#ffffff" 20%; THEME_COLORS[bright_cyan]="$REPLY"; fi',
     "theme-color: bright_cyan uses REPLY"),
    (COLOR,
     '  [[ ${THEME_COLORS[bright_blue]} ]]   || THEME_COLORS[bright_blue]=$(mix_color "${THEME_COLORS[blue]}" "#ffffff" 20%)',
     '  if [[ -z ${THEME_COLORS[bright_blue]} ]]; then mix_color "${THEME_COLORS[blue]}" "#ffffff" 20%; THEME_COLORS[bright_blue]="$REPLY"; fi',
     "theme-color: bright_blue uses REPLY"),
    (COLOR,
     '  [[ ${THEME_COLORS[bright_magenta]} ]] || THEME_COLORS[bright_magenta]=$(mix_color "${THEME_COLORS[magenta]}" "#ffffff" 20%)',
     '  if [[ -z ${THEME_COLORS[bright_magenta]} ]]; then mix_color "${THEME_COLORS[magenta]}" "#ffffff" 20%; THEME_COLORS[bright_magenta]="$REPLY"; fi',
     "theme-color: bright_magenta uses REPLY"),
    (GLASS,
     r'''glass foot.ini '[colors-dark]' \
  '^[[:space:]]*blur[[:space:]]*=' 'blur=yes' || status=1
# GTK only asks Hyprland for blur under a CSS backdrop-filter, which Ghostty
# takes as custom CSS and reloads live; its background-blur speaks only KDE's
# blur protocol.
glass ghostty.conf '' \
  '' "gtk-custom-css = $HEXCIRI_PATH/default/gtk/glass.css" || status=1

# Glassy used to give these a see-through background of their own as well,
# which doubled up with the window fade. Glassing them with no settings takes
# out a block an earlier glassy left in the current theme.
for file in alacritty.toml kitty.conf btop.theme; do
  glass "$file" '' || status=1
done''',
     r'''if [[ $GLASSY == "true" ]]; then
  glass foot.ini '[colors-dark]' \
    '^[[:space:]]*blur[[:space:]]*=' 'blur=yes' || status=1
  # GTK only asks Hyprland for blur under a CSS backdrop-filter, which Ghostty
  # takes as custom CSS and reloads live; its background-blur speaks only KDE's
  # blur protocol.
  glass ghostty.conf '' \
    '' "gtk-custom-css = $HEXCIRI_PATH/default/gtk/glass.css" || status=1

  # Glassy used to give these a see-through background of their own as well,
  # which doubled up with the window fade. Glassing them with no settings takes
  # out a block an earlier glassy left in the current theme.
  for file in alacritty.toml kitty.conf btop.theme; do
    glass "$file" '' || status=1
  done
else
  # When glassy is off, scan all theme files in a single grep rather than
  # forking once per file on every theme switch.
  candidates=()
  for file in foot.ini ghostty.conf alacritty.toml kitty.conf btop.theme; do
    [[ -f $THEME_DIR/$file ]] && candidates+=("$THEME_DIR/$file")
  done
  if (( ${#candidates[@]} > 0 )); then
    while IFS= read -r matched; do
      remove_block "$matched" "#" "" || status=1
    done < <(grep -lF "# hexciri-glass begin" "${candidates[@]}" 2>/dev/null || true)
  fi
fi''',
     "glass: glassy-off scans once with grep -lF instead of a fork per file"),
    (GNOME,
     OLD_GNOME_SET_GTK,
     NEW_GNOME_SET_GTK,
     "gnome: one dconf dump, gsettings only when changed (fork _set_gtk adaptation)"),
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

for label in changed:
    print("patched: %s" % label)
print("theme-helper-reduction patch: %d file edits applied" % len(changed))
PY

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist.
for _f in hexciri-theme-color hexciri-theme-set-glass hexciri-theme-set-gnome; do
  if [ -f "$FORK_OUT/bin/$_f" ]; then
    bash -n "$FORK_OUT/bin/$_f" || die "bash -n failed on patched $_f"
  fi
done
unset _f
info "  theme-helper-reduction: theme-color is awk-free, glass scans once, gnome sets only on change (#20131)"
