#!/usr/bin/env bash
# sim33: Foot desktop file only, package not installed (Devi 2026-11-24
# 20:26/20:27 MST, desktop dokoz). `pacman -Q | grep foot` came back
# blank, yet a Foot entry showed in the app grid on top of Kitty.
# Root cause: the desktop-entry placement loop placed EVERY
# FORK_OUT/applications/*.desktop into ~/.local/share/applications/,
# including foot.desktop, whose only job is to be install-terminal
# foot's source (it copies it there itself when it installs foot).
# Fix: skip foot.desktop in the loop unless foot is installed, repair
# (remove) a stray Hexciri-placed copy when foot is absent, and never
# NoDisplay a real installed Foot entry.
# Extracts the placement block verbatim from a given install.sh and
# runs it in a fake HOME / fake FORK_OUT, 6 scenarios + negative control.
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
BASE=/tmp/foot-desktop-fix
OLD="$BASE/install-old.sh"
NEW="$HOME/workspace/hexiri-2.0/v2/install.sh"
mkdir -p "$BASE"
cp /tmp/foot2/install-old.sh "$OLD"

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

run_place() { # $1=install.sh $2=foot-installed(0/1) $3=prestray(none|plain|custom)
  local file="$1" foot="$2" stray="$3"
  local fake="$BASE/fake" fork="$BASE/fork" block="$BASE/place-block.sh" puf="$BASE/puf.sh" repair="$BASE/repair-block.sh"
  rm -rf "$fake" "$fork" "$BASE/fakebin"; mkdir -p "$fake/.local/share/applications" "$fork/applications" "$BASE/fakebin"
  printf '%s' "$FOOT_DESK" > "$fork/applications/foot.desktop"
  printf '%s' "$WRAP_DESK" > "$fork/applications/hexciri-terminal.desktop"
  printf '%s' "$WRAP_DESK" > "$fork/applications/hexciri-browser.desktop"
  if [ "$stray" = "plain" ]; then
    printf '%s' "$FOOT_DESK" > "$fake/.local/share/applications/foot.desktop"
  elif [ "$stray" = "custom" ]; then
    printf '[Desktop Entry]\nType=Application\nExec=foot --config=/home/devi/.config/foot/foot.ini\nName=Foot\n' > "$fake/.local/share/applications/foot.desktop"
  fi
  if [ "$foot" = "1" ]; then
    printf '#!/bin/bash\nexit 0\n' > "$BASE/fakebin/foot"; chmod +x "$BASE/fakebin/foot"
  fi
  local start end
  start=$(grep -n '^# Browser + terminal desktop entries:' "$file" | cut -d: -f1)
  end=$(grep -n '^# hexciri CLI on PATH everywhere' "$file" | cut -d: -f1); end=$((end-1))
  sed -n "${start},${end}p" "$file" > "$block"
  # repair block (trim section) if present in this install.sh
  : > "$repair"
  if grep -q '^# Stray Foot entry repair' "$file"; then
    local rs re
    rs=$(grep -n '^# Stray Foot entry repair' "$file" | cut -d: -f1)
    re=$(awk -v s="$rs" 'NR>=s && /^fi$/ {print NR; exit}' "$file")
    sed -n "${rs},${re}p" "$file" > "$repair"
  fi
  # place_user_file verbatim from the same install.sh
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

# --- 0. preconditions ---
bash -n "$NEW" && ok "bash -n patched install.sh" || bad "bash -n patched install.sh"
grep -q 'Skipped desktop entry: foot.desktop' "$NEW" && ok "foot skip present" || bad "foot skip missing"
grep -q 'Removed stray desktop entry: foot.desktop' "$NEW" && ok "stray repair present" || bad "stray repair missing"
grep -q '!= "foot.desktop" ] && ! grep -q' "$NEW" && ok "NoDisplay is wrappers-only" || bad "NoDisplay still applies to foot"

# --- 1. negative control: unpatched, foot NOT installed, stray present ---
if run_place "$OLD" 0 plain; then
  [ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && ok "unpatched places foot.desktop with no foot installed (bug reproduced)" || bad "unpatched did not place foot.desktop"
else bad "unpatched placement run failed"; fi

# --- 2. patched, foot NOT installed, stray present (Devi exact scenario) ---
if run_place "$NEW" 0 plain; then ok "patched placement run succeeds, foot absent + stray"; else bad "patched run failed, foot absent + stray"; fi
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && bad "patched still leaves stray foot.desktop" || ok "patched removes stray foot.desktop"
[ -f "$BASE/fake/.local/share/applications/foot.desktop.hexciri.new" ] && bad "patched leaves foot.desktop.hexciri.new" || ok "no foot.desktop.hexciri.new left"
[ -f "$BASE/fake/.local/share/applications/hexciri-terminal.desktop" ] && ok "patched still places hexciri-terminal wrapper" || bad "patched lost terminal wrapper"
[ -f "$BASE/fake/.local/share/applications/hexciri-browser.desktop" ] && ok "patched still places hexciri-browser wrapper" || bad "patched lost browser wrapper"
grep -q '^NoDisplay=true' "$BASE/fake/.local/share/applications/hexciri-terminal.desktop" && ok "wrapper still gets NoDisplay" || bad "wrapper lost NoDisplay"
grep -q 'Removed stray desktop entry' "$BASE/place-run.log" && ok "patched logs the stray removal" || bad "patched did not log stray removal"

# --- 3. patched, foot NOT installed, no stray: never placed ---
run_place "$NEW" 0 none || bad "patched run failed, foot absent + no stray"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && bad "patched placed foot.desktop with no foot installed" || ok "patched never places foot.desktop when foot is absent"
[ -f "$BASE/fake/.local/share/applications/hexciri-terminal.desktop" ] && ok "wrappers still placed when foot absent" || bad "wrappers lost when foot absent"

# --- 4. patched, foot IS installed: entry placed and VISIBLE ---
run_place "$NEW" 1 none || bad "patched run failed, foot installed"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && ok "foot installed: foot.desktop placed" || bad "foot installed: foot.desktop missing"
grep -q '^NoDisplay=' "$BASE/fake/.local/share/applications/foot.desktop" && bad "foot installed: entry hidden by NoDisplay" || ok "foot installed: entry stays visible (no NoDisplay)"

# --- 5. patched, foot NOT installed, user-customised entry: not removed ---
run_place "$NEW" 0 custom || bad "patched run failed, custom entry"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && ok "custom foot.desktop left alone (guard works)" || bad "patched deleted a user-customised entry"

# --- 6. idempotence: run patched twice, foot absent + stray ---
run_place "$NEW" 0 plain || bad "first patched run failed (idempotence)"
run_place "$NEW" 0 plain || bad "second patched run failed (idempotence)"
[ -f "$BASE/fake/.local/share/applications/foot.desktop" ] && bad "second run re-placed foot.desktop" || ok "second run still leaves no foot.desktop"
c=$(grep -c '^NoDisplay=true' "$BASE/fake/.local/share/applications/hexciri-terminal.desktop")
[ "$c" = "1" ] && ok "NoDisplay appended exactly once across runs" || bad "NoDisplay duplicated ($c times)"

# --- 7. fingerprints, same checkout path ---
mkdir -p "$BASE/fp-same"
cp "$OLD" "$BASE/fp-same/install.sh"; (cd "$BASE/fp-same" && bash install.sh --print-fingerprints 2>/dev/null) > "$BASE/fp-old.txt"
cp "$NEW" "$BASE/fp-same/install.sh"; (cd "$BASE/fp-same" && bash install.sh --print-fingerprints 2>/dev/null) > "$BASE/fp-new.txt"
for k in upstream patch system; do
  grep "^$k=" "$BASE/fp-old.txt" | cut -d= -f2 > "$BASE/a.txt"; grep "^$k=" "$BASE/fp-new.txt" | cut -d= -f2 > "$BASE/b.txt"
  cmp -s "$BASE/a.txt" "$BASE/b.txt" && ok "$k fingerprint stable" || bad "$k fingerprint moved"
done
grep "^provision=" "$BASE/fp-old.txt" | cut -d= -f2 > "$BASE/a.txt"; grep "^provision=" "$BASE/fp-new.txt" | cut -d= -f2 > "$BASE/b.txt"
cmp -s "$BASE/a.txt" "$BASE/b.txt" && bad "provision fingerprint did not move (repair would never run)" || ok "provision fingerprint moves only (next update is re-apply-provision)"

echo "sim33: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
