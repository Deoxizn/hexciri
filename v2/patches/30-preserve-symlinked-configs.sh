#!/usr/bin/env bash
# Hexciri fork patch 30: preserve symlinked user configs.
# Forward-port of omarchy PR #20002 ("Preserve symlinked user configs in
# text-size, glass, Sunshine, RetroArch", commit eb12b54).
#
# What it does (upstream behavior, unchanged): writes that used to replace
# a symlinked config with a regular file now write THROUGH the link, so
# dotfiles-managed configs stay linked:
#   * hexciri-display-text-size: set/reset_base_size switch from
#     `mv tmp -> file` to `cat tmp > file` (only when awk succeeded, and
#     the temp file is removed either way); terminal size seds gain
#     --follow-symlinks (kitty already had it at the pin)
#   * hexciri-theme-set-glass: both sed -i sites (remove_block, glass)
#     gain --follow-symlinks
#   * hexciri-install-gaming-retroarch: set_cfg sed gains
#     --follow-symlinks
#   * hexciri-remove-service-sunshine: hyprland autostart sed gains
#     --follow-symlinks
#
# Fork relevance: the fork's dotfiles symlink configs (text-size shell
# [font] base-size, glass theme files, Sunshine autostart, RetroArch
# retroarch.cfg), so without this a text-size change or glassy toggle
# silently unlinks the dotfiles-managed file.
#
# Fork notes:
#   * hexciri-remove-service-sunshine is NOT in the installer's
#     is_allowed_bin list, so it is normally absent from FORK_OUT and
#     this patch warns and skips that hunk at install time; the hunk is
#     still here so it applies if the file is ever shipped. Adding the
#     file to is_allowed_bin is a separate decision, not this patch.
#   * The glass half interacts with patch 31 (#20131): patch 31 reworks
#     the glassy-off path around these same --follow-symlinks seds, so
#     this patch must land first (it does: 30 < 31).
#   * test/shell.d/* changes in the PR are not ported (test/ is not in
#     FORK_OUT).
#
# Standalone: bash v2/patches/30-preserve-symlinked-configs.sh [FORK_OUT]
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
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "30-preserve-symlinked-configs.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Preserve symlinked configs, omarchy PR #20002 (commit eb12b54) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

TEXT_SIZE = "bin/hexciri-display-text-size"
GLASS = "bin/hexciri-theme-set-glass"
RETROARCH = "bin/hexciri-install-gaming-retroarch"
SUNSHINE = "bin/hexciri-remove-service-sunshine"

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # set_base_size: awk becomes the if condition, mv becomes cat-through.
    (TEXT_SIZE,
     '  awk -v val="$size" \'',
     '  if awk -v val="$size" \'',
     "text-size: set_base_size awk guards the write"),
    (TEXT_SIZE,
     '    }\n  \' "$shell_config" >"$tmp"\n  mv "$tmp" "$shell_config"\n}',
     '    }\n  \' "$shell_config" >"$tmp"; then\n    cat "$tmp" >"$shell_config"\n  fi\n\n  rm -f "$tmp"\n}',
     "text-size: set_base_size writes through the symlink"),
    # reset_base_size: same shape; the awk body (not the bare `awk '` line,
    # which current_base_size also has) makes the anchor unique.
    (TEXT_SIZE,
     r'''  awk '
    /^[[:space:]]*\[/ { in_font = ($0 ~ /^[[:space:]]*\[font\]([[:space:]]|$)/) }
    in_font && /^[[:space:]]*base-size[[:space:]]*=/ { next }
    { print }''',
     r'''  if awk '
    /^[[:space:]]*\[/ { in_font = ($0 ~ /^[[:space:]]*\[font\]([[:space:]]|$)/) }
    in_font && /^[[:space:]]*base-size[[:space:]]*=/ { next }
    { print }''',
     "text-size: reset_base_size awk guards the write"),
    (TEXT_SIZE,
     '    { print }\n  \' "$shell_config" >"$tmp"\n  mv "$tmp" "$shell_config"\n}',
     '    { print }\n  \' "$shell_config" >"$tmp"; then\n    cat "$tmp" >"$shell_config"\n  fi\n\n  rm -f "$tmp"\n}',
     "text-size: reset_base_size writes through the symlink"),
    # Terminal size seds (kitty already had --follow-symlinks at the pin).
    (TEXT_SIZE,
     '    sed -i -E "s/^size[[:space:]]*=.*/size = $pt/" ~/.config/alacritty/alacritty.toml',
     '    sed --follow-symlinks -i -E "s/^size[[:space:]]*=.*/size = $pt/" ~/.config/alacritty/alacritty.toml',
     "text-size: alacritty size follows symlinks"),
    (TEXT_SIZE,
     '    sed -i -E "s/^font-size = .*/font-size = $pt/" ~/.config/ghostty/config',
     '    sed --follow-symlinks -i -E "s/^font-size = .*/font-size = $pt/" ~/.config/ghostty/config',
     "text-size: ghostty size follows symlinks"),
    (TEXT_SIZE,
     r'''    sed -i -E "s/(:size=)[0-9.]+/\1$pt/" ~/.config/foot/foot.ini''',
     r'''    sed --follow-symlinks -i -E "s/(:size=)[0-9.]+/\1$pt/" ~/.config/foot/foot.ini''',
     "text-size: foot size follows symlinks"),
    # Glass: both sed sites (remove_block + glass section insert).
    (GLASS,
     '  sed -i "/^$begin/,/^$end\$/d" "$file" || return 1',
     '  sed --follow-symlinks -i "/^$begin/,/^$end\$/d" "$file" || return 1',
     "glass: remove_block follows symlinks"),
    (GLASS,
     '    sed -i -E "0,/$header/{/$header/r $block',
     '    sed --follow-symlinks -i -E "0,/$header/{/$header/r $block',
     "glass: section insert follows symlinks"),
    # RetroArch: set_cfg writes through a symlinked retroarch.cfg.
    (RETROARCH,
     r'''    sed -i "s|^$key = .*|$key = \"$value\"|" "$CFG"''',
     r'''    sed --follow-symlinks -i "s|^$key = .*|$key = \"$value\"|" "$CFG"''',
     "retroarch: set_cfg follows symlinks"),
    # Sunshine: hyprland autostart removal writes through the link.
    (SUNSHINE,
     r'''    sed -i "\|^$HYPR_AUTOSTART_ENTRY$|d" "$HYPR_AUTOSTART_FILE"''',
     r'''    sed --follow-symlinks -i "\|^$HYPR_AUTOSTART_ENTRY$|d" "$HYPR_AUTOSTART_FILE"''',
     "sunshine: autostart removal follows symlinks"),
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
print("preserve-symlinked-configs patch: %d file edits applied" % len(changed))
PY

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist.
for _f in hexciri-display-text-size hexciri-theme-set-glass hexciri-install-gaming-retroarch hexciri-remove-service-sunshine; do
  if [ -f "$FORK_OUT/bin/$_f" ]; then
    bash -n "$FORK_OUT/bin/$_f" || die "bash -n failed on patched $_f"
  fi
done
unset _f
info "  preserve-symlinked-configs: text-size, glass, RetroArch and Sunshine now write through symlinked configs (#20002)"
