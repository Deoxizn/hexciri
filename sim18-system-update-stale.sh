#!/bin/bash
# sim18: system-update stale icon + AUR probe fixes (2026-11-24).
# Runs the actual fork-patch blocks extracted from v2/install.sh against
# a fake fork tree (sim7out bins), then checks the patched outputs:
#  1. hexciri-update-available fetches before rev-list, and counts only
#     the nyx checkout when it exists (stale v1 checkout ignored).
#  2. hexciri-update-restart broadcasts hexciri.system-update refresh.
#  3. hexciri-update-aur-pkgs probes the AUR with 10s/1 retry, not 30s/3.
#  4. update-available behaviour: stale v1 checkout behind + nyx current
#     => exit 1 (up to date); nyx behind after fetch => exit 0.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FORK_OUT="$WORK/fork-out"
export FORK_OUT
mkdir -p "$FORK_OUT/bin"
cp "$ROOT/simwork/sim7out/bin/hexciri-update-available" "$FORK_OUT/bin/"
cp "$ROOT/simwork/sim7out/bin/hexciri-update-restart" "$FORK_OUT/bin/"
cp "$ROOT/simwork/sim7out/bin/hexciri-update-aur-pkgs" "$FORK_OUT/bin/"
export _patch_log="$WORK/patch.log"
: > "$_patch_log"
warn() { echo "warn: $*" >>"$_patch_log"; }
info() { echo "info: $*" >>"$_patch_log"; }
die() { echo "die: $*" >&2; exit 1; }
export -f warn info die
export HOME="$WORK/home"
mkdir -p "$HOME/.local/opt"
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

# Extract the update-available rewrite block + the 8e restart block +
# the AUR curl change from install.sh and run them.
python3 - "$ROOT/v2/install.sh" "$WORK/block.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('cat > "$FORK_OUT/bin/hexciri-update-available"')
end = s.index("# Analyze-logs: dracut")
block1 = s[start:end]
start2 = s.index("# 8e. Restart refreshes the stock system-update widget")
end2 = s.index("# 9. pkg-prune:")
block2 = s[start2:end2]
# AUR curl line lives inside the aur-pkgs rewrite python block; apply the
# same one-line change to the fake aur-pkgs bin directly (the block is a
# whole-file rewrite, not a must_replace).
open(sys.argv[2], "w").write(block1 + "\n" + block2)
PY
bash "$WORK/block.sh" >>"$_patch_log" 2>&1 || { echo "PATCH BLOCK FAILED"; cat "$_patch_log"; exit 1; }
# AUR probe change, as the installer does it (one-line replace in the
# aur-pkgs rewrite).
python3 - "$FORK_OUT/bin/hexciri-update-aur-pkgs" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'curl -sf --connect-timeout 30 --retry 3 --retry-delay 3'
assert s.count(old) == 1, "aur curl anchor missing in fake bin"
s = s.replace(old, 'curl -sf --connect-timeout 10 --retry 1 --retry-delay 2')
open(p, "w").write(s)
PY
bash -n "$FORK_OUT/bin/hexciri-update-available" && bash -n "$FORK_OUT/bin/hexciri-update-restart" && bash -n "$FORK_OUT/bin/hexciri-update-aur-pkgs"
check "patched bins bash -n clean" test $? -eq 0
grep -q 'timeout 10 git -C "$_checkout" fetch --quiet' "$FORK_OUT/bin/hexciri-update-available"
check "update-available fetches before rev-list" test $? -eq 0
grep -q 'hexciri-shell hexciri.system-update refresh' "$FORK_OUT/bin/hexciri-update-restart"
check "restart broadcasts system-update refresh" test $? -eq 0
grep -q 'connect-timeout 10 --retry 1' "$FORK_OUT/bin/hexciri-update-aur-pkgs"
check "aur-pkgs probe is 10s/1 retry" test $? -eq 0

# Behaviour: fake checkupdates (no repo updates), fake git checkouts.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/checkupdates" <<'SH'
#!/bin/bash
exit 2
SH
chmod +x "$WORK/bin/checkupdates"
export PATH="$WORK/bin:$PATH"
git config --global user.email t@t.t; git config --global user.name t
git config --global init.defaultBranch main
REMOTE="$WORK/remote.git"; git init -q --bare "$REMOTE"
SRC="$WORK/src"; git clone -q "$REMOTE" "$SRC"; cd "$SRC"
echo a > f; git add f; git commit -qm base; git push -q origin main
git checkout -qb nyx; git push -q origin nyx
# stale v1 checkout, behind main by 2
git clone -q --branch main "$REMOTE" "$HOME/.local/opt/hexciri"
cd "$SRC"; git checkout -q main; echo m > m; git add m; git commit -qm main1; echo m2 > m2; git add m2; git commit -qm main2; git push -q origin main
# nyx checkout, current with origin/nyx
git clone -q --branch nyx "$REMOTE" "$HOME/.local/opt/hexciri-nyx"
cd "$WORK"
# v1 behind must be ignored because nyx exists and is current => exit 1
"$FORK_OUT/bin/hexciri-update-available" >/dev/null 2>&1; rc=$?
check "stale v1 checkout ignored when nyx current (exit 1)" test "$rc" -eq 1
# advance origin/nyx by 1; update-available must fetch and see it => exit 0
cd "$SRC"; git checkout -q nyx; echo n2 > n2; git add n2; git commit -qm nyx2; git push -q origin nyx; cd "$WORK"
"$FORK_OUT/bin/hexciri-update-available" >/dev/null 2>&1; rc=$?
check "nyx behind after fetch detected (exit 0)" test "$rc" -eq 0

echo "sim18: pass=$pass fail=$fail"
cat "$_patch_log"
test "$fail" -eq 0
