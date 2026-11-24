#!/bin/bash
# sim24: AI + Foot correction to the 74fe03b3 full Install/Remove restore
# (2026-11-24, Devi 14:46 MST). Rebased onto live nyx HEAD 2cdc33c7
# (Learn menu fix) after the race warning; the Learn fix must survive.
# Runs the sim7 fork pipeline verbatim against the patched install.sh in
# /tmp/ai-foot-live (live nyx HEAD 2cdc33c7 + ai-foot-restore patch), NOT
# the shared ~/workspace/hexiri-2.0/v2/install.sh.
# Checks: AI rows present (except Herdr), Foot row present, Kitty still
# default, Foot out of the trim list, Herdr bin/row absent, every
# restored row's action bins exist, no folio/nautilus/herdr in restored
# rows or bins, Foot data files present, Learn fix intact, idempotent
# 2nd run. Regression: same checks fail on the unpatched live file.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
MENU="$ROOT/simwork/sim7out/default/hexciri/hexciri-menu.jsonc"
BIN="$ROOT/simwork/sim7out/bin"
OUT="$ROOT/simwork/sim7out"
PATCHED="/tmp/ai-foot-live/install.sh"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n "$PATCHED" || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"
sed 's|INSTALLER_DIR="$HOME/workspace/hexiri-2.0/v2"|INSTALLER_DIR="/tmp/ai-foot-live"|; s|"$HOME/workspace/hexiri-2.0/v2/install.sh"|"/tmp/ai-foot-live/install.sh"|g' \
  "$ROOT/simwork/sim7.sh" > /tmp/ai-foot-sim7.sh
bash /tmp/ai-foot-sim7.sh >/tmp/sim24-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim24-sim7.log; exit 1; }
echo "sim7 fork pipeline done"

# Restored Install > AI rows (header + 11, Herdr out).
for k in install.ai install.ai.amp install.ai.antigravity install.ai.chatgpt install.ai.claude install.ai.grok-bot install.ai.hermes install.ai.lm-studio install.ai.ollama install.ai.openclaw install.ai.perplexity install.ai.t3-code; do
  check "install.ai row present: $k" grep -q "\"$k\"" "$MENU"
done
# Restored Remove > AI rows (header + 11).
for k in remove.ai remove.ai.amp remove.ai.antigravity remove.ai.chatgpt remove.ai.claude remove.ai.grok-bot remove.ai.hermes remove.ai.lm-studio remove.ai.ollama remove.ai.openclaw remove.ai.perplexity remove.ai.t3-code; do
  check "remove.ai row present: $k" grep -q "\"$k\"" "$MENU"
done
# Foot: Install row + default-terminal choice row (choice, not default).
check "install.terminal.foot present" grep -q '"install.terminal.foot"' "$MENU"
check "setup.default.terminal.foot present" grep -q '"setup.default.terminal.foot"' "$MENU"
check "install.terminal.kitty present" grep -q '"install.terminal.kitty"' "$MENU"
check "setup.default.terminal.kitty present" grep -q '"setup.default.terminal.kitty"' "$MENU"
check "remove.package present (Foot removal path, no upstream remove.terminal)" grep -q '"remove.package"' "$MENU"
# Dropped rows stay gone.
for k in install.ai.herdr remove.ai.herdr install.windows install.preinstalls install.editor.emacs install.development.docker-dbs remove.windows remove.preinstalls remove.factory-reset remove.security.sudoless-docker; do
  check "dropped row absent: $k" bash -c "! grep -q '\"$k\"' \"$MENU\""
done
# Restored bins exist.
for b in hexciri-install-ai-chatgpt hexciri-install-ai-claude hexciri-install-ai-hermes hexciri-install-ai-openclaw hexciri-install-ai-t3-code hexciri-remove-ai-amp hexciri-remove-ai-antigravity hexciri-remove-ai-chatgpt hexciri-remove-ai-claude hexciri-remove-ai-grok-bot hexciri-remove-ai-hermes hexciri-remove-ai-lm-studio hexciri-remove-ai-ollama hexciri-remove-ai-openclaw hexciri-remove-ai-perplexity hexciri-remove-ai-t3-code hexciri-install-hermes-cli hexciri-install-openclaw-cli hexciri-install-t3code-app hexciri-openclaw-onboard hexciri-launch-openclaw; do
  check "bin present: $b" test -x "$BIN/$b"
done
check "herdr bin absent" bash -c "! test -e \"$BIN/hexciri-install-ai-herdr\""
# Foot data files the install-terminal bin reads.
check "foot config copied" test -f "$OUT/config/foot/foot.ini"
check "foot desktop entry copied" test -f "$OUT/applications/foot.desktop"
check "alacritty config still copied" test -f "$OUT/config/alacritty/alacritty.toml"
check "ghostty config still copied" test -f "$OUT/config/ghostty/config"
# Kitty still default, Foot not default anywhere in the installer.
check "default-terminal getter has kitty arm" grep -q 'kitty.desktop) echo "kitty"' "$BIN/hexciri-default-terminal"
check "default-terminal getter has foot arm (choice, not default)" grep -q 'foot.desktop) echo "foot"' "$BIN/hexciri-default-terminal"
check "dock pins still Strata/Spotify/Brave/Zed/Kitty" grep -q 'Strata, Spotify, Brave Origin, Zed, Kitty' "$PATCHED"
# Foot out of the trim list, or the next update uninstalls it again.
check "trim step title has no foot" bash -c "! grep -q 'Trimming bloat: foot,' \"$PATCHED\""
check "trim loop has no foot" bash -c "! grep -q 'for _pkg in foot ' \"$PATCHED\""
check "trim info line has no foot" bash -c "! grep -q '(foot/btop/' \"$PATCHED\""
check "patched file still trims btop" grep -q 'for _pkg in btop ' "$PATCHED"
# Learn fix (2cdc33c7) survived the rebase, not clobbered.
check "learn.zed present" grep -q '"learn.zed"' "$MENU"
check "learn.fish present" grep -q '"learn.fish"' "$MENU"
check "learn.kitty present" grep -q '"learn.kitty"' "$MENU"
check "learn.quickshell present" grep -q '"learn.quickshell"' "$MENU"
check "learn.neovim absent" bash -c "! grep -q '\"learn.neovim\"' \"$MENU\""
check "learn.community absent" bash -c "! grep -q '\"learn.community\"' \"$MENU\""
check "tmux config copied (Learn fix)" test -f "$OUT/config/tmux/tmux.conf"
# Hard defaults: no folio/nautilus/herdr in restored rows or bins.
check "menu has no folio reference" bash -c "! grep -q folio \"$MENU\""
check "menu has no herdr reference" bash -c "! grep -q herdr \"$MENU\""
for b in hexciri-install-ai-chatgpt hexciri-install-ai-claude hexciri-install-ai-hermes hexciri-install-ai-openclaw hexciri-install-ai-t3-code hexciri-remove-ai-hermes hexciri-remove-ai-openclaw hexciri-remove-ai-t3-code hexciri-install-hermes-cli hexciri-install-openclaw-cli hexciri-install-t3code-app hexciri-launch-openclaw hexciri-openclaw-onboard hexciri-install-terminal; do
  check "bin has no folio call: $b" bash -c "! grep -qE '(^|[^a-z-])folio([^a-z-]|$)' \"$BIN/$b\""
  check "bin has no herdr call: $b" bash -c "! grep -qi herdr \"$BIN/$b\""
done
# Every kept install/remove row's action resolves (same invariant as
# placement verification, run here against the sim fork output).
python3 - "$MENU" "$BIN" <<'PYEOF' >/tmp/sim24-deadrows.log 2>&1 || { echo "FAIL: dead install/remove row (see /tmp/sim24-deadrows.log)"; cat /tmp/sim24-deadrows.log; fail=$((fail+1)); }
import os, re, sys
menu, bin_dir = sys.argv[1], sys.argv[2]
have = set(os.listdir(bin_dir))
dead = []
for line in open(menu):
    m = re.match(r'\s*"((?:install|remove)(?:\.[^"]+)?)"\s*:', line)
    if not m:
        continue
    a = re.search(r'"action"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
    if not a:
        continue
    toks = re.findall(r'hexciri-[a-z0-9-]+', a.group(1))
    missing = [t for t in toks if t not in have]
    if missing:
        dead.append("%s calls missing %s" % (m.group(1), ",".join(missing)))
if dead:
    print("\n".join(dead)); sys.exit(1)
print("all install/remove actions resolve")
PYEOF
if [ -s /tmp/sim24-deadrows.log ] && grep -q 'all install/remove actions resolve' /tmp/sim24-deadrows.log; then pass=$((pass+1)); echo "ok: all install/remove actions resolve to installed bins"; fi
# Pre-existing rows still there (no clobber of the 74fe03b3 restore).
check "browser row still there" grep -q '"install.browser.chrome"' "$MENU"
check "tailscale unit ExecStart still fixed" grep -q 'ExecStart=/usr/share/hexciri/bin/hexciri-tailscale-receive' "$OUT/default/systemd/user/hexciri-tailscale-receive.service"
check "pre-existing install.package still there" grep -q '"install.package"' "$MENU"
# Idempotency: run the fork pipeline a second time, same result.
bash /tmp/ai-foot-sim7.sh >/tmp/sim24-sim7b.log 2>&1 || { echo "sim7 2nd run FAILED"; exit 1; }
check "2nd fork run: install.ai.claude still there" grep -q '"install.ai.claude"' "$MENU"
check "2nd fork run: install.terminal.foot still there" grep -q '"install.terminal.foot"' "$MENU"
check "2nd fork run: foot config still copied" test -f "$OUT/config/foot/foot.ini"
echo "sim24: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
# Regression: same checks against the unpatched live file must fail
# (AI rows + Foot row absent there). Runs last: it overwrites sim7out.
mkdir -p /tmp/ai-foot-live-unpatched
cp /tmp/ai-foot-live2/install.sh /tmp/ai-foot-live-unpatched/install.sh
sed 's|INSTALLER_DIR="$HOME/workspace/hexiri-2.0/v2"|INSTALLER_DIR="/tmp/ai-foot-live-unpatched"|; s|"$HOME/workspace/hexiri-2.0/v2/install.sh"|"/tmp/ai-foot-live-unpatched/install.sh"|g' \
  "$ROOT/simwork/sim7.sh" > /tmp/ai-foot-sim7-unpatched.sh
bash /tmp/ai-foot-sim7-unpatched.sh >/tmp/sim24-sim7-unpatched.log 2>&1 || { echo "sim7 unpatched FAILED"; tail -30 /tmp/sim24-sim7-unpatched.log; exit 1; }
if grep -q '"install.ai.claude"' "$MENU" || grep -q '"install.terminal.foot"' "$MENU"; then
  echo "FAIL: regression: unpatched file already has AI/Foot rows"; exit 1
fi
echo "ok: regression: unpatched live file has no AI/Foot rows"
echo "sim24: $pass passed, $fail failed (regression ok)"
