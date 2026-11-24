#!/bin/bash
# sim27: noise + binds fix (2026-11-24, Devi: update log full installer
# noise, Super+Space / Super+Alt+Space still dead after 6e48f01).
# 1. bash -n clean on both patched files.
# 2. Fingerprints: upstream/provision stable vs live 6e48f01, system
#    back to ef73f340 (pre-guard value), patch changed.
# 3. Guard present in Place section before rm -rf, absent from THPM tail.
# 4. sim7 fork pipeline verbatim against patched installer: fork builds,
#    restart bin contains patch 8f poll/retry loop, no bare echo in restart.
# 5. Updater migration: old 6e48f01 vs new selects re-apply (system inputs
#    unchanged); a system-range negative probe selects full.
# 6. Smoke check: no GlobalShortcut warn lines remain in installer.
set -u
NEW="$HOME/workspace/hexiri-2.0/simwork/../.."
PATCHED=/tmp/noise-fix/repo/v2
LIVE=/tmp/noise-fix/live2/v2
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok: $1"; }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

bash -n "$PATCHED/install.sh" && ok "bash -n install.sh" || bad "bash -n install.sh"
bash -n "$PATCHED/hexciri-update-hexciri" && ok "bash -n updater" || bad "bash -n updater"

FP_NEW=$(bash "$PATCHED/install.sh" --print-fingerprints)
FP_LIVE=$(bash "$LIVE/install.sh" --print-fingerprints)
N_UP=$(echo "$FP_NEW" | grep '^upstream=' | cut -d= -f2)
L_UP=$(echo "$FP_LIVE" | grep '^upstream=' | cut -d= -f2)
N_PA=$(echo "$FP_NEW" | grep '^patch=' | cut -d= -f2)
L_PA=$(echo "$FP_LIVE" | grep '^patch=' | cut -d= -f2)
N_PR=$(echo "$FP_NEW" | grep '^provision=' | cut -d= -f2)
L_PR=$(echo "$FP_LIVE" | grep '^provision=' | cut -d= -f2)
N_SY=$(echo "$FP_NEW" | grep '^system=' | cut -d= -f2)
L_SY=$(echo "$FP_LIVE" | grep '^system=' | cut -d= -f2)
[ "$N_UP" = "$L_UP" ] && ok "upstream fp stable vs 6e48f01" || bad "upstream fp changed"
[ "$N_PR" = "$L_PR" ] && ok "provision fp stable vs 6e48f01" || bad "provision fp changed"
[ "$N_SY" = "ef73f3400bdcc0a77edae4c4f8aa04b0ceb605c8aba53e87d70ae35f743d2639" ] && [ "$N_SY" != "$L_SY" ] && ok "system fp back to ef73f340 (pre-guard)" || bad "system fp not ef73f340: $N_SY"
[ "$N_PA" != "$L_PA" ] && ok "patch fp changed" || bad "patch fp unchanged"

# guard location
python3 - "$PATCHED/install.sh" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
place = next(i for i,l in enumerate(lines) if l.startswith("# --- Place the forked tree"))
guard = next(i for i,l in enumerate(lines) if 'binds_chain_ok "$FORK_OUT" || die' in l)
rm = next(i for i,l in enumerate(lines) if 'sudo rm -rf "$HEXCIRI_PATH"' in l)
assert place < guard < rm, f"guard not in Place section before rm -rf: place={place} guard={guard} rm={rm}"
# no guard call before Place header (the fingerprint filter line is not a call)
assert not any('binds_chain_ok "$FORK_OUT" || die' in l for l in lines[:place]), "guard still before Place header"
print("guard in Place section, before rm -rf")
PY
[ $? -eq 0 ] && ok "guard moved to Place section" || bad "guard location"

grep -q 'Super+Alt+Space menu shortcut not registered by the shell' "$PATCHED/install.sh" && bad "smoke check still warns menu" || ok "smoke check menu warn demoted"
grep -q 'Super+Space apps shortcut not registered by the shell' "$PATCHED/install.sh" && bad "smoke check still warns apps" || ok "smoke check apps warn demoted"
grep -q 'hyprctl configerrors' "$PATCHED/install.sh" && ok "configerrors warn kept" || bad "configerrors warn lost"
grep -q 'GlobalShortcuts registered' "$PATCHED/install.sh" && ok "placement check 8f present" || bad "placement check 8f missing"

# --- fork pipeline verbatim (sim7 pattern, patched installer) ---
SIMROOT="$HOME/workspace/hexiri-2.0/simwork"
OMARCHY_SRC="$SIMROOT/up"
FORK_OUT="/tmp/noise-fix/sim27out"
export HEXCIRI_PATH="$FORK_OUT" INSTALLER_DIR="$PATCHED" HEXCIRI_REPO_ROOT="/tmp/noise-fix/repo"
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
FORK_LOG="/tmp/noise-fix/sim27-fork.log"
_patch_log="$FORK_LOG"; : > "$FORK_LOG"
END_LINE=$(grep -n "^# --- Place the forked tree to its install targets ---" "$PATCHED/install.sh" | cut -d: -f1); END_LINE=$((END_LINE - 1))
START_LINE=$(grep -n "^# --- Fork and rename, inline" "$PATCHED/install.sh" | cut -d: -f1)
sed -n "${START_LINE},${END_LINE}p" "$PATCHED/install.sh" > /tmp/noise-fix/sim27-forkblock.sh
# shellcheck disable=SC1090
source /tmp/noise-fix/sim27-forkblock.sh && ok "sim7 fork pipeline builds" || bad "sim7 fork pipeline failed"
grep -q 'GlobalShortcuts registered' "$FORK_OUT/bin/hexciri-update-restart" && ok "restart bin has 8f poll/retry" || bad "restart bin lacks 8f"
grep -q 'hexciri-restart-shell || true' "$FORK_OUT/bin/hexciri-update-restart" && ok "restart bin re-restarts shell in 8f" || bad "restart bin lacks shell re-restart"
bash -n "$FORK_OUT/bin/hexciri-update-restart" && ok "bash -n restart bin" || bad "bash -n restart bin"
grep -qx 'echo' "$FORK_OUT/bin/hexciri-update-restart" && bad "restart bin has bare echo" || ok "restart bin no bare echo"
grep -q 'hexciri-shell hexciri.system-update refresh' "$FORK_OUT/bin/hexciri-update-restart" && ok "restart bin keeps 8e widget refresh" || bad "restart bin lost 8e"

# --- updater migration decision ---
# Simulate: old 6e48f01 install.sh vs new, system ranges identical (guard ignored)
python3 - <<'PY'
import subprocess, pathlib
def sys_hash(path):
    txt = pathlib.Path(path).read_text().splitlines()
    def rng(a, b):
        i = next(x for x,l in enumerate(txt) if l.startswith(a))
        j = next(x for x,l in enumerate(txt) if l.startswith(b))
        return txt[i:j]
    out = rng("# --- Preflight ---", "# --- Fork cache check") + rng("# --- mise + Hexciri tools config", "# --- Place the forked tree to its install targets ---")
    # strip the guard block (comment + call) and blank lines, like the updater migration
    stripped, skip = [], False
    for l in out:
        if l.startswith("# Pre-placement binds guard"): skip = True; continue
        if skip:
            if 'binds_chain_ok "$FORK_OUT" || die' in l: skip = False
            continue
        if l == "": continue
        stripped.append(l)
    import hashlib; return hashlib.sha256("\n".join(stripped).encode()).hexdigest()
old = sys_hash("/tmp/noise-fix/live/v2/install.sh")
new = sys_hash("/tmp/noise-fix/repo/v2/install.sh")
assert old == new, f"system inputs differ old={old} new={new}"
print("migration: system inputs unchanged old vs new")
PY
[ $? -eq 0 ] && ok "migration selects re-apply (system inputs unchanged)" || bad "migration system-input diff"
# negative probe: add a line in a system range, hash must change
cp "$PATCHED/install.sh" /tmp/noise-fix/sysprobe.sh
python3 - <<'PY'
import pathlib
p = pathlib.Path("/tmp/noise-fix/sysprobe.sh"); s = p.read_text()
old = "# --- Core packages ---"
assert s.count(old) == 1; p.write_text(s.replace(old, old + "\n# sim27 negative probe system-only", 1))
PY
python3 - <<'PY'
import pathlib, hashlib
def sys_hash(path):
    txt = pathlib.Path(path).read_text().splitlines()
    def rng(a, b):
        i = next(x for x,l in enumerate(txt) if l.startswith(a))
        j = next(x for x,l in enumerate(txt) if l.startswith(b))
        return txt[i:j]
    out = rng("# --- Preflight ---", "# --- Fork cache check") + rng("# --- mise + Hexciri tools config", "# --- Place the forked tree to its install targets ---")
    stripped, skip = [], False
    for l in out:
        if l.startswith("# Pre-placement binds guard"): skip = True; continue
        if skip:
            if 'binds_chain_ok "$FORK_OUT" || die' in l: skip = False
            continue
        if l == "": continue
        stripped.append(l)
    return hashlib.sha256("\n".join(stripped).encode()).hexdigest()
assert sys_hash("/tmp/noise-fix/sysprobe.sh") != sys_hash("/tmp/noise-fix/repo/v2/install.sh")
print("negative probe: system change detected, would fall through to full")
PY
[ $? -eq 0 ] && ok "migration negative probe selects full" || bad "migration negative probe"
grep -q 'Migration (2026-11-24, noise fix)' "$PATCHED/hexciri-update-hexciri" && ok "migration branch present in updater" || bad "migration branch missing"

echo "sim27: $pass passed, $fail failed"
[ "$fail" = "0" ]
