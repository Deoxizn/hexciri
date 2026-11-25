#!/usr/bin/env bash
# sim36: foot.desktop stray entry, round 2 (Devi 2026-11-24 21:21 MST, dokoz).
# f3c6b59c fixed this, a1e97b06 (SDDM) rebased on a stale pre-f3 base and
# silently reverted both the loop skip and the trim repair; live b56c769a
# has neither. This sim proves: unpatched re-places foot + never repairs;
# patched never places it when foot absent, removes a plain stray (with
# or without NoDisplay appended), leaves a custom entry alone, and
# places it visible when foot IS installed. Also proves the loop-side
# repair (re-apply mode) and the trim-side repair (provision mode) both
# remove the stray independently.
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
BASE=/tmp/foot-desktop-fix2
OLD=/tmp/footfix/install.sh
NEW=/tmp/footfix/work/v2/install.sh
mkdir -p "$BASE"
FOOT_DESK='[Desktop Entry]
Type=Application
TryExec=foot
Exec=foot
Icon=foot
Terminal=false
Categories=System;TerminalEmulator;
Name=Foot
GenericName=Terminal
Comment=A fast, lightweight and minimalistic Wayland terminal emulator
StartupNotify=true
StartupWMClass=foot
'
WRAP_DESK='[Desktop Entry]
Type=Application
Exec=hexciri-launch-terminal
Icon=kitty
Name=Terminal
'
run_case() { # $1=install.sh $2=foot(0/1) $3=stray(none|plain|plain-nodisplay|custom) $4=repair(loop|trim|both)
  local file="$1" foot="$2" stray="$3" mode="$4"
  local fake="$BASE/fake" fork="$BASE/fork" block="$BASE/place-block.sh" puf="$BASE/puf.sh" repair="$BASE/repair-block.sh"
  rm -rf "$fake" "$fork" "$BASE/fakebin"; mkdir -p "$fake/.local/share/applications" "$fork/applications" "$BASE/fakebin"
  printf '%s' "$FOOT_DESK" > "$fork/applications/foot.desktop"
  printf '%s' "$WRAP_DESK" > "$fork/applications/hexciri-terminal.desktop"
  printf '%s' "$WRAP_DESK" > "$fork/applications/hexciri-browser.desktop"
  case "$stray" in
    plain) printf '%s' "$FOOT_DESK" > "$fake/.local/share/applications/foot.desktop" ;;
    plain-nodisplay) printf '%sNoDisplay=true\n' "$FOOT_DESK" > "$fake/.local/share/applications/foot.desktop" ;;
    custom) printf '[Desktop Entry]\nType=Application\nExec=foot --config=/home/devi/.config/foot/foot.ini\nName=Foot\n' > "$fake/.local/share/applications/foot.desktop" ;;
  esac
  if [ "$foot" = "1" ]; then printf '#!/bin/bash\nexit 0\n' > "$BASE/fakebin/foot"; chmod +x "$BASE/fakebin/foot"; fi
  local start end
  start=$(grep -n '^# Browser + terminal desktop entries:' "$file" | cut -d: -f1)
  end=$(grep -n '^# hexciri CLI on PATH everywhere' "$file" | cut -d: -f1); end=$((end-1))
  sed -n "${start},${end}p" "$file" > "$block"
  : > "$repair"
  if [ "$mode" = "loop" ] || [ "$mode" = "both" ]; then
    local rs re
    rs=$(grep -n '^# Stray Foot entry repair, loop side' "$file" | cut -d: -f1)
    if [ -n "$rs" ]; then re=$(awk -v s="$rs" 'NR>=s && /^fi$/ {print NR; exit}' "$file"); sed -n "${rs},${re}p" "$file" >> "$repair"; fi
  fi
  if [ "$mode" = "trim" ] || [ "$mode" = "both" ]; then
    local rs re
    rs=$(grep -n '^# Stray Foot entry repair (2026-11-24, Devi: only' "$file" | cut -d: -f1)
    if [ -n "$rs" ]; then re=$(awk -v s="$rs" 'NR>=s && /^fi$/ {print NR; exit}' "$file"); sed -n "${rs},${re}p" "$file" >> "$repair"; fi
  fi
  local ps pe
  ps=$(grep -n '^place_user_file() {' "$file" | cut -d: -f1)
  pe=$(awk -v s="$ps" 'NR>=s && /^}$/ {print NR; exit}' "$file")
  sed -n "${ps},${pe}p" "$file" > "$puf"
  : > "$BASE/place-run.log"
  export PLACE_LOG="$BASE/place-run.log" PUF="$puf" BLOCK="$block" REPAIR="$repair"
  HOME="$fake" FORK_OUT="$fork" IS_RERUN=0 PATH="$BASE/fakebin:$PATH" bash -c '
    set -eu
    info() { printf "INFO: %s\n" "$1" >> "$PLACE_LOG"; }
    warn() { printf "WARN: %s\n" "$1" >> "$PLACE_LOG"; }
    die()  { printf "ERROR: %s\n" "$1" >> "$PLACE_LOG"; exit 1; }
    source "$PUF"
    source "$BLOCK"
    if [ -s "$REPAIR" ]; then source "$REPAIR"; fi
  '
  return $?
}

bash -n "$NEW" && ok "bash -n patched install.sh" || bad "bash -n patched install.sh"
grep -q 'Skipped desktop entry: foot.desktop' "$NEW" && ok "foot skip present" || bad "foot skip missing"
grep -q 'Removed stray desktop entry: foot.desktop' "$NEW" && ok "stray repair present (x2 sites)" || bad "stray repair missing"
[ "$(grep -c 'Removed stray desktop entry: foot.desktop' "$NEW")" = "2" ] && ok "two repair sites present" || bad "expected 2 repair sites"
grep -q 'Stray Foot entry repair, loop side' "$NEW" && ok "loop-side repair present" || bad "loop-side repair missing"
grep -q 'foot entry: ~/.local/share/applications/foot.desktop exists' "$NEW" && ok "health warn present" || bad "health warn missing"
! grep -q 'Plus foot.desktop (2026-11-24)' "$NEW" && ok "reverted loop text gone" || bad "reverted loop text still present"

# 1. negative control: unpatched, foot absent, plain stray
if run_case "$OLD" 0 plain both; then [ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && ok "unpatched re-places foot.desktop, stray remains (bug reproduced)" || bad "unpatched did not leave foot.desktop"; else bad "unpatched run failed"; fi

# 2. patched, loop repair only, foot absent, plain stray (Devi exact)
run_case "$NEW" 0 plain loop || bad "patched loop run failed"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && bad "loop repair left stray foot.desktop" || ok "loop repair removes plain stray"
grep -q 'Removed stray desktop entry' "$BASE/place-run.log" && ok "loop repair logs removal" || bad "loop repair did not log"
[ -f "$BASE/fake/.local/share/applications/hexciri-terminal.desktop" ] && ok "wrappers still placed" || bad "wrappers lost"
grep -q '^NoDisplay=true' "$BASE/fake/.local/share/applications/hexciri-terminal.desktop" && ok "wrapper still gets NoDisplay" || bad "wrapper lost NoDisplay"

# 3. patched, trim repair only, foot absent, plain+NoDisplay stray (Devi's actual file: installer appended NoDisplay)
run_case "$NEW" 0 plain-nodisplay trim || bad "patched trim run failed"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && bad "trim repair left NoDisplay stray" || ok "trim repair removes NoDisplay stray"
grep -q 'Removed stray desktop entry' "$BASE/place-run.log" && ok "trim repair logs removal" || bad "trim repair did not log"

# 4. patched, foot absent, no stray: never placed
run_case "$NEW" 0 none both || bad "patched no-stray run failed"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && bad "patched placed foot with no foot installed" || ok "never placed when foot absent"
grep -q 'Skipped desktop entry: foot.desktop' "$BASE/place-run.log" && ok "skip logged" || bad "skip not logged"

# 5. patched, foot installed: placed visible, no NoDisplay
run_case "$NEW" 1 none both || bad "patched foot-installed run failed"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && ok "placed when foot installed" || bad "not placed when foot installed"
! grep -q '^NoDisplay=' "$BASE/fake/.local/share/applications/foot.desktop" && ok "installed Foot stays visible (no NoDisplay)" || bad "installed Foot got NoDisplay"

# 6. patched, foot absent, custom stray: left alone
run_case "$NEW" 0 custom both || bad "patched custom run failed"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && ok "custom entry left alone" || bad "custom entry removed"

# 7. regression: f3c6b59c content is back in the patched file (diff of the two blocks vs that commit's patch is exact)
grep -q 'foot.desktop is deliberately NOT placed here' "$NEW" && ok "f3 loop comment back" || bad "f3 loop comment missing"
grep -q 'This lives in the trim' "$NEW" && ok "f3 trim comment back" || bad "f3 trim comment missing"

printf 'sim36: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ]
