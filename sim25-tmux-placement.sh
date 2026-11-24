#!/bin/bash
# sim25: tmux placement failure (2026-11-24, update to 2cdc33c7 died at
# placement verification, exit 1, Super+Space / Super+Alt+Space broken).
# Runs the sim7 fork pipeline verbatim against the patched install.sh in
# /tmp/tmux-live, then simulates the placement cp line (the exact dirs
# the installer copies to /usr/share/hexciri) into /tmp/tmux-place and
# checks the $HEXCIRI_PATH/config/* verification targets exist there.
# Regression: same placement simulation against the unpatched live file
# must fail (config/ never copied).
set -u
ROOT="$HOME/workspace/hexiri-2.0"
OUT="$ROOT/simwork/sim7out"
PLACE="/tmp/tmux-place"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n /tmp/tmux-live/v2/install.sh || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"
sed 's|INSTALLER_DIR="$HOME/workspace/hexiri-2.0/v2"|INSTALLER_DIR="/tmp/tmux-live/v2"|; s|"$HOME/workspace/hexiri-2.0/v2/install.sh"|"/tmp/tmux-live/v2/install.sh"|g' \
  "$ROOT/simwork/sim7.sh" > /tmp/tmux-sim7.sh
bash /tmp/tmux-sim7.sh >/tmp/sim25-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim25-sim7.log; exit 1; }
echo "sim7 fork pipeline done"

# Fork contains the curated config/ subsets.
for f in config/tmux/tmux.conf config/kitty/kitty.conf config/chromium-flags.conf config/alacritty/alacritty.toml config/ghostty/config config/shell.json config/hypr/hyprland.lua; do
  check "fork has $f" test -f "$OUT/$f"
done
check "fork config has no omarchy-named file/dir" bash -c "! find \"$OUT/config\" -iname '*omarchy*' -print -quit | grep -q ."
check "tmux.conf fallback renamed to HEXCIRI_PATH" grep -q 'HEXCIRI_PATH/config/tmux/tmux.conf' "$OUT/bin/hexciri-menu-tmux-keybindings"
check "tmux.conf has no omarchy refs" bash -c "! grep -qi omarchy \"$OUT/config/tmux/tmux.conf\""

# Placement simulation: the exact cp line from the patched installer.
rm -rf "$PLACE"; mkdir -p "$PLACE"
grep -q '"$FORK_OUT/config" "$HEXCIRI_PATH/"' /tmp/tmux-live/v2/install.sh || { echo "FAIL: placement cp line does not include config/"; fail=$((fail+1)); }
cp -a "$OUT/shell" "$OUT/default" "$OUT/themes" "$OUT/bin" "$OUT/install" "$OUT/icons" "$OUT/config" "$PLACE/"
check "placed tree has config/tmux/tmux.conf" test -f "$PLACE/config/tmux/tmux.conf"
check "placed tree has config/chromium-flags.conf" test -f "$PLACE/config/chromium-flags.conf"
check "placed tree has config/alacritty/alacritty.toml" test -f "$PLACE/config/alacritty/alacritty.toml"
check "placed tree has config/ghostty/config" test -f "$PLACE/config/ghostty/config"
check "placed tree has config/kitty/kitty.conf" test -f "$PLACE/config/kitty/kitty.conf"
check "placed config has no omarchy-named file/dir" bash -c "! find \"$PLACE/config\" -iname '*omarchy*' -print -quit | grep -q ."
# The placement verification lines that died / would have died next.
check "verification tmux check passes on placed tree" test -f "$PLACE/config/tmux/tmux.conf"
check "verification chromium-flags check passes" test -f "$PLACE/config/chromium-flags.conf"
check "verification alacritty check passes" test -f "$PLACE/config/alacritty/alacritty.toml"
check "verification ghostty check passes" test -f "$PLACE/config/ghostty/config"
# User tmux placement block present in the installer.
check "installer places user tmux.conf" grep -q 'place_user_file "$FORK_OUT/config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"' /tmp/tmux-live/v2/install.sh
# Idempotent fork: second run, config still there.
cp "$OUT/config/tmux/tmux.conf" /tmp/sim25-tmux-1.conf
bash /tmp/tmux-sim7.sh >/tmp/sim25-sim7-2.log 2>&1 || { echo "sim7 2nd run FAILED"; tail -20 /tmp/sim25-sim7-2.log; exit 1; }
check "2nd fork run idempotent (tmux.conf identical)" cmp -s "$OUT/config/tmux/tmux.conf" /tmp/sim25-tmux-1.conf

echo "---- regression: unpatched live file must FAIL placement ----"
cp /tmp/tmux-live/v2/install.sh /tmp/sim25-patched-install.sh
curl -fsSL https://raw.githubusercontent.com/Deoxizn/hexciri/2cdc33c797cda4a6bc43af227e0465696b0c7daf/v2/install.sh -o /tmp/tmux-live/v2/install.sh
regfail=0
grep -q '"$FORK_OUT/config" "$HEXCIRI_PATH/"' /tmp/tmux-live/v2/install.sh && { echo "REGRESSION FAIL: unpatched placement copies config/"; regfail=1; }
bash /tmp/tmux-sim7.sh >/tmp/sim25-sim7-reg.log 2>&1 || { echo "regression sim7 FAILED (unexpected)"; tail -20 /tmp/sim25-sim7-reg.log; }
rm -rf "$PLACE"; mkdir -p "$PLACE"
cp -a "$OUT/shell" "$OUT/default" "$OUT/themes" "$OUT/bin" "$OUT/install" "$OUT/icons" "$PLACE/"
[ -f "$PLACE/config/tmux/tmux.conf" ] && { echo "REGRESSION FAIL: tmux.conf present in unpatched placement"; regfail=1; }
[ "$regfail" = 0 ] && echo "regression checks pass (unpatched file lacks the fix)"
cp /tmp/sim25-patched-install.sh /tmp/tmux-live/v2/install.sh

echo "sim25: $pass passed, $fail failed"
[ "$fail" = 0 ] && [ "$regfail" = 0 ] || exit 1
