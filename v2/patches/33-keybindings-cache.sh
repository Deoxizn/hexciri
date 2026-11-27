#!/usr/bin/env bash
# Hexciri fork patch 33: invalidate keybindings menu cache on Lua
# config edits (upstream omacom/omarchy #20136, commit b5cc04180).
# Cache key v22 -> v23; hashes ~/.config/hypr/**/*.lua plus the default
# bindings tree, because Hyprland reports Lua binds only by an opaque
# dispatcher/number and `hyprctl binds` alone misses edits; batches the
# Hyprland IPC (`hyprctl --batch "j/getoption ... ; devices ; binds"`)
# with fallback to separate calls. Fixes a stale Mod+K menu after bind
# edits; the fork's custom binds are covered by the ~/.config/hypr glob.
#
# Fork notes: landing file CONFIRMED as bin/hexciri-menu-keybindings
# (fork-shell allowlist carries menu-keybindings; hexciri-settings calls
# it; the rename map turns $OMARCHY_PATH into $HEXCIRI_PATH). No
# hexciri-menu-keybindings fold-in exists to worry about.
# LIVE CHECK STILL OPEN (2026-11-26, cannot verify from here): `hyprctl
# --batch` needs a live check against Hyprland 0.57; the ported code falls
# back to separate hyprctl calls when the batch call returns nothing, so a
# missing --batch degrades to the old behaviour, not a breakage.
# Test-only upstream file (test/shell.d/keybindings-menu-test.sh) is NOT
# ported: test/ is not in FORK_OUT.
#
# Standalone: bash v2/patches/33-keybindings-cache.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "33-keybindings-cache.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    ('bin/hexciri-menu-keybindings',
     r'''keybindings_cache_key() {
  local lang hash _
  lang=$(hexciri-language 2>/dev/null) || lang=""

  read -r hash _ < <(
    {
      printf 'v22\n'
      leading_keyboard
      printf '%s\n' "$lang"
      [[ -n $lang ]] && cat "$HEXCIRI_PATH/default/i18n/$lang/keybindings.json" 2>/dev/null
      hyprctl devices 2>/dev/null | grep -F 'active keymap:'
      cat "$key_names_file" 2>/dev/null
      hyprctl binds 2>/dev/null
    } | sha256sum
  )
  printf '%s\n' "$hash"
}

refresh_keybindings_cache() {
''',
     r'''keybindings_cache_key() {
  local lang hash _ batch f
  lang=$(hexciri-language 2>/dev/null) || lang=""

  # Fetch all Hyprland state in one batched IPC call (falls back to separate
  # calls for older Hyprland or test stubs that don't handle --batch).
  batch=$(hyprctl --batch "j/getoption input:kb_layout ; j/getoption input:kb_variant ; devices ; binds" 2>/dev/null || true)

  read -r hash _ < <(
    {
      printf 'v23\n'
      printf '%s\n' "$lang"
      [[ -n $lang ]] && cat "$HEXCIRI_PATH/default/i18n/$lang/keybindings.json" 2>/dev/null
      cat "$key_names_file" 2>/dev/null
      # Hyprland reports Lua binds only by an opaque dispatcher/number, so
      # editing a Lua bind's command leaves `hyprctl binds` unchanged. Hash the
      # Lua config files (including nested regional bindings) scanned by
      # build_lua_bind_cache() too.
      shopt -s nullglob globstar
      for f in "$HOME/.config/hypr"/**/*.lua "$HEXCIRI_PATH/default/hypr/bindings.lua" "$HEXCIRI_PATH/default/hypr/bindings"/**/*.lua; do
        [[ -f $f && -r $f ]] || continue
        printf 'lua:%s\n' "$f"
        cat "$f"
      done
      if [[ -n $batch ]]; then
        printf '%s\n' "$batch"
      else
        leading_keyboard
        hyprctl devices 2>/dev/null | grep -F 'active keymap:'
        hyprctl binds 2>/dev/null
      fi
    } | sha256sum
  )
  printf '%s\n' "$hash"
}

refresh_keybindings_cache() {
''',
     'keybindings_cache_key: v23 + Lua hash + batched hyprctl IPC with fallback'),
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
print("33 patch: %d file edits applied" % len(changed))
PY

# The python block above writes through >>"$_patch_log", a separate open
# file description when _patch_log is /dev/stdout. If this script's stdout
# is a regular file, the shell's fd offset is still where it was before
# python ran, so the validation/info prints below would overwrite the
# start of python's output (observed in sim: the first patched: lines
# were clobbered by the trailing info line). Seek stdout to EOF first;
# a guarded no-op on terminals and pipes, where lseek fails.
python3 -c "import os
try:
    os.lseek(1, 0, os.SEEK_END)
except OSError:
    pass" 2>/dev/null || true

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist.
for _f in hexciri-menu-keybindings; do
  if [ -f "$FORK_OUT/$_f" ]; then
    bash -n "$FORK_OUT/$_f" || die "bash -n failed on patched $_f"
  fi
done
unset _f
info "  keybindings-cache: cache key v23, Lua bind edits invalidate the keybindings menu cache"
