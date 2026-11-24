#!/bin/bash
# sim28: Install > Terminal four rows + foot.desktop placement fix
# (2026-11-24, Devi 15:37 + 15:39 MST).
# 1. bash -n clean on the patched installer.
# 2. Fingerprints vs live cf3bb1a: upstream/provision/system stable,
#    patch changed (fork cache invalidates, fresh fork on next update).
# 3. Fork pipeline verbatim from the PATCHED installer: all four
#    install.terminal.* rows present, backing bins + data present,
#    FORK_OUT/applications has exactly the 3 curated desktop files.
# 4. Placement emulation with the PATCHED cp list (read from the patched
#    file, not hardcoded): placed applications/foot.desktop present,
#    and the terminal verification lines from the patched installer
#    (foot.desktop check, _term desktop_id loop, _row loop incl. all
#    four terminal rows) all pass against the placed tree.
# 5. Negative controls on the UNPATCHED installer: placed
#    applications/foot.desktop missing (Devi's exact error), and the
#    unpatched _row list has no alacritty/ghostty/kitty row checks.
# 6. Idempotency: fork + placement run twice, same rows/files.
# 7. Kitty still default (default-terminal getter, dock pins), trim
#    removes none of the four terminals.
set -u
PATCHED=/tmp/term-fix
LIVE=/tmp/hexciri-nyx/v2
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok: $1"; }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

bash -n "$PATCHED/install.sh" && ok "bash -n patched install.sh" || bad "bash -n patched install.sh"

FP_NEW=$(bash "$PATCHED/install.sh" --print-fingerprints)
FP_LIVE=$(bash "$LIVE/install.sh" --print-fingerprints)
for _k in upstream provision system; do
  N=$(echo "$FP_NEW" | grep "^$_k=" | cut -d= -f2)
  L=$(echo "$FP_LIVE" | grep "^$_k=" | cut -d= -f2)
  [ "$N" = "$L" ] && ok "$_k fp stable vs live" || bad "$_k fp changed: $N vs $L"
done
N_PA=$(echo "$FP_NEW" | grep '^patch=' | cut -d= -f2)
L_PA=$(echo "$FP_LIVE" | grep '^patch=' | cut -d= -f2)
[ "$N_PA" != "$L_PA" ] && ok "patch fp changed (fresh fork on next update)" || bad "patch fp unchanged"

# --- fork pipeline verbatim (sim27 pattern), patched installer ---
run_fork() {
  local _out="$1"
  SIMROOT="$HOME/workspace/hexiri-2.0/simwork"
  OMARCHY_SRC="$SIMROOT/up"
  FORK_OUT="$_out"
  export HEXCIRI_PATH="$FORK_OUT" INSTALLER_DIR="$PATCHED" HEXCIRI_REPO_ROOT="/tmp/hexciri-nyx"
  rm -rf "$FORK_OUT"; mkdir -p "$FORK_OUT"
  step() { printf '\n==> %s\n' "$1"; }
  info() { printf '[hexciri] %s\n' "$1"; }
  warn() { printf 'WARN: %s\n' "$1"; }
  die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
  sudo() { echo "[SIM sudo stub] $*"; return 0; }
  bootstrap_ok() { local _f="$1" _n; [ -f "$_f" ] || return 1; [ -s "$_f" ] || return 1; _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"; [ "${_n:-0}" -ge 500 ] || return 1; grep -q 'package.path' "$_f" 2>/dev/null || return 1; grep -q 'HEXCIRI_PATH' "$_f" 2>/dev/null || return 1; return 0; }
  hyprlua_ok() { local _f="$1" _n; [ -f "$_f" ] || return 1; [ -s "$_f" ] || return 1; _n="$(wc -c < "$_f" 2>/dev/null | tr -d ' ')"; [ "${_n:-0}" -ge 1000 ] || return 1; grep -q 'require("default.hypr.helpers")' "$_f" 2>/dev/null || return 1; return 0; }
  binds_chain_ok() {
    local _root="$1" _why=""
    grep -q 'SUPER + ALT + SPACE.*{ menu = "root" }' "$_root/default/hypr/bindings/utilities.lua" 2>/dev/null || _why="utilities.lua swap lost"
    [ -n "$_why" ] || grep -q 'SUPER + SPACE.*{ ipc = "hexciri.dock.apps" }' "$_root/default/hypr/bindings/utilities.lua" 2>/dev/null || _why="utilities.lua swap lost"
    [ -n "$_why" ] || grep -qx 'menu root' "$_root/default/hexciri/shortcuts" 2>/dev/null || _why="shortcuts menu root missing"
    [ -n "$_why" ] || grep -qx 'ipc hexciri.dock.apps' "$_root/default/hexciri/shortcuts" 2>/dev/null || _why="shortcuts apps missing"
    [ -n "$_why" ] || grep -q 'require("default.hypr.bindings.hexciri")' "$_root/default/hypr/hexciri.lua" 2>/dev/null || _why="binds require missing"
    [ -n "$_why" ] || [ -s "$_root/default/hypr/bindings/hexciri.lua" ] || _why="bindings/hexciri.lua empty"
    [ -n "$_why" ] || grep -q 'appid: "omarchy"' "$_root/shell/shell.qml" 2>/dev/null || _why="appid not omarchy"
    [ -n "$_why" ] || [ -f "$_root/config/tmux/tmux.conf" ] || _why="tmux.conf missing"
    [ -n "$_why" ] || [ -f "$_root/config/chromium-flags.conf" ] || _why="chromium-flags missing"
    if [ -n "$_why" ]; then printf 'binds chain broken: %s\n' "$_why" >&2; return 1; fi
    return 0
  }
  FORK_LOG="/home/hatch/workspace/term-fix-sim/sim28-fork.log"
  _patch_log="$FORK_LOG"; : > "$FORK_LOG"
  END_LINE=$(grep -n "^# --- Place the forked tree to its install targets ---" "$PATCHED/install.sh" | cut -d: -f1); END_LINE=$((END_LINE - 1))
  START_LINE=$(grep -n "^# --- Fork and rename, inline" "$PATCHED/install.sh" | cut -d: -f1)
  sed -n "${START_LINE},${END_LINE}p" "$PATCHED/install.sh" > /home/hatch/workspace/term-fix-sim/sim28-forkblock.sh
  # shellcheck disable=SC1090
  source /home/hatch/workspace/term-fix-sim/sim28-forkblock.sh
}
run_fork /home/hatch/workspace/term-fix-sim/sim28out && ok "fork pipeline builds (patched)" || bad "fork pipeline failed (patched)"
FORK_OUT=/home/hatch/workspace/term-fix-sim/sim28out

for _t in alacritty kitty ghostty foot; do
  grep -q "\"install.terminal.$_t\"" "$FORK_OUT/default/hexciri/hexciri-menu.jsonc" && ok "row install.terminal.$_t present" || bad "row install.terminal.$_t MISSING"
done
for _b in hexciri-install-terminal hexciri-launch-floating-terminal-with-presentation hexciri-pkg-present hexciri-default-terminal; do
  [ -x "$FORK_OUT/bin/$_b" ] && ok "bin $_b present" || bad "bin $_b MISSING"
done
ls "$FORK_OUT/applications/" | sort | tr '\n' ' ' | grep -qx "foot.desktop hexciri-browser.desktop hexciri-terminal.desktop " && ok "fork applications/ exactly the 3 curated files" || bad "fork applications/ unexpected: $(ls "$FORK_OUT/applications/" | tr '\n' ' ')"
for _f in config/alacritty/alacritty.toml config/ghostty/config config/foot/foot.ini default/alacritty/Alacritty.desktop applications/foot.desktop; do
  [ -f "$FORK_OUT/$_f" ] && ok "fork file $_f present" || bad "fork file $_f MISSING"
done

# --- placement emulation: cp list read from the patched installer ---
PLACED=/home/hatch/workspace/term-fix-sim/sim28placed
rm -rf "$PLACED"; mkdir -p "$PLACED"
CP_LINE=$(grep '^sudo cp -a "\$FORK_OUT/shell"' "$PATCHED/install.sh")
echo "$CP_LINE" | grep -q 'FORK_OUT/applications' && ok "patched placement cp includes applications/" || bad "patched placement cp lacks applications/"
# Execute the installer's own cp line with FORK_OUT/HEXCIRI_PATH pointed at the sim dirs.
# NOTE: the installer runs this under sudo, where cp -a preserves ownership
# and exits 0. In the sim it runs as the user, so cp -a warns "failed to
# preserve ownership" and exits non-zero even though every file copies;
# the check below is therefore on the RESULT (all 8 dirs landed), not rc.
( FORK_OUT="$FORK_OUT" HEXCIRI_PATH="$PLACED"; eval "${CP_LINE#sudo }" 2>/tmp/term-fix/sim28-cp.err || true )
for _d in shell default themes bin install icons config applications; do
  [ -d "$PLACED/$_d" ] && ok "placement copied $_d" || bad "placement missing $_d"
done
[ -f "$PLACED/applications/foot.desktop" ] && ok "placed applications/foot.desktop present" || bad "placed applications/foot.desktop MISSING"
[ -f "$PLACED/applications/hexciri-terminal.desktop" ] && ok "placed applications/hexciri-terminal.desktop present" || bad "placed hexciri-terminal.desktop MISSING"
[ -f "$PLACED/applications/hexciri-browser.desktop" ] && ok "placed applications/hexciri-browser.desktop present" || bad "placed hexciri-browser.desktop MISSING"

# --- verification lines verbatim from the patched installer ---
HEXCIRI_PATH="$PLACED"
[ -f "$HEXCIRI_PATH/config/alacritty/alacritty.toml" ] && ok "verify config/alacritty" || bad "verify config/alacritty"
[ -f "$HEXCIRI_PATH/config/ghostty/config" ] && ok "verify config/ghostty" || bad "verify config/ghostty"
[ -f "$HEXCIRI_PATH/default/alacritty/Alacritty.desktop" ] && ok "verify default/alacritty desktop" || bad "verify default/alacritty desktop"
[ -f "$HEXCIRI_PATH/config/foot/foot.ini" ] && ok "verify config/foot" || bad "verify config/foot"
[ -f "$HEXCIRI_PATH/applications/foot.desktop" ] && ok "verify applications/foot.desktop (was Devi's ERROR)" || bad "verify applications/foot.desktop"
for _term in alacritty foot ghostty kitty; do
  grep -q "^$_term) desktop_id=" "$HEXCIRI_PATH/bin/hexciri-install-terminal" && ok "install-terminal desktop_id for $_term" || bad "install-terminal desktop_id for $_term MISSING"
done
# The _row loop, extracted verbatim from the patched installer.
ROW_LINE=$(grep "^for _row in '\"install.browser\"'" "$PATCHED/install.sh")
echo "$ROW_LINE" | grep -q 'install.terminal.alacritty' && ok "patched _row list has alacritty" || bad "patched _row list lacks alacritty"
echo "$ROW_LINE" | grep -q 'install.terminal.ghostty' && ok "patched _row list has ghostty" || bad "patched _row list lacks ghostty"
echo "$ROW_LINE" | grep -q 'install.terminal.kitty' && ok "patched _row list has kitty" || bad "patched _row list lacks kitty"
eval "$ROW_LINE
  grep -q \"\$_row\" \"\$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc\" || { echo \"FAIL: row missing: \$_row\"; fail=\$((fail+1)); }
done" && ok "patched _row loop: all restored rows present" || bad "patched _row loop failed"

# --- idempotency: fork + placement a second time, same result ---
run_fork /home/hatch/workspace/term-fix-sim/sim28out2 && ok "fork pipeline builds (2nd run)" || bad "fork pipeline failed (2nd run)"
for _t in alacritty kitty ghostty foot; do
  grep -q "\"install.terminal.$_t\"" /home/hatch/workspace/term-fix-sim/sim28out2/default/hexciri/hexciri-menu.jsonc || bad "2nd run lost row install.terminal.$_t"
done
diff <(grep -o '"install\.terminal[^"]*"' "$FORK_OUT/default/hexciri/hexciri-menu.jsonc") <(grep -o '"install\.terminal[^"]*"' /home/hatch/workspace/term-fix-sim/sim28out2/default/hexciri/hexciri-menu.jsonc) >/dev/null && ok "terminal rows identical across runs" || bad "terminal rows differ across runs"

# --- negative controls on the UNPATCHED installer ---
UNCP_LINE=$(grep '^sudo cp -a "\$FORK_OUT/shell"' "$LIVE/install.sh")
echo "$UNCP_LINE" | grep -q 'FORK_OUT/applications' && bad "NEGATIVE: unpatched cp already has applications/" || ok "negative: unpatched cp lacks applications/ (reproduces the bug)"
UNPLACED=/home/hatch/workspace/term-fix-sim/sim28unplaced
rm -rf "$UNPLACED"; mkdir -p "$UNPLACED"
( FORK_OUT="$FORK_OUT" HEXCIRI_PATH="$UNPLACED"; eval "${UNCP_LINE#sudo }" )
[ -f "$UNPLACED/applications/foot.desktop" ] && bad "NEGATIVE: unpatched placement has foot.desktop" || ok "negative: unpatched placement lacks foot.desktop (Devi's ERROR reproduced)"
UNROW_LINE=$(grep "^for _row in '\"install.browser\"'" "$LIVE/install.sh")
echo "$UNROW_LINE" | grep -q 'install.terminal.alacritty' && bad "NEGATIVE: unpatched _row list has alacritty" || ok "negative: unpatched _row list lacks alacritty (sim gap confirmed)"
echo "$UNROW_LINE" | grep -q 'install.terminal.ghostty' && bad "NEGATIVE: unpatched _row list has ghostty" || ok "negative: unpatched _row list lacks ghostty (sim gap confirmed)"

# --- Kitty still default, trim removes no terminal ---
grep -q 'kitty.desktop) echo "kitty"' "$FORK_OUT/bin/hexciri-default-terminal" && ok "default-terminal getter reports kitty" || bad "default-terminal getter not kitty"
grep -q "Strata, Spotify, Brave Origin, Zed, Kitty" "$PATCHED/install.sh" && ok "dock pins unchanged (Strata, Spotify, Brave Origin, Zed, Kitty)" || bad "dock pins changed"
TRIM_LINE=$(grep '^for _pkg in btop' "$PATCHED/install.sh")
for _t in alacritty ghostty foot kitty; do
  echo "$TRIM_LINE" | grep -qw "$_t" && bad "trim removes $_t" || ok "trim does not remove $_t"
done
grep -q '"install.terminal.foot"' "$FORK_OUT/default/hexciri/hexciri-menu.jsonc" && grep -q 'foot' "$PATCHED/install.sh" && ok "foot row present, foot not trimmed" || bad "foot row/trim mismatch"

echo "sim28: $pass passed, $fail failed"
[ "$fail" = "0" ]
