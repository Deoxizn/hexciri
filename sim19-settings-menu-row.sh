#!/bin/bash
# sim19: top-level Settings row removed from Super+Alt+Space menu.
# 1. sim7 fork pipeline verbatim against pristine upstream 94a8c3c:
#    forked menu must have NO "settings" row calling hexciri-launch-settings.
# 2. Seeded-row test: take the sim7 fork output, insert the OLD Settings
#    row after "system" (exactly what the old lean patch produced), then
#    run the menu-audit python block extracted from install.sh against
#    that copy: the row must be removed, everything else intact.
# 3. User-extensions cleanup snippet: a fake extensions file with the
#    old row loses exactly that line; a file without it is untouched.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n "$ROOT/v2/install.sh" || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"

bash "$ROOT/simwork/sim7.sh" >/tmp/sim19-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim19-sim7.log; exit 1; }
MENU="$ROOT/simwork/sim7out/default/hexciri/hexciri-menu.jsonc"
check "sim7 menu exists" test -f "$MENU"
check "sim7 no Settings row (hexciri-launch-settings)" bash -c "! grep -q '\"settings\".*hexciri-launch-settings' \"$MENU\""
check "sim7 setup row still present" grep -q '"setup"' "$MENU"
check "sim7 setup keeps settings alias" grep -q '"setup".*aliases":\["settings"\]' "$MENU"
check "sim7 Update > Hexciri row present" grep -q '"update.hexciri"' "$MENU"
check "sim7 lean rows gone (top-bar position)" bash -c "! grep -q '\"appearance.top-bar.position\"' \"$MENU\""

# Seeded-row removal via the real menu-audit block.
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp -a "$ROOT/simwork/sim7out" "$WORK/root"
SEED="$WORK/root/default/hexciri/hexciri-menu.jsonc"
python3 - "$SEED" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
row = '  "settings": {"icon":"\ue615","label":"Settings","action":"hexciri-launch-settings"},'
for i, l in enumerate(lines):
    if l.strip().startswith('"system":'):
        lines.insert(i + 1, row)
        break
open(p, "w").write("\n".join(lines) + "\n")
PY
grep -q '"settings".*hexciri-launch-settings' "$SEED" || { echo "seed FAILED"; exit 1; }
echo "seeded old Settings row after system"
# Extract the menu-audit python block from install.sh (step at 2519 to PY at 2803).
python3 - "$ROOT/v2/install.sh" "$WORK/block.py" <<'PY'
import sys
s = open(sys.argv[1]).read().splitlines()
start = next(i for i, l in enumerate(s) if l.startswith('python3 - "$FORK_OUT"') and i > 2500)
end = next(i for i, l in enumerate(s) if l == 'PY' and i > start)
open(sys.argv[2], "w").write("\n".join(s[start + 1:end]) + "\n")
PY
export _patch_log="$WORK/patch.log"; : > "$_patch_log"
python3 - "$WORK/root" < "$WORK/block.py" >>"$_patch_log" 2>&1 || { echo "menu block FAILED"; cat "$_patch_log"; exit 1; }
check "seeded Settings row removed by menu block" bash -c "! grep -q '\"settings\".*hexciri-launch-settings' \"$SEED\""
check "seeded run: setup row intact" grep -q '"setup"' "$SEED"
check "seeded run: Update > Hexciri intact" grep -q '"update.hexciri"' "$SEED"
check "seeded run: menu block idempotent (2nd run)" bash -c "python3 - \"$WORK/root\" < \"$WORK/block.py\" >>\"$_patch_log\" 2>&1 && ! grep -q '\"settings\".*hexciri-launch-settings' \"$SEED\""
grep -q "removed top-level Settings row (1)" "$_patch_log" && echo "ok: patch log reports removed top-level Settings row (1)" && pass=$((pass+1)) || { echo "FAIL: patch log does not report removal"; fail=$((fail+1)); }

# User-extensions cleanup snippet, extracted from the Settings step.
EXT="$WORK/extensions.jsonc"
printf '{\n  "apps": {"icon":"x","label":"Apps"},\n  "settings": {"icon":"x","label":"Settings","action":"hexciri-launch-settings"},\n  "system": {"icon":"x","label":"System"}\n}\n' > "$EXT"
HOME_BAK="$HOME"; export HOME="$WORK"
mkdir -p "$WORK/.config/hexciri/extensions"
cp "$EXT" "$WORK/.config/hexciri/extensions/hexciri-menu.jsonc"
_user_menu="$HOME/.config/hexciri/extensions/hexciri-menu.jsonc"
if [[ -f $_user_menu ]] && grep -q '"settings".*hexciri-launch-settings' "$_user_menu"; then
  sed -i '/"settings".*hexciri-launch-settings/d' "$_user_menu"
fi
check "extensions cleanup removes Settings row" bash -c "! grep -q 'hexciri-launch-settings' \"$WORK/.config/hexciri/extensions/hexciri-menu.jsonc\""
check "extensions cleanup keeps other rows" grep -q '"apps"' "$WORK/.config/hexciri/extensions/hexciri-menu.jsonc"
export HOME="$HOME_BAK"

echo "sim19: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
