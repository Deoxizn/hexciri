#!/bin/bash
# sim23: full Install/Remove restore (2026-11-24, Devi: full menu back).
# Runs the sim7 fork pipeline verbatim against the patched install.sh in
# /tmp/menu-live (live nyx HEAD 748c59a + menu-full-restore patch), NOT the
# shared ~/workspace/hexiri-2.0/v2/install.sh, which a sibling agent
# (minimal-update) is concurrently editing from 91299f9.
# Checks: every restored row present, every dropped row absent, every
# restored row's action bins exist, no folio/nautilus in restored rows or
# bins, data files present, tailscale unit fixed, idempotent 2nd run.
# Regression: the same checks against the unpatched live file must fail
# (restored rows absent there).
set -u
ROOT="$HOME/workspace/hexiri-2.0"
MENU="$ROOT/simwork/sim7out/default/hexciri/hexciri-menu.jsonc"
BIN="$ROOT/simwork/sim7out/bin"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok: $n"; else fail=$((fail+1)); echo "FAIL: $n"; fi; }

bash -n /tmp/menu-live/install.sh || { echo "bash -n install.sh FAILED"; exit 1; }
echo "bash -n clean"
sed 's|INSTALLER_DIR="$HOME/workspace/hexiri-2.0/v2"|INSTALLER_DIR="/tmp/menu-live"|; s|"$HOME/workspace/hexiri-2.0/v2/install.sh"|"/tmp/menu-live/install.sh"|g' \
  "$ROOT/simwork/sim7.sh" > /tmp/menu-sim7.sh
bash /tmp/menu-sim7.sh >/tmp/sim23-sim7.log 2>&1 || { echo "sim7 FAILED"; tail -30 /tmp/sim23-sim7.log; exit 1; }
echo "sim7 fork pipeline done"

# Restored Install rows (headers + leaves).
for k in install.browser install.browser.chromium install.browser.chrome install.browser.edge install.browser.brave install.browser.brave-origin install.browser.firefox install.browser.zen install.terminal install.terminal.alacritty install.terminal.ghostty install.terminal.kitty install.editor.vscode install.editor.cursor install.editor.sublime install.editor.helix install.editor.vim install.service install.service.1password install.service.bitwarden install.service.dropbox install.service.dingtalk install.service.microsoft install.service.nordvpn install.service.notion install.service.once install.service.signal install.service.slack install.service.tailscale install.service.wechat install.development install.development.rails install.development.go install.development.php install.development.python install.development.elixir install.development.zig install.development.rust install.development.java install.development.dotnet install.development.ocaml install.development.clojure install.development.scala install.development.javascript install.development.javascript.node install.development.javascript.bun install.development.javascript.deno install.development.php.php install.development.php.laravel install.development.php.symfony install.development.elixir.elixir install.development.elixir.phoenix install.gaming.vibes install.gaming.xbox-cloud install.gaming.xbox-controllers install.gaming.retro-launcher; do
  check "install row present: $k" grep -q "\"$k\"" "$MENU"
done
# Restored Remove rows.
for k in remove.service remove.service.1password remove.service.dropbox remove.service.tailscale remove.service.microsoft remove.service.ssh-agent remove.development remove.development.rails remove.development.go remove.development.php remove.development.python remove.development.elixir remove.development.zig remove.development.rust remove.development.java remove.development.dotnet remove.development.ocaml remove.development.clojure remove.development.scala remove.development.javascript remove.development.javascript.node remove.development.javascript.bun remove.development.javascript.deno remove.development.php.php remove.development.php.laravel remove.development.php.symfony remove.development.elixir.elixir remove.development.elixir.phoenix remove.dictation remove.dictation.hex remove.dictation.superwhisper remove.dictation.voxtype remove.security.fido2 remove.security.sshd remove.gaming.battlenet remove.gaming.heroic remove.gaming.lutris remove.gaming.moonlight remove.gaming.xbox-cloud remove.gaming.xbox-controllers remove.gaming.vibes; do
  check "remove row present: $k" grep -q "\"$k\"" "$MENU"
done
# Dropped rows stay gone.
for k in install.ai install.ai.claude install.ai.herdr install.windows install.preinstalls install.terminal.foot install.editor.emacs install.development.docker-dbs remove.ai remove.ai.claude remove.windows remove.preinstalls remove.factory-reset remove.security.sudoless-docker; do
  check "dropped row absent: $k" bash -c "! grep -q '\"$k\"' \"$MENU\""
done
# Restored bins exist.
for b in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-remove-service-1password hexciri-remove-service-dropbox hexciri-remove-service-microsoft hexciri-remove-service-ssh-agent hexciri-remove-service-tailscale hexciri-remove-security-fido2 hexciri-remove-security-sshd hexciri-install-dictation-hex hexciri-install-dictation-superwhisper hexciri-install-dictation-voxtype hexciri-remove-dictation-hex hexciri-remove-dictation-superwhisper hexciri-remove-dictation-voxtype hexciri-install-gaming-xbox-cloud hexciri-install-gaming-xbox-controllers hexciri-remove-gaming-battlenet hexciri-remove-gaming-heroic hexciri-remove-gaming-lutris hexciri-remove-gaming-moonlight hexciri-remove-gaming-xbox-cloud hexciri-remove-gaming-xbox-controllers hexciri-games-retro-install hexciri-games-retro-cores hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-vibes-launch hexciri-games-vibes-copy hexciri-install-chromium-copy-url hexciri-install-chromium-ytdlp hexciri-install-video-decode hexciri-install-camera hexciri-pkg-aur-add hexciri-chromium-add-feature hexciri-chromium-copy-url-host hexciri-chromium-ytdlp-host hexciri-tailscale-receive hexciri-tailscale-send; do
  check "bin present: $b" test -x "$BIN/$b"
done
# Data files the restored bins read.
OUT="$ROOT/simwork/sim7out"
check "chromium-flags.conf copied" test -f "$OUT/config/chromium-flags.conf"
check "chromium extensions copied" test -f "$OUT/default/chromium/extensions/copy-url/manifest.json"
check "chromium native-messaging copy-url template copied" test -f "$OUT/default/chromium/native-messaging-hosts/com.hexciri.copy_url.json"
check "chromium native-messaging ytdlp template copied" test -f "$OUT/default/chromium/native-messaging-hosts/com.hexciri.ytdlp.json"
check "alacritty config copied" test -f "$OUT/config/alacritty/alacritty.toml"
check "ghostty config copied" test -f "$OUT/config/ghostty/config"
check "Alacritty desktop entry copied" test -f "$OUT/default/alacritty/Alacritty.desktop"
check "voxtype config copied" test -f "$OUT/default/voxtype/config.toml"
check "tailscale unit copied" test -f "$OUT/default/systemd/user/hexciri-tailscale-receive.service"
check "tailscale unit ExecStart fixed" grep -q 'ExecStart=/usr/share/hexciri/bin/hexciri-tailscale-receive' "$OUT/default/systemd/user/hexciri-tailscale-receive.service"
check "install-service-tailscale installs unit" grep -q 'default/systemd/user/hexciri-tailscale-receive.service' "$BIN/hexciri-install-service-tailscale"
check "remove-service-tailscale removes unit" grep -q 'rm -f ~/.config/systemd/user/hexciri-tailscale-receive.service' "$BIN/hexciri-remove-service-tailscale"
# Hard defaults: no folio/nautilus in restored rows or bins.
check "menu has no folio reference" bash -c "! grep -q folio \"$MENU\""
check "menu has no nautilus reference" bash -c "! grep -q nautilus \"$MENU\""
for b in hexciri-install-browser hexciri-install-terminal hexciri-install-editor-vscode hexciri-install-editor-helix hexciri-install-dev-env hexciri-remove-dev-env hexciri-install-service-1password hexciri-install-service-dropbox hexciri-install-service-microsoft hexciri-install-service-nordvpn hexciri-install-service-once hexciri-install-service-signal hexciri-install-service-tailscale hexciri-games-vibes-install hexciri-games-vibes-remove hexciri-games-retro-install; do
  check "bin has no folio call: $b" bash -c "! grep -qE '(^|[^a-z-])folio([^a-z-]|$)' \"$BIN/$b\""
done
# Every kept install/remove row's action resolves (same invariant as
# placement verification, run here against the sim fork output).
python3 - "$MENU" "$BIN" <<'PYEOF' >/tmp/sim23-deadrows.log 2>&1 || { echo "FAIL: dead install/remove row (see /tmp/sim23-deadrows.log)"; cat /tmp/sim23-deadrows.log; fail=$((fail+1)); }
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
if [ -s /tmp/sim23-deadrows.log ] && grep -q 'all install/remove actions resolve' /tmp/sim23-deadrows.log; then pass=$((pass+1)); echo "ok: all install/remove actions resolve to installed bins"; fi
# Pre-existing rows still there (no clobber of the bg fix or the lean restore).
check "bg row still calls theme-bg-install" grep -q '"install.style.background".*hexciri-theme-bg-install' "$MENU"
check "theme-bg-install still uses launch-files" grep -q 'hexciri-launch-files "$THEME_USER_BACKGROUNDS"' "$BIN/hexciri-theme-bg-install"
check "launch-files still forwards args" grep -q 'strata "$@"' "$BIN/hexciri-launch-files"
check "pre-existing install.package still there" grep -q '"install.package"' "$MENU"
check "pre-existing remove.package still there" grep -q '"remove.package"' "$MENU"
# Idempotency: run the fork pipeline a second time, same result.
bash /tmp/menu-sim7.sh >/tmp/sim23-sim7b.log 2>&1 || { echo "sim7 2nd run FAILED"; exit 1; }
check "2nd fork run: browser row still there" grep -q '"install.browser.chrome"' "$MENU"
check "2nd fork run: tailscale unit ExecStart still fixed" grep -q 'ExecStart=/usr/share/hexciri/bin/hexciri-tailscale-receive' "$OUT/default/systemd/user/hexciri-tailscale-receive.service"
echo "sim23: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
