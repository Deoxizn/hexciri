#!/usr/bin/env bash
# sim13: Hexciri Settings as a shell plugin (pizza.dirty.settings).
# 1. sim7 fork pipeline vs pristine upstream 94a8c3c: Share only on
#    SUPER+CTRL+SHIFT+S, Settings bind runs hexciri-launch-settings,
#    launcher bin +x in fork, menu row action is the launcher, luac clean.
# 2. Fork checks: manifest id pizza.dirty.settings, no Quattro label,
#    Devi icon byte-identical, PKGBUILD renamed, store.cpp .toUtf8(),
#    generated-Lua toggle identifiers use underscores, luac clean.
# 3. Fake-HOME plugin install as user nobody, running the installer's
#    Settings-step block VERBATIM (extracted from v2/install.sh):
#    A. plugin add succeeds (shell running): clone + enable + build.
#    B. plugin add fails (no shell, tty3): git-clone fallback + validate.
#    C. re-run with plugin installed: plugin update branch, build is a
#       no-op ("already up to date"), binary still present.
set -u
ROOT="$HOME/workspace/hexiri-2.0"
FORK="$ROOT/hexciri-settings-fork"
FAIL=0
say() { printf '[sim13] %s\n' "$*"; }
check() { if eval "$2"; then say "PASS: $1"; else say "FAIL: $1"; FAIL=1; fi; }

# --- 1. sim7 ---
bash "$ROOT/simwork/sim7.sh" > /tmp/sim13-sim7.log 2>&1
check "sim7 exit 0" "[ -f $ROOT/simwork/sim7out/default/hypr/bindings/hexciri.lua ]"
grep -q 'o.bind("SUPER + CTRL + SHIFT + S", "Share", { menu = "share" })' "$ROOT/simwork/sim7out/default/hypr/bindings/utilities.lua" \
  && ! grep -q 'o.bind("SUPER + CTRL + S", "Share"' "$ROOT/simwork/sim7out/default/hypr/bindings/utilities.lua"
check "Share only on SUPER+CTRL+SHIFT+S" "[ $? -eq 0 ]"
grep -q 'o.bind("SUPER + CTRL + S", "Hexciri Settings", "hexciri-launch-settings")' "$ROOT/simwork/sim7out/default/hypr/bindings/hexciri.lua"
check "Settings bind runs hexciri-launch-settings" "[ $? -eq 0 ]"
check "launcher bin in fork, +x" "[ -x $ROOT/simwork/sim7out/bin/hexciri-launch-settings ]"
! grep -q '"settings".*hexciri-launch-settings' "$ROOT/simwork/sim7out/default/hexciri/hexciri-menu.jsonc" 2>/dev/null
check "menu has NO top-level Settings row (removed 2026-11-24, Super+Ctrl+S / launcher only)" "[ $? -eq 0 ]"
luac -p "$ROOT/simwork/sim7out/default/hypr/bindings/hexciri.lua" "$ROOT/simwork/sim7out/default/hypr/bindings/utilities.lua" 2>/dev/null
check "luac clean on bind files" "[ $? -eq 0 ]"

# --- 2. fork checks ---
check "manifest id is pizza.dirty.settings" "grep -q '\"id\": \"pizza.dirty.settings\"' $FORK/manifest.json"
check "manifest kinds service" "grep -q '\"service\"' $FORK/manifest.json && grep -q 'plugin/Service.qml' $FORK/manifest.json"
! grep -rni "quattro" "$FORK/README.md" "$FORK/README-HEXCIRI.md" "$FORK/plugin" >/dev/null 2>&1
check "no Quattro label in fork" "[ $? -eq 0 ]"
check "Devi icon byte-identical in fork" "cmp -s $HOME/workspace/user/files/serversettings_108555.svg $FORK/pkgbuild/hexciri-settings.svg"
check "PKGBUILD renamed" "grep -q 'pkgname=hexciri-settings' $FORK/pkgbuild/PKGBUILD && ! grep -q omasettings $FORK/pkgbuild/PKGBUILD"
check "store.cpp:1042 has .toUtf8()" "grep -q 'fromJson(readFile(info.absoluteFilePath()).toUtf8())' $FORK/src/store.cpp"
! grep -rn "hexciri-settings_toggle\|hexciri-settings_ok\|hexciri-settings_paths" "$FORK/src/" >/dev/null 2>&1
check "no hyphenated Lua identifiers in src" "[ $? -eq 0 ]"
grep -q "hexciri_settings_toggle" "$FORK/src/hyprconf.cpp"
check "Lua toggle identifiers use underscores" "[ $? -eq 0 ]"
check "installer step uses pizza.dirty.settings" "grep -q 'SETTINGS_PLUGIN_ID=\"pizza.dirty.settings\"' $ROOT/v2/install.sh"
check "installer has no vendored-tree fingerprint" "! grep -q 'v2/hexciri-settings\" -type f' $ROOT/v2/install.sh"
check "installer quattro comment fixed" "! grep -q 'hexciri-upgrade-to-quattro runs' $ROOT/v2/install.sh"
bash -n "$ROOT/v2/install.sh"
check "bash -n install.sh" "[ $? -eq 0 ]"

# --- 3. fake-HOME plugin install ---
T=/tmp/sim13-home
rm -rf "$T" && mkdir -p "$T/home" "$T/stubs" "$T/remote"
# temp git remote from the fork workdir (modes preserved, like a real clone)
cp -a "$FORK/." "$T/remote/"
( cd "$T/remote" && git init -q . && git add -A && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git commit -qm "fork" )
chmod -R a+rX "$T/remote"
# stubs: qmake6/make/pacman (reuse sim12 shapes), real jq + git from /usr/bin
cat > "$T/stubs/qmake6" <<'EOF'
#!/bin/sh
printf 'all:\n\tcp fake-src hexciri-settings\n' > Makefile
echo '#!/bin/sh' > fake-src
echo 'echo hexciri-settings-stub "$@"' >> fake-src
chmod +x fake-src
EOF
cat > "$T/stubs/make" <<'EOF'
#!/bin/sh
cp fake-src hexciri-settings
chmod +x hexciri-settings
EOF
cat > "$T/stubs/pacman" <<'EOF'
#!/bin/sh
if [ "$1" = "-T" ]; then exit 0; fi
exit 1
EOF
cat > "$T/stubs/hexciri" <<'EOF'
#!/bin/sh
# stub dispatcher: plugin add / plugin update only. SIM_NO_SHELL=1 makes
# add fail, exercising the installer's git-clone fallback.
if [ "$1" = "plugin" ] && [ "$2" = "add" ]; then
  [ -n "${SIM_NO_SHELL:-}" ] && { echo "stub: no shell running" >&2; exit 1; }
  url="$3"
  id="pizza.dirty.settings"
  target="$HOME/.config/hexciri/plugins/$id"
  git clone -- "$url" "$target" || exit 1
  hexciri-plugin-validate "$target" || exit 1
  echo enabled > "$target/.sim-enabled"
  echo "Added $id into $target"
  exit 0
fi
if [ "$1" = "plugin" ] && [ "$2" = "update" ]; then
  id="$3"
  git -C "$HOME/.config/hexciri/plugins/$id" pull --ff-only >/dev/null 2>&1
  echo "$id is up to date."
  exit 0
fi
echo "stub hexciri: unknown $*" >&2; exit 1
EOF
cp "$ROOT/simwork/sim7out/bin/hexciri-plugin-validate" "$T/stubs/hexciri-plugin-validate"
chmod +x "$T/stubs/"*
chmod -R a+rX "$T/stubs" "$T/remote"
# extract the installer Settings-step block verbatim
sed -n '/^# --- Hexciri Settings, Hexciri shell plugin/,/^unset SETTINGS_PLUGIN_ID/p' "$ROOT/v2/install.sh" > "$T/step.sh"
# the step's plugin URL must point at our local remote in the sim
sed -i "s|https://github.com/Deoxizn/hexciri-settings.git|file://$T/remote|" "$T/step.sh"
chmod a+r "$T/step.sh"
cat > "$T/defs.sh" <<'EOF'
step() { echo "[step] $*"; }
info() { echo "[info] $*"; }
warn() { echo "[warn] $*"; }
die() { echo "[die] $*" >&2; exit 1; }
EOF
chmod a+r "$T/defs.sh"
chown -R nobody:nogroup "$T"

run_step() {
  local tag="$1"; shift
  runuser -u nobody -- env -i HOME="$T/home" PATH="$T/stubs:/usr/bin:/bin" "$@" bash -c 'set -e; . /tmp/sim13-home/defs.sh; . /tmp/sim13-home/step.sh' > "/tmp/sim13-$tag.log" 2>&1
  echo "$?"
}
P="$T/home/.config/hexciri/plugins/pizza.dirty.settings"

# Scenario A: shell running, plugin add succeeds
rc=$(run_step A)
check "scenario A step exit 0" "[ $rc -eq 0 ]"
check "A: plugin dir + manifest id" "[ -f $P/manifest.json ] && grep -q 'pizza.dirty.settings' $P/manifest.json"
check "A: binary landed" "[ -x $T/home/.local/bin/hexciri-settings ]"
check "A: desktop entry landed" "[ -f $T/home/.local/share/applications/hexciri-settings.desktop ]"
check "A: desktop Icon=hexciri-settings" "grep -q '^Icon=hexciri-settings$' $T/home/.local/share/applications/hexciri-settings.desktop"
check "A: installed icon is Devi's SVG" "cmp -s $HOME/workspace/user/files/serversettings_108555.svg $T/home/.local/share/icons/hicolor/scalable/apps/hexciri-settings.svg"
check "A: plugin install script is +x (git clone preserves mode)" "[ -x $P/plugin/install ]"

# Scenario C: re-run, plugin already installed -> update branch, no rebuild
rc=$(run_step C)
check "scenario C step exit 0" "[ $rc -eq 0 ]"
grep -q "settings plugin updated" "/tmp/sim13-C.log"
check "C: took update branch" "[ $? -eq 0 ]"
grep -q "already up to date" "/tmp/sim13-C.log"
check "C: build is a no-op second run" "[ $? -eq 0 ]"
check "C: binary still present" "[ -x $T/home/.local/bin/hexciri-settings ]"

# Scenario B: fresh home, plugin add fails -> git-clone fallback
rm -rf "$T/home" && mkdir -p "$T/home"
chown -R nobody:nogroup "$T/home"
rc=$(run_step B SIM_NO_SHELL=1)
check "scenario B step exit 0 (fallback)" "[ $rc -eq 0 ]"
check "B: plugin dir cloned by fallback" "[ -f $P/manifest.json ] && grep -q 'pizza.dirty.settings' $P/manifest.json"
check "B: binary landed via fallback" "[ -x $T/home/.local/bin/hexciri-settings ]"
check "B: desktop entry landed via fallback" "[ -f $T/home/.local/share/applications/hexciri-settings.desktop ]"
grep -q "shell not running" "/tmp/sim13-B.log"
check "B: logged the tty3 fallback" "[ $? -eq 0 ]"

say "sim13 done, FAIL=$FAIL"
exit $FAIL
