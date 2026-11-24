#!/bin/bash
# sim20: zxing-cpp DB race (2026-11-24).
# checkupdates (own temp DB) lists zxing-cpp 3.2.0-1 while pacman -Su
# (main DB, synced seconds earlier) says "there is nothing to do":
# the two syncs can hit different geo-mirror backends. The old code
# then printed "System packages are up to date" while _pending > 0.
# New code: one forced -Syy re-sync + pacman -Qu re-count + second
# -Su, and if that still upgrades 0 it prints an honest "mirror DB
# lag?" warning naming the pending packages, never "up to date".
# Scenarios, with stubbed pacman/checkupdates/hexciri-update-pacman:
#  A. mirror lag, retry fixes it -> "updated (1 package(s))", -Syy called
#  B. mirror still lagging -> "mirror DB lag" + package line, no "up to date"
#  C. no pending -> "System packages are up to date", no -Su, no -Syy
#  D. normal upgrade -> "updated (1 package(s))", no -Syy
# Scenario B is the regression check: the old code printed "up to date"
# there, so this sim fails on the unpatched script.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
check() { local n="$1"; shift; if "$@"; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

# Extract the real system-pkgs heredoc from v2/install.sh.
mkdir -p "$WORK/bin-out"
python3 - "$ROOT/v2/install.sh" "$WORK/bin-out/hexciri-update-system-pkgs" <<'PY'
import sys
s = open(sys.argv[1]).read()
start = s.index('cat > "$FORK_OUT/bin/hexciri-update-system-pkgs"')
start = s.index("\n", start) + 1
end = s.index("\nSYSPKGS_EOF", start)
open(sys.argv[2], "w").write(s[start:end] + "\n")
PY
chmod +x "$WORK/bin-out/hexciri-update-system-pkgs"
bash -n "$WORK/bin-out/hexciri-update-system-pkgs"
check "extracted system-pkgs bash -n clean" test $? -eq 0

# Stubs, driven by $STATE files.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/hexciri-theme-ansi" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$WORK/bin/hexciri-i18n" <<'SH'
#!/bin/bash
echo "Update system packages"
SH
cat >"$WORK/bin/checkupdates" <<'SH'
#!/bin/bash
# $STATE/checkupdates_mode: one | none
if [[ "$(cat "$STATE/checkupdates_mode" 2>/dev/null)" == "one" ]]; then
  echo "zxing-cpp 3.1.1-1 -> 3.2.0-1"
  exit 0
fi
exit 2
SH
cat >"$WORK/bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Sl) exit 0 ;;
  -Qu)
    if [[ -f "$STATE/db_fresh" ]]; then
      echo "zxing-cpp 3.1.1-1 -> 3.2.0-1"
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
SH
cat >"$WORK/bin/hexciri-update-pacman" <<'SH'
#!/bin/bash
# $1: -Sy | -Syy | -Su. $STATE/su_upgrades=1: -Su upgrades.
# $STATE/syy_fresh=1: -Syy makes the main DB fresh (mirror caught up).
case "$1" in
  -Sy) echo "sy" >>"$STATE/calls"; exit 0 ;;
  -Syy)
    echo "syy" >>"$STATE/calls"
    if [[ "$(cat "$STATE/syy_fresh" 2>/dev/null)" == "1" ]]; then
      touch "$STATE/db_fresh"
    fi
    exit 0 ;;
  -Su)
    echo "su" >>"$STATE/calls"
    if [[ -f "$STATE/db_fresh" ]] || [[ "$(cat "$STATE/su_upgrades" 2>/dev/null)" == "1" ]]; then
      echo "(1/1) upgrading zxing-cpp..."
    else
      echo ":: Starting full system upgrade..."
      echo " there is nothing to do"
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
SH
cat >"$WORK/bin/find" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"
export HEXCIRI_UPDATE_UNATTENDED=1

run_scenario() { # $1 = name; sets $STATE, runs script, leaves output in $WORK/out.txt
  export STATE="$WORK/state-$1"
  mkdir -p "$STATE"; : >"$STATE/calls"
  "$WORK/bin-out/hexciri-update-system-pkgs" >"$WORK/out-$1.txt" 2>&1
  echo "rc=$? ($1)"
}

# A. mirror lag, retry fixes it.
export STATE="$WORK/state-A"; mkdir -p "$STATE"
printf one >"$STATE/checkupdates_mode"; printf 0 >"$STATE/su_upgrades"; printf 1 >"$STATE/syy_fresh"
run_scenario A
grep -q 'System packages updated (1 package(s))' "$WORK/out-A.txt"
check "A: retry upgrades zxing-cpp" test $? -eq 0
grep -q 'System packages are up to date' "$WORK/out-A.txt" && fail=$((fail+1)) || pass=$((pass+1)); echo "ok: A: no up-to-date claim"
grep -qx syy "$STATE/calls"
check "A: forced -Syy was called" test $? -eq 0

# B. mirror still lagging.
export STATE="$WORK/state-B"; mkdir -p "$STATE"
printf one >"$STATE/checkupdates_mode"; printf 0 >"$STATE/su_upgrades"; printf 0 >"$STATE/syy_fresh"
run_scenario B
grep -q 'mirror DB lag' "$WORK/out-B.txt"
check "B: honest mirror-lag warning" test $? -eq 0
grep -q 'zxing-cpp 3.1.1-1 -> 3.2.0-1' "$WORK/out-B.txt"
check "B: warning names the pending package" test $? -eq 0
grep -q 'Re-run hexciri update later' "$WORK/out-B.txt"
check "B: warning tells Devi to re-run later" test $? -eq 0
if grep -q 'System packages are up to date' "$WORK/out-B.txt"; then echo "FAIL: B: still claims up to date"; fail=$((fail+1)); else echo "ok: B: no up-to-date claim"; pass=$((pass+1)); fi

# C. no pending.
export STATE="$WORK/state-C"; mkdir -p "$STATE"
printf none >"$STATE/checkupdates_mode"; printf 0 >"$STATE/su_upgrades"; printf 0 >"$STATE/syy_fresh"
run_scenario C
grep -q 'System packages are up to date' "$WORK/out-C.txt"
check "C: no pending -> up to date" test $? -eq 0
if grep -qx su "$STATE/calls"; then echo "FAIL: C: -Su ran with nothing pending"; fail=$((fail+1)); else echo "ok: C: no -Su run"; pass=$((pass+1)); fi
if grep -qx syy "$STATE/calls"; then echo "FAIL: C: -Syy ran with nothing pending"; fail=$((fail+1)); else echo "ok: C: no -Syy run"; pass=$((pass+1)); fi

# D. normal upgrade, no retry needed.
export STATE="$WORK/state-D"; mkdir -p "$STATE"
printf one >"$STATE/checkupdates_mode"; printf 1 >"$STATE/su_upgrades"; printf 0 >"$STATE/syy_fresh"
run_scenario D
grep -q 'System packages updated (1 package(s))' "$WORK/out-D.txt"
check "D: normal upgrade reported" test $? -eq 0
if grep -qx syy "$STATE/calls"; then echo "FAIL: D: -Syy ran on a normal upgrade"; fail=$((fail+1)); else echo "ok: D: no -Syy on normal upgrade"; pass=$((pass+1)); fi

echo "sim20: pass=$pass fail=$fail"
test "$fail" -eq 0
