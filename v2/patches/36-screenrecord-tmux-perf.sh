#!/usr/bin/env bash
# Hexciri fork patch 36: screenrecording status / default-terminal / tmux
# theme-sync perf.
# Forward-port of omarchy PR #19973 (commit 7427fab86, "Speed up
# screenrecording status, default-terminal lookup, tmux theme sync").
#
# What it does (PR behavior, unchanged, fork-renamed omarchy->hexciri):
#  - bin/hexciri-capture-screenrecording: OUTPUT_DIR is resolved lazily,
#    only when not --status, so a status query never sources user-dirs
#    or touches the recordings dir; select_recorder remembers that it
#    already verified the pid (RECORDER_VERIFIED), so screenrecording_active
#    and the busy-status branch skip a second process-helper call.
#  - bin/hexciri-capture-screenrecording-process: the pgrep scan is replaced
#    by a direct /proc/*/comm walk (deduped --pid list, comm pre-filter,
#    exe still confirms each candidate, impostors still rejected).
#  - bin/hexciri-default-terminal: no-arg query fast-paths by reading
#    ~/.config/xdg-terminals.list directly instead of spawning
#    xdg-terminal-exec (~15 ms on the menu-guard hot path), falling back
#    to xdg-terminal-exec when a desktop-specific list exists or the id
#    is unknown.
#  - bin/hexciri-theme-set-tmux: sessions load once up front (one
#    list-sessions call); pane ttys load once; pane foreground process
#    groups resolve in one ps scan; client refreshes queue into the
#    single tmux script instead of one client call each. Two bare
#    `return`s become `return 0` so a failing sync step no longer
#    aborts the rest of the theme switch under set -e callers.
#
# Fork notes (verified against live nyx bin/ + the renamed tree):
#  - All four landing files are live in FORK_OUT: the menu guard and the
#    bar indicator call `hexciri-capture-screenrecording --status`, the
#    menu rows call `hexciri-default-terminal`, and bin/hexciri-theme-set
#    calls `hexciri-theme-set-tmux`. The repo's separate rewrite
#    bin/hexciri-screenrecord (plain pgrep, no --status path) is NOT
#    touched: it is a different command, and the PR's hunks have no
#    landing there.
#  - Fork divergence fixed as a side effect: the fork's no-arg
#    default-terminal case mapped `kitty.desktop` to "foot" (a rename
#    mishap; `foot.desktop` never matched). The PR replaces that case
#    with terminal_binary_for_desktop_id, so kitty.desktop now correctly
#    answers "kitty". The fork's *set* path still writes
#    desktop_id="kitty.desktop" for foot (same mishap, untouched by the
#    PR); flagged, not fixed here.
#  - Renames in the port: HEXCIRI_SCREENRECORD_DIR (fork env),
#    HEXCIRI_PROC_ROOT (fork env), hexciri-* command names,
#    "Hexciri's xdg-terminals.list" in the fast-path comment.
#    The `# omarchy:summary=` metadata prefix is kept: the fork router
#    parses it. Upstream test files are NOT in FORK_OUT (test/ is not
#    one of the copied subsets), so no test file is edited.
#
# Standalone: bash v2/patches/36-screenrecord-tmux-perf.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited files are bash, so the end-of-patch
# check is bash -n on each one.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "36-screenrecord-tmux-perf.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Screenrecording / default-terminal / tmux perf, omarchy PR #19973 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label, done_marker). done_marker defaults to new; it is
# the string whose presence means this edit is already applied (needed for
# deletions, where new is empty or already present elsewhere).
REPLACEMENTS = [
    # --- bin/hexciri-capture-screenrecording: lazy OUTPUT_DIR ---
    # Top of file: drop the eager user-dirs source + OUTPUT_DIR (they move
    # into the non---status branch below). The blank line after OUTPUT_DIR
    # goes with them, matching the upstream -3 lines.
    ("bin/hexciri-capture-screenrecording",
     "[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs\n"
     "OUTPUT_DIR=\"${HEXCIRI_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}}\"\n"
     "\n",
     "",
     "capture-screenrecording: drop eager OUTPUT_DIR resolution",
     "  OUTPUT_DIR=\"${HEXCIRI_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}}\"\n  if [[ ! -d $OUTPUT_DIR ]]"),
    # --status branch: resolve OUTPUT_DIR only when a recording dir is needed.
    ("bin/hexciri-capture-screenrecording",
     "if [[ $STATUS != \"true\" && ! -d $OUTPUT_DIR ]]; then\n"
     "  hexciri-notification-send -u critical -t 3000 \"$(hexciri-i18n capture.noRecordingDir \"$OUTPUT_DIR\")\"\n"
     "  exit 1\n"
     "fi",
     "if [[ $STATUS != \"true\" ]]; then\n"
     "  [[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs\n"
     "  OUTPUT_DIR=\"${HEXCIRI_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}}\"\n"
     "  if [[ ! -d $OUTPUT_DIR ]]; then\n"
     "    hexciri-notification-send -u critical -t 3000 \"$(hexciri-i18n capture.noRecordingDir \"$OUTPUT_DIR\")\"\n"
     "    exit 1\n"
     "  fi\n"
     "fi",
     "capture-screenrecording: resolve OUTPUT_DIR lazily (non---status only)",
     None),
    # select_recorder: remember the verified pid.
    ("bin/hexciri-capture-screenrecording",
     "select_recorder() {\n"
     "  RECORDER=()\n"
     "  [[ -f $REC_PID_FILE ]] || return 0\n"
     "\n"
     "  local pid\n"
     "  pid=$(<\"$REC_PID_FILE\")\n"
     "  [[ $pid =~ ^[0-9]+$ ]] && hexciri-capture-screenrecording-process --pid \"$pid\" || return 1\n"
     "  RECORDER=(--pid \"$pid\")\n"
     "}",
     "select_recorder() {\n"
     "  RECORDER=()\n"
     "  RECORDER_VERIFIED=0\n"
     "  [[ -f $REC_PID_FILE ]] || return 0\n"
     "\n"
     "  local pid\n"
     "  pid=$(<\"$REC_PID_FILE\")\n"
     "  [[ $pid =~ ^[0-9]+$ ]] && hexciri-capture-screenrecording-process --pid \"$pid\" || return 1\n"
     "  RECORDER=(--pid \"$pid\")\n"
     "  RECORDER_VERIFIED=1\n"
     "}",
     "capture-screenrecording: select_recorder sets RECORDER_VERIFIED",
     None),
    # screenrecording_active: skip the second process-helper call.
    ("bin/hexciri-capture-screenrecording",
     "screenrecording_active() {\n"
     "  if select_recorder && hexciri-capture-screenrecording-process \"${RECORDER[@]}\"; then",
     "screenrecording_active() {\n"
     "  if select_recorder && { (( RECORDER_VERIFIED )) || hexciri-capture-screenrecording-process \"${RECORDER[@]}\"; }; then",
     "capture-screenrecording: screenrecording_active reuses verified pid",
     None),
    # Busy-status branch: same skip.
    ("bin/hexciri-capture-screenrecording",
     "      select_recorder && hexciri-capture-screenrecording-process \"${RECORDER[@]}\"",
     "      select_recorder && { (( RECORDER_VERIFIED )) || hexciri-capture-screenrecording-process \"${RECORDER[@]}\"; }",
     "capture-screenrecording: busy-status branch reuses verified pid",
     None),
    # --- bin/hexciri-capture-screenrecording-process: /proc walk, no pgrep ---
    ("bin/hexciri-capture-screenrecording-process",
     "wanted=\" \"\n",
     "wanted_pids=()\n"
     "\n"
     "declare -A wanted_seen=()\n",
     "screenrecording-process: deduped --pid list replaces wanted string",
     None),
    ("bin/hexciri-capture-screenrecording-process",
     "      wanted+=\"$((10#$pid)) \"\n",
     "      pid=$((10#$pid))\n"
     "\n"
     "      if [[ -z ${wanted_seen[$pid]:-} ]]; then\n"
     "        wanted_seen[$pid]=1\n"
     "        wanted_pids+=(\"$pid\")\n"
     "      fi\n",
     "screenrecording-process: --pid dedupes into wanted_pids",
     None),
    ("bin/hexciri-capture-screenrecording-process",
     "# Linux truncates a process name to 15 characters: gpu-screen-recorder runs as\n"
     "# gpu-screen-reco, which any executable sharing that prefix also matches, and a\n"
     "# process can rename itself, so the executable path confirms each candidate.\n"
     "matched=()\n"
     "while read -r pid; do\n"
     "  if [[ $wanted == \" \" || $wanted == *\" $pid \"* ]] && is_recorder \"$pid\"; then\n"
     "    matched+=(\"$pid\")\n"
     "  fi\n"
     "done < <(pgrep -u \"$UID\" -x 'gpu-screen-reco(rder)?|wf-recorder')",
     "comm_is_recorder() {\n"
     "  local comm\n"
     "  { IFS= read -r comm <\"$proc_root/$1/comm\"; } 2>/dev/null || return 1\n"
     "  [[ $comm == \"gpu-screen-reco\" || $comm == \"gpu-screen-recorder\" || $comm == \"wf-recorder\" ]]\n"
     "}\n"
     "\n"
     "# Linux truncates a process name to 15 characters: gpu-screen-recorder runs as\n"
     "# gpu-screen-reco, which any executable sharing that prefix also matches, and a\n"
     "# process can rename itself, so the executable path confirms each candidate.\n"
     "# Reading $proc_root/*/comm directly avoids pgrep's full /proc stat/status walk.\n"
     "matched=()\n"
     "if ((${#wanted_pids[@]} > 0)); then\n"
     "  for pid in \"${wanted_pids[@]}\"; do\n"
     "    if [[ -O $proc_root/$pid ]] && comm_is_recorder \"$pid\" && is_recorder \"$pid\"; then\n"
     "      matched+=(\"$pid\")\n"
     "    fi\n"
     "  done\n"
     "else\n"
     "  shopt -s nullglob\n"
     "  comm_files=(\"$proc_root\"/[0-9]*/comm)\n"
     "  if ((${#comm_files[@]} > 0)); then\n"
     "    while IFS= read -r file; do\n"
     "      pid=${file#\"$proc_root\"/}\n"
     "      pid=${pid%/comm}\n"
     "      if [[ -O $proc_root/$pid ]] && is_recorder \"$pid\"; then\n"
     "        matched+=(\"$pid\")\n"
     "      fi\n"
     "    done < <(grep -lE '^(gpu-screen-reco(rder)?|wf-recorder)$' \"${comm_files[@]}\" 2>/dev/null)\n"
     "  fi\n"
     "fi",
     "screenrecording-process: direct /proc/*/comm walk replaces pgrep",
     None),
    # --- bin/hexciri-default-terminal: fast-path xdg-terminals.list ---
    ("bin/hexciri-default-terminal",
     "if (($# == 0)); then\n"
     "  desktop_id=$(xdg-terminal-exec --print-id 2>/dev/null || true)",
     "terminal_binary_for_desktop_id() {\n"
     "  case \"$1\" in\n"
     "  Alacritty.desktop) TERMINAL_BINARY=\"alacritty\" ;;\n"
     "  foot.desktop) TERMINAL_BINARY=\"foot\" ;;\n"
     "  com.mitchellh.ghostty.desktop) TERMINAL_BINARY=\"ghostty\" ;;\n"
     "  kitty.desktop) TERMINAL_BINARY=\"kitty\" ;;\n"
     "  *) return 1 ;;\n"
     "  esac\n"
     "}\n"
     "\n"
     "# Fast-path reading Hexciri's xdg-terminals.list directly in bash when called\n"
     "# without args (the menu guard hot path), avoiding xdg-terminal-exec's ~15ms\n"
     "# shell scan for the standard config.\n"
     "fast_default_terminal() {\n"
     "  [[ -z ${XTE_EXECARG_COMPAT:-}${XTE_DEBUG:-}${XTE_CACHE_ENABLED:-} ]] || return 1\n"
     "\n"
     "  local config_dir=\"${XDG_CONFIG_HOME:-$HOME/.config}\"\n"
     "  local list=\"$config_dir/xdg-terminals.list\"\n"
     "  local desktop line binary=\"\"\n"
     "  local -a desktops\n"
     "\n"
     "  IFS=: read -ra desktops <<<\"${XDG_CURRENT_DESKTOP:-}\"\n"
     "  for desktop in \"${desktops[@]}\"; do\n"
     "    [[ -n $desktop && -e $config_dir/${desktop,,}-xdg-terminals.list ]] && return 1\n"
     "  done\n"
     "\n"
     "  [[ -r $list ]] || return 1\n"
     "\n"
     "  while IFS= read -r line || [[ -n $line ]]; do\n"
     "    line=${line%$'\\r'}\n"
     "    line=${line#\"${line%%[![:space:]]*}\"}\n"
     "    [[ -z $line || $line == \\#* ]] && continue\n"
     "    [[ $line == [/+-]* ]] && return 1\n"
     "    if [[ -z $binary ]]; then\n"
     "      terminal_binary_for_desktop_id \"$line\" || return 1\n"
     "      binary=$TERMINAL_BINARY\n"
     "    fi\n"
     "  done <\"$list\"\n"
     "\n"
     "  [[ -n $binary ]] && type -P \"$binary\" >/dev/null 2>&1 || return 1\n"
     "  echo \"$binary\"\n"
     "}\n"
     "\n"
     "if (($# == 0)); then\n"
     "  if fast_default_terminal; then\n"
     "    exit 0\n"
     "  fi\n"
     "\n"
     "  desktop_id=$(xdg-terminal-exec --print-id 2>/dev/null || true)",
     "default-terminal: add fast_default_terminal + terminal_binary_for_desktop_id",
     None),
    # The no-arg case block becomes the shared helper call. (An earlier
    # draft of this patch assumed the fork's block had a duplicate
    # kitty.desktop line mapping to "foot"; that duplicate existed only
    # in the sim's rename mimic, never in the live fork. The live block
    # already maps foot->foot and kitty->kitty correctly.)
    ("bin/hexciri-default-terminal",
     "  desktop_id=$(xdg-terminal-exec --print-id 2>/dev/null || true)\n"
     "  desktop_id=${desktop_id%%:*}\n"
     "  case \"$desktop_id\" in\n"
     "  Alacritty.desktop) echo \"alacritty\" ;;\n"
     "  foot.desktop) echo \"foot\" ;;\n"
     "  com.mitchellh.ghostty.desktop) echo \"ghostty\" ;;\n"
     "  kitty.desktop) echo \"kitty\" ;;\n"
     "  *) echo \"$desktop_id\" ;;\n"
     "  esac\n"
     "  exit 0",
     "  desktop_id=$(xdg-terminal-exec --print-id 2>/dev/null || true)\n"
     "  desktop_id=${desktop_id%%:*}\n"
     "  if terminal_binary_for_desktop_id \"$desktop_id\"; then\n"
     "    echo \"$TERMINAL_BINARY\"\n"
     "  else\n"
     "    echo \"$desktop_id\"\n"
     "  fi\n"
     "  exit 0",
     "default-terminal: no-arg query uses terminal_binary_for_desktop_id",
     None),
    # --- bin/hexciri-theme-set-tmux: batch loads, one ps scan, queued refresh ---
    ("bin/hexciri-theme-set-tmux",
     "if ! tmux list-sessions >/dev/null 2>&1; then\n"
     "  exit 0\n"
     "fi\n",
     "",
     "theme-set-tmux: drop the probe list-sessions call",
     "load_tmux_sessions || exit 0"),
    ("bin/hexciri-theme-set-tmux",
     "TMUX_COMMANDS=()\n"
     "TMUX_SESSIONS=()\n"
     "declare -A THEME_COLORS=()\n",
     "TMUX_COMMANDS=()\n"
     "TMUX_SESSIONS=()\n"
     "TMUX_PANE_TTYS=()\n"
     "declare -A THEME_COLORS=()\n"
     "\n"
     "load_tmux_sessions() {\n"
     "  local session output\n"
     "\n"
     "  output=$(tmux list-sessions -F \"#{session_id}\" 2>/dev/null) || return 1\n"
     "  while IFS= read -r session; do\n"
     "    [[ -n $session ]] && TMUX_SESSIONS+=(\"$session\")\n"
     "  done <<<\"$output\"\n"
     "  (( ${#TMUX_SESSIONS[@]} > 0 ))\n"
     "}\n"
     "\n"
     "load_tmux_sessions || exit 0\n",
     "theme-set-tmux: sessions load once up front",
     None),
    ("bin/hexciri-theme-set-tmux",
     "load_tmux_sessions() {\n"
     "  local session\n"
     "\n"
     "  while IFS= read -r session; do\n"
     "    [[ -n $session ]] && TMUX_SESSIONS+=(\"$session\")\n"
     "  done < <(tmux list-sessions -F \"#{session_id}\" 2>/dev/null)\n"
     "}",
     "load_tmux_pane_ttys() {\n"
     "  local pane_tty\n"
     "\n"
     "  while IFS= read -r pane_tty; do\n"
     "    [[ $pane_tty == /dev/pts/* ]] && TMUX_PANE_TTYS+=(\"$pane_tty\")\n"
     "  done < <(tmux list-panes -a -F \"#{pane_tty}\" 2>/dev/null | sort -u)\n"
     "}",
     "theme-set-tmux: pane ttys load once (was one list-panes per sync)",
     None),
    ("bin/hexciri-theme-set-tmux",
     "  [[ -f $GUM_ENV ]] || return\n",
     "  [[ -f $GUM_ENV ]] || return 0\n",
     "theme-set-tmux: sync_theme_environment returns 0 when gum env is absent",
     None),
    ("bin/hexciri-theme-set-tmux",
     "  [[ -f $COLORS_TOML && -n $foreground && -n $background ]] || return\n",
     "  [[ -f $COLORS_TOML && -n $foreground && -n $background ]] || return 0\n",
     "theme-set-tmux: sync_tmux_window_style returns 0 when colours are absent",
     None),
    ("bin/hexciri-theme-set-tmux",
     "sync_tmux_pane_colors() {\n"
     "  local pane_tty theme_osc\n"
     "\n"
     "  [[ -f $COLORS_TOML ]] || return\n"
     "\n"
     "  theme_osc=$(theme_osc_sequences)\n"
     "  [[ -n $theme_osc ]] || return\n"
     "\n"
     "  while IFS= read -r pane_tty; do\n"
     "    [[ $pane_tty == /dev/pts/* ]] || continue\n"
     "    printf '%b' \"$theme_osc\" >\"$pane_tty\" 2>/dev/null || true\n"
     "  done < <(tmux list-panes -a -F \"#{pane_tty}\" 2>/dev/null | sort -u)\n"
     "}",
     "sync_tmux_pane_colors() {\n"
     "  local pane_tty theme_osc\n"
     "\n"
     "  [[ -f $COLORS_TOML ]] || return 0\n"
     "\n"
     "  (( ${#TMUX_PANE_TTYS[@]} > 0 )) || return 0\n"
     "\n"
     "  theme_osc=$(theme_osc_sequences)\n"
     "  [[ -n $theme_osc ]] || return 0\n"
     "\n"
     "  for pane_tty in \"${TMUX_PANE_TTYS[@]}\"; do\n"
     "    printf '%b' \"$theme_osc\" >\"$pane_tty\" 2>/dev/null || true\n"
     "  done\n"
     "}",
     "theme-set-tmux: sync_tmux_pane_colors uses the loaded pane ttys",
     None),
    ("bin/hexciri-theme-set-tmux",
     "signal_tmux_panes() {\n"
     "  local pane_tty tpgid\n"
     "\n"
     "  while IFS= read -r pane_tty; do\n"
     "    [[ $pane_tty == /dev/pts/* ]] || continue\n"
     "    tpgid=$(ps -o tpgid= -t \"${pane_tty#/dev/}\" 2>/dev/null | awk 'NF && $1 > 0 { print $1; exit }')\n"
     "    [[ -n $tpgid ]] || continue\n"
     "    kill -WINCH \"-$tpgid\" 2>/dev/null || true\n"
     "  done < <(tmux list-panes -a -F \"#{pane_tty}\" 2>/dev/null | sort -u)\n"
     "}",
     "signal_tmux_panes() {\n"
     "  local pane_tty tty tpgid\n"
     "  local -A tty_tpgid=()\n"
     "\n"
     "  (( ${#TMUX_PANE_TTYS[@]} > 0 )) || return 0\n"
     "\n"
     "  # One process-table scan resolves every pane's foreground process group,\n"
     "  # avoiding a ps + awk fork per pane.\n"
     "  while read -r tty tpgid; do\n"
     "    if [[ -n $tty && $tpgid =~ ^[1-9][0-9]*$ && -z ${tty_tpgid[$tty]:-} ]]; then\n"
     "      tty_tpgid[$tty]=$tpgid\n"
     "    fi\n"
     "  done < <(ps -eo tty=,tpgid= 2>/dev/null)\n"
     "\n"
     "  for pane_tty in \"${TMUX_PANE_TTYS[@]}\"; do\n"
     "    tpgid=${tty_tpgid[${pane_tty#/dev/}]:-}\n"
     "    [[ -n $tpgid ]] || continue\n"
     "    kill -WINCH \"-$tpgid\" 2>/dev/null || true\n"
     "  done\n"
     "}",
     "theme-set-tmux: signal_tmux_panes uses one ps scan for all panes",
     None),
    ("bin/hexciri-theme-set-tmux",
     "refresh_tmux_clients() {\n"
     "  local client\n"
     "\n"
     "  while IFS= read -r client; do\n"
     "    [[ -n $client ]] || continue\n"
     "    tmux refresh-client -t \"$client\" 2>/dev/null || true\n"
     "  done < <(tmux list-clients -F \"#{client_name}\" 2>/dev/null)\n"
     "}",
     "queue_refresh_tmux_clients() {\n"
     "  local client\n"
     "\n"
     "  while IFS= read -r client; do\n"
     "    [[ -n $client ]] || continue\n"
     "    queue_tmux_command refresh-client -t \"$client\"\n"
     "  done < <(tmux list-clients -F \"#{client_name}\" 2>/dev/null)\n"
     "}",
     "theme-set-tmux: client refresh queues into the single tmux script",
     None),
    ("bin/hexciri-theme-set-tmux",
     "load_tmux_sessions\n"
     "load_theme_colors\n"
     "\n"
     "sync_theme_environment\n"
     "sync_colorfgbg\n"
     "sync_tmux_window_style\n"
     "apply_tmux_commands\n"
     "sync_tmux_pane_colors\n"
     "signal_tmux_panes\n"
     "refresh_tmux_clients",
     "load_theme_colors\n"
     "load_tmux_pane_ttys\n"
     "\n"
     "sync_theme_environment\n"
     "sync_colorfgbg\n"
     "sync_tmux_window_style\n"
     "sync_tmux_pane_colors\n"
     "signal_tmux_panes\n"
     "queue_refresh_tmux_clients\n"
     "apply_tmux_commands",
     "theme-set-tmux: apply the queued script once, at the end",
     None),
]

for rel, old, new, label, *rest in REPLACEMENTS:
    done_marker = rest[0] if rest else None
    if done_marker is None:
        done_marker = new
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if done_marker and done_marker in s:
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
print("screenrecord-tmux-perf patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. They are bash, so bash -n applies here.
for _f in bin/hexciri-capture-screenrecording bin/hexciri-capture-screenrecording-process bin/hexciri-default-terminal bin/hexciri-theme-set-tmux; do
  if [ -f "$FORK_OUT/$_f" ]; then
    bash -n "$FORK_OUT/$_f" || die "bash -n failed on patched $_f"
  fi
done
info "  screenrecord-tmux-perf: status/terminal/tmux fast paths from PR #19973"
