#!/bin/bash
# sim29: Super+Alt+Space menu empty after update (2026-11-24, Devi 15:52 MST).
# 1. bash -n clean on the patched installer.
# 2. Fingerprints vs live 7cfd163: upstream/provision/system stable,
#    patch changed (fork cache invalidates, fresh fork on next update).
# 3. Fork pipeline verbatim from the PATCHED installer (sim7 pattern):
#    the forked hexciri-menu.jsonc must PARSE exactly like MenuModel.js
#    parses it (full-line // comments + trailing commas stripped, then
#    JSON.parse): 369 entries, all 9 root entries, and the maple row
#    action round-trips with its quoted font name. The fork log must
#    record the new "menu jsonc parses" line.
# 4. Placement emulation with the PATCHED cp list: the placed menu parses
#    too, via the placement-verification snippet extracted verbatim from
#    the patched installer (not a re-implementation).
# 5. Negative controls on the UNPATCHED live installer: its forked menu
#    FAILS to parse at line 199 col 248 (the cf3bb1a maple row's bare
#    quotes), and the unpatched installer has no parse guard anywhere.
#    This is the exact failure sim28 missed: grep row checks pass on a
#    menu the shell cannot read.
# 6. Idempotency: fork + placement run twice, same menu bytes.
# 7. Terminal-four rows + foot.desktop placement still pass (no
#    regression from the maple fix).
set -u
PATCHED=/tmp/menu-empty-1124
LIVE=/tmp/menu-empty-1124-unpatched
SIMROOT_P=/tmp/menu-empty-1124-simwork
SIMROOT_U=/tmp/menu-empty-1124-simwork-unpatched
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok: $1"; }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

bash -n "$PATCHED/v2/install.sh" && ok "bash -n patched install.sh" || bad "bash -n patched install.sh"

# Unpatched staging (live 7cfd163) must exist before the fingerprint
# comparison below and the negative-control fork in section 5.
mkdir -p "$LIVE/v2"
cp -a "$PATCHED/v2/." "$LIVE/v2/"
cp /tmp/menu-gone-1124/install-live.sh "$LIVE/v2/install.sh"

FP_NEW=$(bash "$PATCHED/v2/install.sh" --print-fingerprints)
FP_LIVE=$(bash "$LIVE/v2/install.sh" --print-fingerprints)
for _k in upstream provision system; do
  N=$(echo "$FP_NEW" | grep "^$_k=" | cut -d= -f2)
  L=$(echo "$FP_LIVE" | grep "^$_k=" | cut -d= -f2)
  [ "$N" = "$L" ] && ok "$_k fp stable vs live" || bad "$_k fp changed: $N vs $L"
done
N_PA=$(echo "$FP_NEW" | grep '^patch=' | cut -d= -f2)
L_PA=$(echo "$FP_LIVE" | grep '^patch=' | cut -d= -f2)
[ "$N_PA" != "$L_PA" ] && ok "patch fp changed (fresh fork on next update)" || bad "patch fp unchanged"

# --- MenuModel.js-equivalent parse helper (stripJsonc + JSON.parse) ---
cat > /tmp/menu-empty-parse.py <<'PYEOF'
import re, sys, json
raw = open(sys.argv[1]).read()
stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
d = json.loads(stripped)
roots = [k for k in d if '.' not in k]
want = ['apps', 'appearance', 'trigger', 'setup', 'install', 'remove', 'update', 'learn', 'system']
missing = [r for r in want if r not in d]
print("entries=%d roots=%s" % (len(d), ",".join(roots)))
print("maple_action=%s" % d.get('install.style.font.maple', {}).get('action', ''))
if missing:
    print("MISSING ROOTS: %s" % ",".join(missing)); sys.exit(2)
if 'hexciri-font-set "Maple Mono NF CN"' not in d.get('install.style.font.maple', {}).get('action', ''):
    print("MAPLE ACTION LOST ITS QUOTED FONT NAME"); sys.exit(3)
PYEOF

# --- fork runner (sim7 pattern, paths rewritten to a staging simroot) ---
run_fork() {
  local _installer_dir="$1" _repo_root="$2" _simroot="$3" _sim7="$4"
  mkdir -p "$_simroot"
  [ -e "$_simroot/up" ] || ln -s "$HOME/workspace/hexiri-2.0/simwork/up" "$_simroot/up"
  sed "s|\$HOME/workspace/hexiri-2.0/simwork|$_simroot|g; s|\$HOME/workspace/hexiri-2.0|$_repo_root|g" \
    "$HOME/workspace/hexiri-2.0/simwork/sim7.sh" > "$_sim7"
  # sim7.sh hardcodes INSTALLER_DIR from the workspace path; the sed above
  # rewrote $HOME/workspace/hexiri-2.0 to the repo root, so INSTALLER_DIR
  # is now $_repo_root/v2 -- but the installer lives at $_installer_dir.
  sed -i "s|INSTALLER_DIR=\"$_repo_root/v2\"|INSTALLER_DIR=\"$_installer_dir\"|" "$_sim7"
  bash "$_sim7" > "$_simroot/sim7.log" 2>&1
}

# --- 3. patched fork ---
run_fork "$PATCHED/v2" "$PATCHED" "$SIMROOT_P" /tmp/menu-empty-1124-sim7.sh || { echo "patched fork FAILED"; tail -30 "$SIMROOT_P/sim7.log"; exit 1; }
echo "patched fork done"
OUT_P="$SIMROOT_P/sim7out"
python3 /tmp/menu-empty-parse.py "$OUT_P/default/hexciri/hexciri-menu.jsonc" > /tmp/menu-empty-parse-patched.txt 2>&1 && ok "patched fork menu parses (MenuModel.js strip+JSON.parse)" || { bad "patched fork menu DOES NOT parse"; cat /tmp/menu-empty-parse-patched.txt; }
grep -q "entries=369" /tmp/menu-empty-parse-patched.txt && ok "patched fork menu has 369 entries" || bad "patched fork menu entry count wrong"
grep -q "roots=apps,appearance,trigger,setup,install,remove,update,learn,system" /tmp/menu-empty-parse-patched.txt && ok "patched fork menu has all 9 root entries" || bad "patched fork menu roots wrong"
grep -q 'menu jsonc parses (369 entries, 9 root entries)' "$SIMROOT_P/sim7-fork.log" && ok "fork log records menu jsonc parses" || bad "fork log missing menu jsonc parses line"
grep -q 'hexciri-font-set "Maple Mono NF CN"' /tmp/menu-empty-parse-patched.txt && ok "maple action round-trips with quoted font name" || bad "maple action wrong"
grep -q 'hexciri-font-set \\"Maple Mono NF CN\\"' "$OUT_P/default/hexciri/hexciri-menu.jsonc" && ok "emitted jsonc holds escaped quotes" || bad "emitted jsonc lacks escaped quotes"

# --- 4. placement emulation + verbatim placement-verification snippet ---
PLACED=/tmp/menu-empty-1124-placed
rm -rf "$PLACED"; mkdir -p "$PLACED"
cp -a "$OUT_P/shell" "$OUT_P/default" "$OUT_P/themes" "$OUT_P/bin" "$OUT_P/install" "$OUT_P/icons" "$OUT_P/config" "$OUT_P/applications" "$PLACED/"
[ -f "$PLACED/applications/foot.desktop" ] && ok "placed applications/foot.desktop present (terminal-four, no regression)" || bad "placed applications/foot.desktop missing"
for _term in alacritty foot ghostty kitty; do
  grep -q "^$_term) desktop_id=" "$PLACED/bin/hexciri-install-terminal" && ok "placed install-terminal desktop_id for $_term" || bad "placed install-terminal desktop_id for $_term MISSING"
done
for _row in '"install.terminal.alacritty"' '"install.terminal.kitty"' '"install.terminal.ghostty"' '"install.terminal.foot"'; do
  grep -q "$_row" "$PLACED/default/hexciri/hexciri-menu.jsonc" && ok "placed menu row $_row present" || bad "placed menu row $_row missing"
done
# Extract the placement parse block verbatim from the patched installer.
awk '/^python3 - "\$HEXCIRI_PATH\/default\/hexciri\/hexciri-menu.jsonc" <<.PYEOF./{f=1} f{print} /^PYEOF$/{if(f)exit}' "$PATCHED/v2/install.sh" > /tmp/menu-empty-place-verify.sh
grep -q "does not parse" /tmp/menu-empty-place-verify.sh && ok "placement parse block present in patched installer" || bad "placement parse block missing from patched installer"
# The snippet reads $HEXCIRI_PATH itself; run it as the installer would.
HEXCIRI_PATH="$PLACED" bash /tmp/menu-empty-place-verify.sh > /tmp/menu-empty-place-verify.log 2>&1 && ok "verbatim placement snippet parses placed menu" || { bad "verbatim placement snippet FAILED on placed menu"; cat /tmp/menu-empty-place-verify.log; }
grep -q "menu jsonc parses: 369 entries" /tmp/menu-empty-place-verify.log && ok "placement snippet reports 369 entries" || bad "placement snippet entry count wrong"

# --- 5. negative controls: unpatched live installer (staged above) ---
run_fork "$LIVE/v2" "$LIVE" "$SIMROOT_U" /tmp/menu-empty-1124-sim7-unpatched.sh || { echo "unpatched fork FAILED (unexpected, fork itself should succeed)"; tail -30 "$SIMROOT_U/sim7.log"; exit 1; }
echo "unpatched fork done"
OUT_U="$SIMROOT_U/sim7out"
if python3 /tmp/menu-empty-parse.py "$OUT_U/default/hexciri/hexciri-menu.jsonc" > /tmp/menu-empty-parse-unpatched.txt 2>&1; then
  bad "UNPATCHED fork menu parses (negative control failed, bug not reproduced)"
else
  ok "unpatched fork menu FAILS to parse (bug reproduced)"
  grep -q "line 199" /tmp/menu-empty-parse-unpatched.txt && ok "unpatched parse fails at line 199 (maple row)" || bad "unpatched parse fails elsewhere"
fi
grep -q 'hexciri-font-set "Maple Mono NF CN"' "$OUT_U/default/hexciri/hexciri-menu.jsonc" && ok "unpatched fork has the bare-quote maple row" || bad "unpatched fork maple row differs"
grep -q "menu jsonc parses" "$LIVE/v2/install.sh" && bad "unpatched installer already has a parse guard" || ok "unpatched installer has no parse guard"
grep -q "menu jsonc does not parse" "$LIVE/v2/install.sh" && bad "unpatched installer already has placement parse check" || ok "unpatched installer has no placement parse check"

# --- 6. idempotency: fork patched twice, same menu bytes ---
sha1=$(sha256sum "$OUT_P/default/hexciri/hexciri-menu.jsonc" | cut -d' ' -f1)
run_fork "$PATCHED/v2" "$PATCHED" "$SIMROOT_P" /tmp/menu-empty-1124-sim7.sh || { echo "second patched fork FAILED"; tail -30 "$SIMROOT_P/sim7.log"; exit 1; }
sha2=$(sha256sum "$OUT_P/default/hexciri/hexciri-menu.jsonc" | cut -d' ' -f1)
[ "$sha1" = "$sha2" ] && ok "fork idempotent: menu bytes identical on re-run" || bad "fork not idempotent: menu bytes differ"
python3 /tmp/menu-empty-parse.py "$OUT_P/default/hexciri/hexciri-menu.jsonc" >/dev/null 2>&1 && ok "second fork menu still parses" || bad "second fork menu does not parse"

echo
echo "sim29: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
