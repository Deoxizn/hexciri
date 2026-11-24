#!/bin/bash
# sim22: Install > Style > Background opens the theme backgrounds folder in Strata.
# Runs the sim7 fork pipeline verbatim against the patched install.sh in
# /tmp/bg-live (live nyx HEAD 91299f9 + bg-install-strata patch), NOT the
# shared ~/workspace/hexiri-2.0/v2/install.sh, which a sibling agent
# (minimal re-apply) is concurrently editing from the same base.
# Checks the forked bin/hexciri-theme-bg-install and bin/hexciri-launch-files.
# Regression: the same checks against the unpatched live file must fail.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n /tmp/bg-live/install.sh || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"
# sim7 copy, pointed at /tmp/bg-live for the installer only.
sed 's|INSTALLER_DIR="$HOME/workspace/hexiri-2.0/v2"|INSTALLER_DIR="/tmp/bg-live"|; s|"$HOME/workspace/hexiri-2.0/v2/install.sh"|"/tmp/bg-live/install.sh"|g' \
  "$ROOT/simwork/sim7.sh" > /tmp/bg-sim7.sh
bash /tmp/bg-sim7.sh >/tmp/sim22-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim22-sim7.log; exit 1; }
BG="$ROOT/simwork/sim7out/bin/hexciri-theme-bg-install"
LF="$ROOT/simwork/sim7out/bin/hexciri-launch-files"
check "theme-bg-install exists" test -f "$BG"
check "theme-bg-install opens folder via launch-files" grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$BG"
check "theme-bg-install has no folio call" bash -c "! grep -q '^folio ' \"$BG\""
check "theme-bg-install still mkdirs the folder" grep -q 'mkdir -p "$THEME_USER_BACKGROUNDS"' "$BG"
check "theme-bg-install still reads current theme" grep -q 'current/theme.name' "$BG"
check "launch-files exists" test -f "$LF"
check "launch-files forwards args to strata" grep -q 'exec setsid uwsm-app -- strata "$@"' "$LF"
check "launch-files still uses strata, not folio" bash -c "! grep -q folio \"$LF\""
check "launch-files still via uwsm-app" grep -q 'setsid uwsm-app -- strata' "$LF"
# Menu row still calls the bin, unchanged.
check "menu row still calls hexciri-theme-bg-install" grep -q '"install.style.background".*hexciri-theme-bg-install' "$ROOT/simwork/sim7out/default/hexciri/hexciri-menu.jsonc"
# Idempotency: run the fork pipeline a second time, same result.
bash /tmp/bg-sim7.sh >/tmp/sim22-sim7b.log 2>&1 || { echo "sim7 2nd run FAILED"; exit 1; }
check "2nd fork run: Strata launcher still in place" grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$BG"
check "2nd fork run: launch-files still forwards args" grep -q 'strata "$@"' "$LF"
echo "sim22: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
