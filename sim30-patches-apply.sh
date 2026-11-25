#!/usr/bin/env bash
# sim30: reproduce Devi 2026-11-24 16:54 MST laptop failure, prove the fix.
#   ERROR: v2/patches/apply.sh not in the installer tree
#          (/home/devi/.local/opt/hexciri-nyx/v2/patches)
# Root cause: apply.sh is mode 644 in the repo (push-files lands 644),
# and install.sh guarded it with [ -x ]. The patches dir IS pulled;
# only the +x bit is missing, and nothing needs it (bash-invoked).
#
# Runs the sim7 fork pipeline verbatim against two clones of live nyx
# a812b576, both with patches at repo modes (apply.sh 644, not +x):
#   A. unpatched -> must die with Devi's exact error at the patch step
#   B. patched   -> must fork clean, all 12 patches applied, menu parses
# Plus: bash -n on both changed files, fingerprints old vs new, and the
# updater's new post-sync patches check in isolation.
set -u
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
BASE=/tmp/patches-apply-fix
SIMROOT="$HOME/workspace/hexiri-2.0/simwork"

run_fork() { # $1 = stage dir, $2 = out dir, $3 = log file
  local stage="$1" out="$2" log="$3" sim
  sim="$BASE/sim7-$(basename "$2").sh"
  rm -rf "$out"; mkdir -p "$out"
  sed -e "s#\$HOME/workspace/hexiri-2.0/v2#$stage/v2#g" \
      -e "s#\$HOME/workspace/hexiri-2.0/simwork#$SIMROOT#g" \
      -e "s#\$HOME/workspace/hexiri-2.0\"#$stage\"#g" \
      "$SIMROOT/sim7.sh" > "$sim"
  # sim7.sh hardcodes FORK_OUT=sim7out under SIMROOT; point it at $out
  sed -i "s#FORK_OUT=\"\$SIMROOT/sim7out\"#FORK_OUT=\"$out\"#" "$sim"
  # and the fork-block extraction path
  sed -i "s#\"\$HOME/workspace/hexiri-2.0/v2/install.sh\"#\"$stage/v2/install.sh\"#g" "$sim"
  bash "$sim" > "$log" 2>&1
  return $?
}

# --- 0. preconditions: live modes, bash -n ---
[ "$(stat -c %a "$BASE/unpatched/v2/patches/apply.sh")" = "660" ] || [ "$(stat -c %a "$BASE/unpatched/v2/patches/apply.sh")" = "644" ] && ok "unpatched clone apply.sh is not executable (repo mode, like Devi's laptop)" || bad "unpatched apply.sh unexpectedly +x"
bash -n "$BASE/patched/v2/install.sh" && ok "bash -n patched install.sh" || bad "bash -n patched install.sh"
bash -n "$BASE/patched/v2/hexciri-update-hexciri" && ok "bash -n patched hexciri-update-hexciri" || bad "bash -n patched updater"
grep -q '\[ -f "\$PATCHES_DIR/apply.sh" \]' "$BASE/patched/v2/install.sh" && ok "patched guard is -f, not -x" || bad "patched guard not -f"
grep -q '\[ -x "\$PATCHES_DIR/apply.sh" \]' "$BASE/patched/v2/install.sh" && bad "patched file still has -x guard" || ok "no -x guard left in patched install.sh"
grep -q 'cloned tree has no v2/patches/apply.sh' "$BASE/patched/v2/hexciri-update-hexciri" && ok "updater git_sync checks patches presence" || bad "updater git_sync check missing"
grep -q 'extracted tree has no v2/patches/apply.sh' "$BASE/patched/v2/hexciri-update-hexciri" && ok "updater tarball_sync checks patches presence" || bad "updater tarball check missing"

# --- 1. fingerprints: only patch moves (updater is in patch_fp list) ---
OLD_FP="$(bash "$BASE/unpatched/v2/install.sh" --print-fingerprints 2>/dev/null)"
NEW_FP="$(bash "$BASE/patched/v2/install.sh" --print-fingerprints 2>/dev/null)"
[ -n "$OLD_FP" ] && [ -n "$NEW_FP" ] && ok "fingerprints print on both" || bad "fingerprints did not print"
for k in upstream provision system; do
  o="$(printf '%s\n' "$OLD_FP" | grep "^$k=" | cut -d= -f2)"
  n="$(printf '%s\n' "$NEW_FP" | grep "^$k=" | cut -d= -f2)"
  [ "$o" = "$n" ] && ok "$k fingerprint stable" || bad "$k fingerprint moved ($o -> $n)"
done
o="$(printf '%s\n' "$OLD_FP" | grep '^patch=' | cut -d= -f2)"
n="$(printf '%s\n' "$NEW_FP" | grep '^patch=' | cut -d= -f2)"
[ "$o" != "$n" ] && ok "patch fingerprint changed (updater file in patch_fp list)" || bad "patch fingerprint did not change"

# --- 2. negative control: unpatched fork dies with Devi's exact error ---
if run_fork "$BASE/unpatched" "$BASE/sim-unpatched-out" "$BASE/sim-unpatched.log"; then
  bad "unpatched fork unexpectedly succeeded (bug not reproduced)"
else
  grep -q 'v2/patches/apply.sh missing from the installer tree\|v2/patches/apply.sh not in the installer tree' "$BASE/sim-unpatched.log" \
    && ok "unpatched fork dies with Devi's exact apply.sh error" \
    || { bad "unpatched fork died, but not with the apply.sh error"; tail -5 "$BASE/sim-unpatched.log"; }
fi

# --- 3. patched fork: clean, all 12 patches, menu parses ---
if run_fork "$BASE/patched" "$BASE/sim-patched-out" "$BASE/sim-patched.log"; then
  ok "patched fork completes (no apply.sh die)"
else
  bad "patched fork failed"; tail -15 "$BASE/sim-patched.log"
fi
OUT="$BASE/sim-patched-out"
[ -f "$OUT/default/hypr/bootstrap.lua" ] && grep -q 'package.path' "$OUT/default/hypr/bootstrap.lua" && ok "patched fork has valid bootstrap.lua" || bad "patched fork bootstrap.lua bad"
grep -q 'require("default.hypr.bindings.hexciri")' "$OUT/default/hypr/hexciri.lua" 2>/dev/null && ok "patched fork hexciri.lua requires custom binds" || bad "patched fork hexciri.lua binds require missing"
python3 - "$OUT/default/hexciri/hexciri-menu.jsonc" <<'PY' && ok "patched fork menu jsonc parses (369 entries expected)" || bad "patched fork menu jsonc does not parse"
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r'(?m)^\s*//.*$', '', raw)
raw = re.sub(r',(\s*[}\]])', r'\1', raw)
d = json.loads(raw)
assert len(d) >= 9, len(d)
PY
[ -f "$OUT/config/tmux/tmux.conf" ] && ok "patched fork has config/tmux/tmux.conf" || bad "patched fork tmux.conf missing"
[ -f "$OUT/applications/foot.desktop" ] && ok "patched fork has applications/foot.desktop" || bad "patched fork foot.desktop missing"
grep -q 'Fork:' "$BASE/sim-patched.log" && ok "patched fork printed Fork summary" || bad "no Fork summary in patched log"

# --- 4. updater patches check in isolation (fake checkouts) ---
mkdir -p "$BASE/fake-with/v2/patches" "$BASE/fake-without/v2"
touch "$BASE/fake-with/v2/install.sh" "$BASE/fake-with/v2/patches/apply.sh"
touch "$BASE/fake-without/v2/install.sh"
CHECKOUT="$BASE/fake-with"; [ -f "$CHECKOUT/v2/patches/apply.sh" ] && ok "updater check passes with patches present" || bad "updater check fails with patches present"
CHECKOUT="$BASE/fake-without"; [ -f "$CHECKOUT/v2/patches/apply.sh" ] && bad "updater check passes without patches" || ok "updater check fails without patches (early sync fail, not late fork die)"

echo "sim30: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
