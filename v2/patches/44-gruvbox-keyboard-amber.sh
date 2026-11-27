#!/usr/bin/env bash
# Hexciri fork patch 44: gruvbox theme keyboard backlight warm amber.
# Forward-port of omarchy PR #20031 (commit 6ffadc3e1, "gruvbox keyboard.rgb
# warm amber"): new data file themes/gruvbox/keyboard.rgb holding #d8a657.
#
# Why verbatim: the consumers strip a leading '#' themselves, so the '#'
# form is what upstream ships and what the fork's readers expect:
# bin/hexciri-theme-set-keyboard-f16 does hex="${hex#\#}" and validates
# ^[0-9A-Fa-f]{6}$, bin/hexciri-theme-set-keyboard-asus-rog does
# sed 's/^#//'. The sibling file themes/tokyo-night/keyboard.rgb holds
# 'ff00ff' with no '#'; both forms work, upstream chose '#d8a657' here.
#
# No rename: the file holds a colour value only, no omarchy strings.
# Devi's machines: Framework 13 (no per-key RGB; the f16 script is for the
# Framework 16) and the desktop, so this is theme-data completeness, not
# a live behaviour change for him.
#
# Standalone: bash v2/patches/44-gruvbox-keyboard-amber.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose content differs is
#   overwritten, since this is fork-shipped theme data, not user config.
#
# Syntax check note: the edited file is theme data, not code, so the
# end-of-patch check asserts its exact bytes (#d8a657 plus newline).
# bash -n does not apply to a data file and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "44-gruvbox-keyboard-amber.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- gruvbox keyboard.rgb warm amber, omarchy PR #20031 (2026-11-26) ---
if [ ! -d "$FORK_OUT/themes/gruvbox" ]; then
  warn "themes/gruvbox not in fork output, skipping (gruvbox keyboard.rgb)"
elif [ -f "$FORK_OUT/themes/gruvbox/keyboard.rgb" ] && [ "$(cat "$FORK_OUT/themes/gruvbox/keyboard.rgb")" = "#d8a657" ]; then
  printf 'gruvbox keyboard.rgb: already present, skipping\n' >>"$_patch_log"
else
  printf '%s\n' "#d8a657" >"$FORK_OUT/themes/gruvbox/keyboard.rgb"
  printf 'patched: themes/gruvbox/keyboard.rgb created (#d8a657)\n' >>"$_patch_log"
fi

# End-of-patch check: exact bytes, '#d8a657' plus one trailing newline.
if [ -f "$FORK_OUT/themes/gruvbox/keyboard.rgb" ]; then
  [ "$(cat "$FORK_OUT/themes/gruvbox/keyboard.rgb")" = "#d8a657" ] || die "gruvbox keyboard.rgb content is not #d8a657"
  [ "$(wc -c <"$FORK_OUT/themes/gruvbox/keyboard.rgb" | tr -d ' ')" = "8" ] || die "gruvbox keyboard.rgb is not '#d8a657' plus newline"
fi
info "  gruvbox-keyboard-amber: gruvbox keyboard backlight is warm amber #d8a657 (PR #20031)"
