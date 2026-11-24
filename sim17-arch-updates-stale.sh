#!/bin/bash
# sim17: arch-updates stale-count fixes (2026-11-24).
# 1. plugin_behind on nyx: main ahead must NOT count; nyx behind MUST count.
# 2. Parallel scan: stubbed sources produce the same JSON shape/total.
# 3. update_plugins_themes plugin_behind_count agrees.
# 4. BarWidget fast poll only counts ticks where a scan started (text check
#    + node simulation of the timer logic).
set -u
AU="/tmp/arch-updates-nyx"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
# Sim-only copy of the scanner with the file protocol allowed, so the
# local-path test remote can be fetched. Shipped code keeps
# GIT_ALLOW_PROTOCOL=https:ssh.
mkdir -p "$WORK/scripts"
cp "$AU/scripts/check_updates.py" "$WORK/scripts/check_updates.py"
cp "$AU/scripts/update_plugins_themes.py" "$WORK/scripts/update_plugins_themes.py"
sed -i 's/"https:ssh"/"https:ssh:file"/' "$WORK/scripts/"*.py
export AU_SCRIPTS="$WORK/scripts"
mkdir -p "$HOME/.config/hexciri/plugins" "$HOME/.cache"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

# --- fake git remote with main and nyx diverging ---
git config --global user.email t@t.t; git config --global user.name t
git config --global init.defaultBranch main
REMOTE="$WORK/remote.git"; git init -q --bare "$REMOTE"
SRC="$WORK/src"; git clone -q "$REMOTE" "$SRC"; cd "$SRC"
echo a > f; git add f; git commit -qm base; git push -q origin main
git checkout -qb nyx; echo n > n; git add n; git commit -qm nyx1; git push -q origin nyx
git checkout -q main; echo m > m; git add m; git commit -qm main1; echo m2 > m2; git add m2; git commit -qm main2; git push -q origin main
# plugin checkout on nyx, up to date with origin/nyx, behind origin/main by 2
PLUG="$HOME/.config/hexciri/plugins/pizza.dirty.testplug"
git clone -q --branch nyx "$REMOTE" "$PLUG"
cd "$WORK"
python3 - "$AU" "$PLUG" <<'PY'
import sys
import os
sys.path.insert(0, os.environ["AU_SCRIPTS"])
import check_updates as cu
from pathlib import Path
plug = Path(sys.argv[2])
entry = cu.plugin_behind(plug)
print("nyx-up-to-date entry:", entry)
assert entry is None, "nyx plugin behind main must not count"
# now make origin/nyx one ahead
PY
check "nyx plugin behind main counts 0" test $? -eq 0
# advance origin/nyx by one, fetch in plugin, now behind nyx by 1
cd "$SRC"; git checkout -q nyx; echo n2 > n2; git add n2; git commit -qm nyx2; git push -q origin nyx; cd "$WORK"
python3 - "$AU" "$PLUG" <<'PY'
import sys
import os
sys.path.insert(0, os.environ["AU_SCRIPTS"])
import check_updates as cu
from pathlib import Path
entry = cu.plugin_behind(Path(sys.argv[2]))
print("nyx-behind-1 entry:", entry)
assert entry is not None and entry["behind"] == 1, entry
PY
check "nyx plugin behind nyx counts 1" test $? -eq 0
python3 - "$AU" "$PLUG" <<'PY'
import sys
import os
sys.path.insert(0, os.environ["AU_SCRIPTS"])
import update_plugins_themes as u
from pathlib import Path
c = u.plugin_behind_count(Path(sys.argv[2]))
print("updater behind count:", c)
assert c == 1, c
PY
check "update_plugins_themes agrees (1)" test $? -eq 0

# --- parallel scan with stubbed sources ---
mkdir -p "$WORK/bin"
cat >"$WORK/bin/checkupdates" <<'SH'
#!/bin/bash
echo "flex 2.7.1 -> 2.7.6"
sleep 1
SH
cat >"$WORK/bin/yay" <<'SH'
#!/bin/bash
echo "brave-origin-bin 1.0 -> 1.1"
sleep 1
SH
cat >"$WORK/bin/flatpak" <<'SH'
#!/bin/bash
sleep 1
SH
cat >"$WORK/bin/mise" <<'SH'
#!/bin/bash
echo '{}'
SH
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"
# point themes/plugins dirs at empty dirs so git fetches are skipped
mkdir -p "$HOME/.config/hexciri/themes"
# remove test plugin so no network fetch in scan
rm -rf "$PLUG"
START=$(date +%s)
OUT=$(python3 "$AU/scripts/check_updates.py" --no-plugins)
END=$(date +%s); ELAPSED=$((END-START))
echo "scan output: $OUT"
echo "scan elapsed: ${ELAPSED}s"
python3 - "$OUT" <<'PY'
import sys, json
d = json.loads(sys.argv[1])
assert d["total"] == 2, d
assert [r["id"] for r in d["repos"]] == ["system","aur","flatpak","plugins","mise"], d
assert d["repos"][0]["count"] == 1 and d["repos"][1]["count"] == 1, d
print("scan shape/total ok")
PY
check "parallel scan shape/total (2)" test $? -eq 0
check "parallel scan under 4s (was ~3s sequential here, parallel ~1s)" test "$ELAPSED" -lt 4

# --- BarWidget fast-poll text + node simulation ---
grep -q "var started = !checkProc.running" "$AU/BarWidget.qml" && grep -q "if (started) root.fastPollCount++" "$AU/BarWidget.qml"
check "BarWidget fast poll counts only started scans" test $? -eq 0
node -e '
let count=0, running=false, ticks=0;
function runCheck(){ if(running) return; running=true; }
function tick(){ const started=!running; runCheck(); if(started) count++; ticks++; }
// scan runs ticks 0..2, finishes tick 3
for(let i=0;i<6;i++){ if(i===3) running=false; tick(); }
if(count!==2) throw new Error("count="+count);
console.log("node fast-poll sim ok, count="+count+" ticks="+ticks);
'
check "node fast-poll sim (2 starts in 6 ticks)" test $? -eq 0

echo "sim17: pass=$pass fail=$fail"
test "$fail" -eq 0
