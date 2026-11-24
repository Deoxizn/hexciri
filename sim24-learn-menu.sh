#!/bin/bash
# sim24: Learn menu rework (2026-11-24, Devi: tmux?, no kitty link, QS?).
# Runs the sim7 fork pipeline verbatim against the patched install.sh in
# /tmp/learn-live (live nyx HEAD 74fe03b3 + Learn patch), NOT the shared
# ~/workspace/hexiri-2.0/v2/install.sh, which a sibling agent (AI/Foot
# restore) may be editing concurrently.
# Checks: Learn rows kept/added/dropped, tmux config copied + renamed,
# tmux bin present, no discord invite in menu, idempotent 2nd run.
# Regression: same checks against the unpatched live file must fail.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
MENU="$ROOT/simwork/sim7out/default/hexciri/hexciri-menu.jsonc"
BIN="$ROOT/simwork/sim7out/bin"
OUT="$ROOT/simwork/sim7out"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n /tmp/learn-live/v2/install.sh || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"
mkdir -p /tmp/learn-live/v2
sed 's|INSTALLER_DIR="$HOME/workspace/hexiri-2.0/v2"|INSTALLER_DIR="/tmp/learn-live/v2"|; s|"$HOME/workspace/hexiri-2.0/v2/install.sh"|"/tmp/learn-live/v2/install.sh"|g' \
  "$ROOT/simwork/sim7.sh" > /tmp/learn-sim7.sh
bash /tmp/learn-sim7.sh >/tmp/sim24-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim24-sim7.log; exit 1; }
echo "sim7 fork pipeline done"

# Kept Learn rows.
for k in learn learn.keybindings learn.hexciri learn.hyprland learn.arch learn.bash learn.tmux-keybindings; do
  check "learn row kept: $k" grep -q "\"$k\"" "$MENU"
done
# Added Learn rows.
for k in learn.zed learn.fish learn.kitty learn.quickshell; do
  check "learn row added: $k" grep -q "\"$k\"" "$MENU"
done
# Dropped Learn rows.
for k in learn.neovim learn.community learn.herdr-keybindings; do
  check "learn row dropped: $k" bash -c "! grep -q '\"$k\"' \"$MENU\""
done
# Added rows point at the right docs (webapp, Hexciri bins).
check "zed row opens zed docs" grep -q "learn.zed.*zed.dev/docs" "$MENU"
check "fish row opens fish docs" grep -q "learn.fish.*fishshell.com/docs" "$MENU"
check "kitty row opens kitty docs" grep -q "learn.kitty.*sw.kovidgoyal.net/kitty" "$MENU"
check "quickshell row opens quickshell docs" grep -q "learn.quickshell.*quickshell.org/docs" "$MENU"
check "hyprland/arch/bash rows still webapp docs" bash -c "grep -q \"learn.hyprland.*wiki.hypr.land\" \"$MENU\" && grep -q \"learn.arch.*wiki.archlinux.org\" \"$MENU\" && grep -q \"learn.bash.*devhints.io/bash\" \"$MENU\""
check "hexciri row still opens repo via launch-manual" grep -q "learn.hexciri.*hexciri-launch-manual" "$MENU"
# No Omarchy Discord anywhere in the menu.
check "menu has no discord invite" bash -c "! grep -q discord.gg \"$MENU\""
check "menu has no learn.community action" bash -c "! grep -q hexciri-launch-discord-community \"$MENU\""
# Tmux: bin + config copied, config rename applied.
check "tmux-keybindings bin present" test -x "$BIN/hexciri-menu-tmux-keybindings"
check "tmux config copied into fork" test -f "$OUT/config/tmux/tmux.conf"
check "tmux.conf fallback path renamed" grep -q 'HEXCIRI_PATH/config/tmux/tmux.conf' "$BIN/hexciri-menu-tmux-keybindings"
check "tmux.conf popup bind renamed" grep -q 'hexciri-menu-tmux-keybindings --print' "$OUT/config/tmux/tmux.conf"
check "tmux.conf has no omarchy refs" bash -c "! grep -qi omarchy \"$OUT/config/tmux/tmux.conf\""
check "launch-terminal-tmux bin present" test -x "$BIN/hexciri-launch-terminal-tmux"
# Learn rows' actions resolve (webapp/menu bins exist).
for b in hexciri-launch-webapp hexciri-launch-manual hexciri-menu-tmux-keybindings; do
  check "learn action bin present: $b" test -x "$BIN/$b"
done
# Idempotent: run the fork pipeline a second time, menu must be identical.
cp "$MENU" /tmp/sim24-menu-1.jsonc
bash /tmp/learn-sim7.sh >/tmp/sim24-sim7-2.log 2>&1 || { echo "sim7 2nd run FAILED"; tail -20 /tmp/sim24-sim7-2.log; exit 1; }
check "2nd fork run idempotent (menu identical)" cmp -s "$MENU" /tmp/sim24-menu-1.jsonc
check "2nd run tmux config still present" test -f "$OUT/config/tmux/tmux.conf"

echo "---- regression: unpatched live file must FAIL these checks ----"
# Rebuild the fork from the pristine live file (74fe03b3) and expect the
# new rows absent / dropped rows present / tmux config missing.
cp /tmp/learn-live/v2/install.sh /tmp/sim24-patched-install.sh
curl -fsSL https://raw.githubusercontent.com/Deoxizn/hexciri/74fe03b3442d3d69beb0bfc18de857a295a32612/v2/install.sh -o /tmp/learn-live/v2/install.sh
bash /tmp/learn-sim7.sh >/tmp/sim24-sim7-reg.log 2>&1 || { echo "regression sim7 FAILED (unexpected)"; tail -20 /tmp/sim24-sim7-reg.log; }
regfail=0
for k in learn.zed learn.fish learn.kitty learn.quickshell; do
  grep -q "\"$k\"" "$MENU" && { echo "REGRESSION FAIL: $k present in unpatched fork"; regfail=1; }
done
grep -q '"learn.neovim"' "$MENU" || { echo "REGRESSION FAIL: learn.neovim absent in unpatched fork"; regfail=1; }
grep -q '"learn.community"' "$MENU" || { echo "REGRESSION FAIL: learn.community absent in unpatched fork"; regfail=1; }
[ -f "$OUT/config/tmux/tmux.conf" ] && { echo "REGRESSION FAIL: tmux config present in unpatched fork"; regfail=1; }
[ "$regfail" = 0 ] && echo "regression checks pass (unpatched file lacks the fix)"
# Restore the patched installer.
cp /tmp/sim24-patched-install.sh /tmp/learn-live/v2/install.sh

echo "sim24: $pass passed, $fail failed"
[ "$fail" = 0 ] && [ "$regfail" = 0 ] || exit 1
