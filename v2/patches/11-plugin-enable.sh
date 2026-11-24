#!/usr/bin/env bash
# Hexciri fork patch 11: hexciri-plugin-enable accepts multiple ids.
# Moved verbatim from v2/install.sh (2026-11-24 patches refactor, Devi:
# "shouldn't all patches have been in a /patches on GH, be cleaner?").
# Behavior is identical, only the location changed: the installer now
# calls v2/patches/apply.sh, which runs these in MANIFEST order.
# Standalone: bash v2/patches/11-plugin-enable.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "11-plugin-enable.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  # Re-run quiet (2026-11-24, Devi: a plain `hexciri update` printed
  # ~500 lines of installer re-run spam, most of them "Kept: ... (already
  # current)" / "already present" / "already correct"). On a re-run those
  # go to the detail log only; changed / failed steps still print, and
  # the one-line "already up to date" status lines (run_pacman) stay on
  # screen, they are the per-step result.
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
# Fork-integrity helpers, verbatim from install.sh (00-compat-alias.sh
# calls bootstrap_ok; hyprlua_ok is here for any patch that needs it).
bootstrap_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 500 ] || return 1
  grep -q 'package.path' "$_f" 2>/dev/null || return 1
  grep -q 'HEXCIRI_PATH' "$_f" 2>/dev/null || return 1
  return 0
}
hyprlua_ok() {
  local _f="$1" _n
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"
  [ "${_n:-0}" -ge 1000 ] || return 1
  grep -q 'require("default.hypr.helpers")' "$_f" 2>/dev/null || return 1
  return 0
}

# --- hexciri-plugin-enable accepts multiple ids (2026-11-24, Nyxiri bar enable bug) ---
# Upstream `plugin enable` takes exactly one id; any second argument is
# placement. Devi ran `hexciri plugin enable pizza.dirty.nyxiri
# pizza.dirty.nyxiri-menu ...` and got "unknown placement option:
# pizza.dirty.clock" (bar first id: the bar guard) and nothing was
# enabled at all. This patch rewrites bin/hexciri-plugin-enable in the
# fork output: several ids with no placement are enabled one by one (a
# bar id switches via `hexciri bar use`, which edits shell.json directly
# and works from tty3; unknown ids error but do not stop the rest), while
# any placement option keeps single-plugin upstream behaviour verbatim.
# Idempotent: the Hexciri marker inside the new script; the anchor
# asserts the file still looks like the renamed upstream script.
PLUGIN_ENABLE_BIN="$FORK_OUT/bin/hexciri-plugin-enable"
if [ -f "$PLUGIN_ENABLE_BIN" ]; then
  python3 - "$PLUGIN_ENABLE_BIN" <<'PY' >>"$_patch_log"
import sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()
new_script = r'''#!/bin/bash

# omarchy:summary=Enable a shell plugin
# omarchy:group=plugin
# omarchy:args=<id>... [placement]
# omarchy:examples=hexciri plugin enable acme.weather --section right | hexciri plugin enable acme.clock acme.weather

set -euo pipefail

fail() {
  echo "hexciri-plugin-enable: $*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: hexciri plugin enable <id>... [placement]"
  echo "  Enable one or more plugins. Placement (--section, --index,"
  echo "  --before, --after, or a positional section) applies to a"
  echo "  single plugin only. A bar plugin switches the active bar:"
  echo "  hexciri bar use <id>"
  exit 0
fi

[[ -n ${1:-} ]] || fail "plugin id is required"

is_bar() {
  hexciri-plugin-catalog | jq -e --arg id "$1" '
    any(.[]; .id == $id and (.kinds | index("bar")))
  ' >/dev/null
}

enable_one() {
  local id="$1" placement="$2" result=""
  if is_bar "$id"; then
    # Hexciri: a bar is enabled by switching to it. `hexciri bar use`
    # edits shell.json directly, so this works even when the shell is
    # not running (tty3), unlike enablePlugin over shell IPC.
    if hexciri bar use "$id" >/dev/null; then
      echo "Now using $id as the bar"
      return 0
    fi
    echo "hexciri-plugin-enable: could not switch to bar '$id'" >&2
    return 1
  fi
  result=$(hexciri-shell shell enablePlugin "$id" "$placement")
  if [[ $result == "unknown" ]]; then
    echo "hexciri-plugin-enable: plugin '$id' is not known; run: hexciri-shell shell rescanPlugins" >&2
    return 1
  elif [[ $result != "ok" ]]; then
    echo "hexciri-plugin-enable: $result" >&2
    return 1
  fi
  if [[ $placement != "{}" ]]; then
    echo "Enabled and moved $id"
  else
    echo "Enabled $id"
  fi
  return 0
}

# Hexciri: enable multiple plugins (2026-11-24). Upstream takes exactly
# one id and treats any second argument as placement, so
# `plugin enable a b c` died with "unknown placement option: c" (and a
# bar as first id died with the bar guard) and enabled nothing at all.
# A placement option (--section/--index/--before/--after, or a positional
# section name as the second argument) still means single-plugin mode,
# with upstream behaviour unchanged.
has_placement=0
for arg in "$@"; do
  case "$arg" in
    --section|--index|--before|--after) has_placement=1 ;;
  esac
done
if (( has_placement == 0 )) && (( $# >= 2 )) && [[ $2 != left && $2 != centerBegin && $2 != center && $2 != centerEnd && $2 != tray && $2 != right ]]; then
  failed=0
  for id in "$@"; do
    enable_one "$id" "{}" || failed=1
  done
  exit "$failed"
fi

# Single-plugin mode: upstream behaviour, verbatim.
id="$1"
shift

if (( $# > 0 )) && is_bar "$id"; then
  fail "'$id' is a bar; it replaces the bar in use rather than taking a place in one"
fi

section=""
index=""
before=""
after=""
if (( $# > 0 )) && [[ $1 != --* ]]; then
  section="$1"
  shift
fi
while (( $# > 0 )); do
  case "$1" in
    --section)
      [[ -z $section ]] || fail "specify a section positionally or with --section, not both"
      section="${2:-}"
      [[ -n $section ]] || fail "--section requires a section"
      shift 2
      ;;
    --index)
      index="${2:-}"
      [[ -n $index ]] || fail "--index requires an index"
      shift 2
      ;;
    --before)
      before="${2:-}"
      [[ -n $before ]] || fail "--before requires a widget id"
      shift 2
      ;;
    --after)
      after="${2:-}"
      [[ -n $after ]] || fail "--after requires a widget id"
      shift 2
      ;;
    *)
      fail "unknown placement option: $1"
      ;;
  esac
done

[[ -z $section || $section =~ ^(left|centerBegin|center|centerEnd|tray|right)$ ]] ||
  fail "section must be left, centerBegin, center, centerEnd, tray, or right"
[[ -z $index || $index =~ ^[0-9]+$ ]] ||
  fail "index must be a non-negative integer"
[[ -z $before || -z $after ]] || fail "use only one of --before or --after"

placement=$(jq -cn \
  --arg section "$section" \
  --arg index "$index" \
  --arg before "$before" \
  --arg after "$after" '
    {}
    + (if $section == "" then {} else {section: $section} end)
    + (if $index == "" then {} else {index: ($index | tonumber)} end)
    + (if $before == "" then {} else {before: $before} end)
    + (if $after == "" then {} else {after: $after} end)
  ')

enable_one "$id" "$placement"'''
if "Hexciri: enable multiple plugins" in s:
    print("plugin-enable: multi-id already present, skipping")
else:
    assert s.count("# omarchy:args=<id> [placement]") == 1, "plugin-enable upstream anchor not found exactly once"
    assert "hexciri-plugin-catalog" in s, "plugin-enable does not look like the renamed upstream script"
    with open(path, "w") as f:
        f.write(new_script)
    print("plugin-enable: rewritten for multiple ids (bar ids via hexciri bar use)")
PY
  bash -n "$PLUGIN_ENABLE_BIN" || die "bash -n failed on patched $PLUGIN_ENABLE_BIN"
  info "  plugin-enable: accepts multiple ids (bar ids switch via hexciri bar use)"
else
  warn "  plugin-enable: bin/hexciri-plugin-enable not in fork output, multi-id enable not patched"
fi
