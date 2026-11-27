#!/usr/bin/env bash
# Hexciri fork patch 67: terminal fast path for --app-id and TUI launches (upstream #20400, Devi 2026-11-27).
# Upstream PR: https://github.com/omacom/omarchy/pull/20400 (diff verified 2026-11-27).
#
# Upstream extends bin/omarchy-launch-terminal's plain-launch fast path (which
# already resolved the default terminal straight from xdg-terminals.list to
# skip xdg-terminal-exec's ~10ms shell scan) to simple --app-id / command
# launches, saving ~10-15ms per TUI launch, and repoints
# bin/omarchy-launch-tui at it instead of calling xdg-terminal-exec directly.
# A new --dir=<dir> option skips the terminal-cwd lookup when the caller
# already knows the directory. Any other leading option (--title, --hold, ...)
# or a desktop entry without the needed X-TerminalArg* keys still falls back
# to xdg-terminal-exec, unchanged.
#
# Fork renames applied to the upstream diff (verified against live nyx
# install.sh rename map, 2026-11-27):
# - omarchy-cmd-terminal-cwd -> hexciri-cmd-terminal-cwd
# - omarchy-launch-terminal -> hexciri-launch-terminal
# - OMARCHY_PATH -> HEXCIRI_PATH, with the fork's usual
#   ${HEXCIRI_PATH:-/usr/share/hexciri} fallback in launch-tui (upstream
#   assumes OMARCHY_PATH is set; the fork never relies on a bare variable).
# - org.omarchy.<cmd> -> org.hexciri.<cmd> in launch-tui's default app id
#   (already renamed in the fork; the line itself is untouched here).
# Upstream's test-only changes are not ported: the fork does not ship test/.
#
# Whether the fast path actually engages on Devi's machines depends on the
# default terminal's desktop entry declaring X-TerminalArgAppId /
# TerminalArgExec. The fork default is kitty (xdg-terminals.list carries
# kitty.desktop after the rename map) and kitty's shipped desktop entry was
# NOT verified here to declare those keys; if it does not, launches fall
# back to xdg-terminal-exec exactly as before, no behaviour change. Worth a
# live check of /usr/share/applications/kitty.desktop before expecting the
# speedup. Foot (still installed as an option) declares neither key in the
# fork's applications/foot.desktop either, so it falls back too.
#
# Standalone: bash v2/patches/67-terminal-fastpath.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "67-terminal-fastpath.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
die() { printf 'ERROR: %s\n' "67-terminal-fastpath.sh: $1" >&2; exit 1; }
CHANGED=0

# --- 1. bin/hexciri-launch-terminal + bin/hexciri-launch-tui ---
# Every replacement below asserts its old block occurs exactly once in the
# pinned (94a8c3c) file; a drifted live file dies loudly instead of silently
# half-applying. Blocks are the upstream diff's hunks with the fork renames
# from the header above.
step "Adding the --app-id / TUI fast path to the terminal launcher"
_PY_OUT="$(mktemp)"
python3 - "$FORK_OUT" >"$_PY_OUT" 2>&1 <<'PY' || { cat "$_PY_OUT" >&2; rm -f "$_PY_OUT"; die "patch 67 terminal edit failed"; }
import sys

fork = sys.argv[1]
term = fork + "/bin/hexciri-launch-terminal"
tui = fork + "/bin/hexciri-launch-tui"


def _die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def _replace_once(text, old, new, where):
    if text.count(old) != 1:
        _die("anchor occurs %d times in %s, want exactly 1: %s" % (text.count(old), where, old.splitlines()[0][:80]))
    return text.replace(old, new, 1)


try:
    with open(term, encoding="utf-8") as f:
        raw = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % term)

try:
    with open(tui, encoding="utf-8") as f:
        tui_raw = f.read()
except FileNotFoundError:
    _die("%s not found in fork output" % tui)

MARKER = "can_fast_path=1"
if MARKER in raw:
    print("launch-terminal: fast path already present, skipping")
else:
    raw = _replace_once(raw, r'''# omarchy:args=[--pid=<terminal-pid>] [command...]''',
                        r'''# omarchy:args=[--pid=<terminal-pid>] [--dir=<dir>] [command...]''', term)
    raw = _replace_once(raw, r'''pid=""
if [[ ${1:-} == --pid=* ]]; then
  pid=${1#--pid=}
  shift
fi

cwd=$(hexciri-cmd-terminal-cwd "$pid")''',
                        r'''pid=""
dir_override=""
fast_app_id=""
fast_cmd=()
fallback_args=()
can_fast_path=1

# Parse --pid=/--dir= plus optional --app-id=<id> and -e/-- command in one pass.
# Any other leading option (such as --title or --hold) falls back to xdg-terminal-exec.
while (($# > 0)); do
  case "$1" in
    --pid=*)
      pid=${1#--pid=}
      shift
      ;;
    --dir=*)
      dir_override=${1#--dir=}
      shift
      ;;
    --app-id=?*)
      fast_app_id=${1#--app-id=}
      fallback_args+=("$1")
      shift
      ;;
    -e | --)
      fallback_args+=("$@")
      shift
      fast_cmd=("$@")
      (( ${#fast_cmd[@]} > 0 )) || can_fast_path=0
      break
      ;;
    -*)
      can_fast_path=0
      fallback_args+=("$@")
      break
      ;;
    *)
      fast_cmd=("$@")
      fallback_args+=("$@")
      break
      ;;
  esac
done

if [[ -n $dir_override ]]; then
  cwd=$dir_override
else
  cwd=$(hexciri-cmd-terminal-cwd "$pid")
fi''', term)
    raw = _replace_once(raw, r'''# Resolve the default terminal directly from xdg-terminals.list on a plain
# launch (Super+Return) to avoid xdg-terminal-exec's ~10ms shell scan.
# Custom options, command arguments, or non-simple desktop entries fall through
# to xdg-terminal-exec.''',
                        r'''# Resolve the default terminal directly from xdg-terminals.list for plain
# launches (Super+Return) and simple --app-id / command launches (TUIs, Herdr)
# to avoid xdg-terminal-exec's shell scan (~10-15ms saved).
# Other xdg-terminal-exec options or non-simple desktop entries fall through
# to xdg-terminal-exec.''', term)
    raw = _replace_once(raw, r'''  local in_entry try_exec exec_line dir_arg''',
                        r'''  local in_entry try_exec exec_line dir_arg app_id_arg exec_arg''', term)
    raw = _replace_once(raw, r'''          in_entry=0
          try_exec=""
          exec_line=""
          dir_arg=""''',
                        r'''          in_entry=0
          try_exec=""
          exec_line=""
          dir_arg=""
          app_id_arg=""
          exec_arg=""''', term)
    raw = _replace_once(raw, r'''                X-TerminalArgDir=*) dir_arg=${line#X-TerminalArgDir=} ;;
                TerminalArgDir=*) [[ -z $dir_arg ]] && dir_arg=${line#TerminalArgDir=} ;;''',
                        r'''                X-TerminalArgDir=*) dir_arg=${line#X-TerminalArgDir=} ;;
                TerminalArgDir=*) [[ -z $dir_arg ]] && dir_arg=${line#TerminalArgDir=} ;;
                X-TerminalArgAppId=*) app_id_arg=${line#X-TerminalArgAppId=} ;;
                TerminalArgAppId=*) [[ -z $app_id_arg ]] && app_id_arg=${line#TerminalArgAppId=} ;;
                X-TerminalArgExec=*) exec_arg=${line#X-TerminalArgExec=} ;;
                TerminalArgExec=*) [[ -z $exec_arg ]] && exec_arg=${line#TerminalArgExec=} ;;''', term)
    raw = _replace_once(raw, r'''          # Only fast-path simple single-token Exec= and simple dir arg (no args,
          # quotes, escapes, or field codes)
          [[ -n $exec_line && $exec_line != *[[:space:]\"\'\\\%]* ]] || return 1
          [[ $dir_arg != *[[:space:]\"\'\\]* ]] || return 1''',
                        r'''          # Only fast-path simple single-token Exec= and simple arg specs (no
          # spaces, quotes, escapes, or field codes)
          [[ -n $exec_line && $exec_line != *[[:space:]\"\'\\\%]* ]] || return 1
          [[ $dir_arg != *[[:space:]\"\'\\]* ]] || return 1
          [[ $app_id_arg != *[[:space:]\"\'\\]* ]] || return 1
          [[ $exec_arg != *[[:space:]\"\'\\]* ]] || return 1''', term)
    raw = _replace_once(raw, r'''          TERMINAL_EXEC=$exec_line
          TERMINAL_DIR_ARG=$dir_arg
          return 0''',
                        r'''          TERMINAL_EXEC=$exec_line
          TERMINAL_DIR_ARG=$dir_arg
          TERMINAL_APP_ID_ARG=$app_id_arg
          TERMINAL_EXEC_ARG=$exec_arg
          return 0''', term)
    raw = _replace_once(raw, r'''if (($# == 0)) && resolve_plain_terminal; then
  if [[ -n $TERMINAL_DIR_ARG ]]; then
    if [[ $TERMINAL_DIR_ARG == *= ]]; then
      exec setsid uwsm-app -- "$TERMINAL_EXEC" "${TERMINAL_DIR_ARG}${cwd}"
    else
      exec setsid uwsm-app -- "$TERMINAL_EXEC" "$TERMINAL_DIR_ARG" "$cwd"
    fi
  else
    cd "$cwd" || true
    exec setsid uwsm-app -- "$TERMINAL_EXEC"
  fi
else
  exec setsid uwsm-app -- xdg-terminal-exec --dir="$cwd" "$@"
fi''',
                        r'''if (( can_fast_path )) && resolve_plain_terminal &&
  [[ -z $fast_app_id || -n $TERMINAL_APP_ID_ARG ]] &&
  { (( ${#fast_cmd[@]} == 0 )) || [[ -n $TERMINAL_EXEC_ARG && $TERMINAL_EXEC_ARG != *= ]]; }; then
  term_args=()
  if [[ -n $TERMINAL_DIR_ARG ]]; then
    if [[ $TERMINAL_DIR_ARG == *= ]]; then
      term_args+=("${TERMINAL_DIR_ARG}${cwd}")
    else
      term_args+=("$TERMINAL_DIR_ARG" "$cwd")
    fi
  else
    cd "$cwd" || true
  fi

  if [[ -n $fast_app_id ]]; then
    if [[ $TERMINAL_APP_ID_ARG == *= ]]; then
      term_args+=("${TERMINAL_APP_ID_ARG}${fast_app_id}")
    else
      term_args+=("$TERMINAL_APP_ID_ARG" "$fast_app_id")
    fi
  fi

  if (( ${#fast_cmd[@]} > 0 )); then
    term_args+=("$TERMINAL_EXEC_ARG" "${fast_cmd[@]}")
  fi

  exec setsid uwsm-app -- "$TERMINAL_EXEC" "${term_args[@]}"
else
  exec setsid uwsm-app -- xdg-terminal-exec --dir="$cwd" "${fallback_args[@]}"
fi''', term)
    with open(term, "w", encoding="utf-8") as f:
        f.write(raw)
    print("patched: terminal fast path in bin/hexciri-launch-terminal")

TUI_MARKER = "hexciri-launch-terminal"
if TUI_MARKER in tui_raw:
    print("launch-tui: already routes through hexciri-launch-terminal, skipping")
else:
    tui_raw = _replace_once(tui_raw,
                            r'''exec setsid uwsm-app -- xdg-terminal-exec --app-id=$APP_ID -e "$1" "${@:2}"''',
                            r'''exec "${HEXCIRI_PATH:-/usr/share/hexciri}/bin/hexciri-launch-terminal" --dir="$PWD" --app-id="$APP_ID" -e "$1" "${@:2}"''',
                            tui)
    with open(tui, "w", encoding="utf-8") as f:
        f.write(tui_raw)
    print("patched: launch-tui routes through hexciri-launch-terminal")

with open(term, encoding="utf-8") as f:
    raw = f.read()
with open(tui, encoding="utf-8") as f:
    tui_raw = f.read()
for needle in ("can_fast_path=1", "TERMINAL_APP_ID_ARG=$app_id_arg", "TERMINAL_EXEC_ARG=$exec_arg",
               "fallback_args", "--dir=<dir>", "hexciri-cmd-terminal-cwd"):
    if needle not in raw:
        _die("launch-terminal lost %r after edit" % needle)
if raw.count("can_fast_path=1") != 1:
    _die("can_fast_path marker occurs %d times after edit" % raw.count("can_fast_path=1"))
if "(($# == 0)) && resolve_plain_terminal" in raw:
    _die("old plain-only fast-path guard still present after edit")
if '"$@"' in raw.split("exec setsid uwsm-app -- xdg-terminal-exec")[1]:
    _die("fallback exec still passes raw \"$@\" instead of fallback_args")
if "xdg-terminal-exec" in tui_raw:
    _die("launch-tui still calls xdg-terminal-exec directly after edit (it must route through launch-terminal)")
if "hexciri-launch-terminal" not in tui_raw or "setsid uwsm-app -- xdg-terminal-exec" in tui_raw:
    _die("launch-tui does not route through hexciri-launch-terminal after edit")
print("terminal fast path validates (%d + %d lines)" % (len(raw.splitlines()), len(tui_raw.splitlines())))
PY
cat "$_PY_OUT" >>"$_patch_log"
_PY_EDITS=$(grep -c '^patched: ' "$_PY_OUT" || true)
CHANGED=$((CHANGED + _PY_EDITS))
rm -f "$_PY_OUT"

# bash syntax check on both edited scripts: a bad edit here would break
# every terminal launch (Super+Return, TUI binds, Herdr).
bash -n "$FORK_OUT/bin/hexciri-launch-terminal" || die "bash -n failed on bin/hexciri-launch-terminal"
bash -n "$FORK_OUT/bin/hexciri-launch-tui" || die "bash -n failed on bin/hexciri-launch-tui"

printf 'terminal fast path patch: %d launcher edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 67: terminal fast path for --app-id and TUI launches"
