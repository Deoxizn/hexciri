#!/usr/bin/env bash
# sim32: SDDM password login fails on a no-reader desktop (Devi 2026-11-24
# 20:19 MST, dokoz). Same password works at a tty, SDDM says failed.
# Root cause per installer code: the SDDM step only ADDED pam_fprintd lines
# when a finger was enrolled, and its else branch just logged "left alone".
# Any stray Hexciri fingerprint lines in /etc/pam.d/sddm make SDDM demand
# a touch it can never get on a reader-less machine. Fix: gate on a
# detected reader (hexciri-hw-fingerprint sysfs probe + fprintd-list), and
# REPAIR (strip the lines + theme.conf Fingerprint flag) when no reader.
# Extracts the SDDM fingerprint block verbatim from a given install.sh and
# runs it against a fake root, in 4 scenarios + negative control.
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
BASE=/tmp/sddm-fix
OLD="$BASE/install-old.sh"
NEW="$HOME/workspace/hexiri-2.0/v2/install.sh"

STOCK_SDDM='#%PAM-1.0
auth        include     system-login
account     include     system-login
password    include     system-login
session     include     system-login
'
BROKEN_SDDM='auth      [success=2 new_authtok_reqd=2 default=ignore] pam_unix.so try_first_pass likeauth nullok
auth      [success=1 default=ignore] pam_exec.so quiet /usr/share/hexciri/bin/hexciri-hw-laptop-closed
auth      sufficient pam_fprintd.so
#%PAM-1.0
auth        include     system-login
account     include     system-login
password    include     system-login
session     include     system-login
'

run_sddm() { # $1=install.sh $2=hw (0=reader,1=none) $3=fprintd mode $4=sddm content
  local file="$1" hw="$2" mode="$3" content="$4"
  local fake="$BASE/fake" block="$BASE/sddm-block.sh"
  rm -rf "$fake"; mkdir -p "$fake/etc/pam.d" "$fake/usr/share/sddm/themes/hexciri" "$fake/usr/share/hexciri/bin" "$fake/bin" "$fake/home"
  printf '%s' "$content" > "$fake/etc/pam.d/sddm"
  printf '[General]\nBackground=#0b0f0c\nFingerprint=true\n' > "$fake/usr/share/sddm/themes/hexciri/theme.conf"
  printf '#!/bin/bash\nexit %s\n' "$hw" > "$fake/usr/share/hexciri/bin/hexciri-hw-fingerprint"
  chmod +x "$fake/usr/share/hexciri/bin/hexciri-hw-fingerprint"
  cat > "$fake/bin/fprintd-list" <<EOF
#!/bin/bash
case "$mode" in
  enrolled) printf 'Listing enrolled fingers:\n - #0: right-index-finger\n'; exit 0;;
  present)  printf 'Listing enrolled fingers:\n'; exit 0;;
  *)        printf 'No devices available\n' >&2; exit 1;;
esac
EOF
  chmod +x "$fake/bin/fprintd-list"
  local start end
  start=$(grep -n '^# --- SDDM fingerprint' "$file" | cut -d: -f1)
  end=$(grep -n '^# --- SDDM keyring' "$file" | cut -d: -f1); end=$((end-1))
  sed -n "${start},${end}p" "$file" > "$block"
  # fake root: absolute /etc and /usr/share paths point at $fake
  sed -i "s|/etc/pam.d/sddm|$fake/etc/pam.d/sddm|g; s|/usr/share/sddm/themes/hexciri/theme.conf|$fake/usr/share/sddm/themes/hexciri/theme.conf|g" "$block"
  # installer calls /usr/bin/fprintd-list by absolute path (real on Arch);
  # this VM has none, so map it to the PATH stub for the sim only.
  sed -i 's|/usr/bin/fprintd-list|fprintd-list|g' "$block"
  FAKE="$fake" BLOCK="$block" bash -c '
    set -u
    export HEXCIRI_PATH="$FAKE/usr/share/hexciri" USER=devi HOME="$FAKE/home"
    export PATH="$FAKE/bin:/usr/bin:/bin"
    step() { printf "STEP: %s\n" "$1"; }
    info() { printf "INFO: %s\n" "$1"; }
    warn() { printf "WARN: %s\n" "$1"; }
    sudo() { "$@"; }
    source "$BLOCK"
  ' > "$BASE/sddm-run.log" 2>&1
  return $?
}

# --- 0. preconditions ---
bash -n "$NEW" && ok "bash -n patched install.sh" || bad "bash -n patched install.sh"
grep -q 'hexciri_has_fingerprint_reader()' "$NEW" && ok "reader helper present" || bad "reader helper missing"
grep -q 'hexciri_finger_enrolled()' "$NEW" && ok "enrolled helper present" || bad "enrolled helper missing"
grep -q 'No fingerprint reader detected, SDDM fingerprint lines stripped' "$NEW" && ok "repair branch present" || bad "repair branch missing"
grep -q 'if hexciri_has_fingerprint_reader && hexciri_finger_enrolled; then' "$NEW" && ok "SDDM step gated on reader AND enrolled" || bad "SDDM step gate wrong"
grep -q 'fingerprint: /etc/pam.d/sddm still has pam_fprintd but no fingerprint reader was detected' "$NEW" && ok "health check warns on pam_fprintd with no reader" || bad "health warn missing"

# --- 1. negative control: unpatched, Devi desktop, no reader, stray lines ---
if run_sddm "$OLD" 1 nodevice "$BROKEN_SDDM"; then
  grep -q pam_fprintd "$BASE/fake/etc/pam.d/sddm" && ok "unpatched leaves stray pam_fprintd in place (repair gap reproduced)" || bad "unpatched unexpectedly stripped lines"
else bad "unpatched run failed outright"; fi
grep -q '^Fingerprint=true' "$BASE/fake/usr/share/sddm/themes/hexciri/theme.conf" && ok "unpatched leaves theme.conf Fingerprint=true" || bad "unpatched theme.conf changed"

# --- 2. patched, Devi desktop: no reader, stray lines -> stripped ---
if run_sddm "$NEW" 1 nodevice "$BROKEN_SDDM"; then ok "patched no-reader run succeeds"; else bad "patched no-reader run failed"; cat "$BASE/sddm-run.log"; fi
grep -q pam_fprintd "$BASE/fake/etc/pam.d/sddm" && bad "patched still has pam_fprintd" || ok "patched strips pam_fprintd"
grep -q 'hexciri-hw-laptop-closed' "$BASE/fake/etc/pam.d/sddm" && bad "patched still has gate line" || ok "patched strips gate line"
grep -q 'try_first_pass likeauth nullok' "$BASE/fake/etc/pam.d/sddm" && bad "patched still has pam_unix-first line" || ok "patched strips pam_unix-first line"
grep -q 'auth        include     system-login' "$BASE/fake/etc/pam.d/sddm" && ok "patched keeps stock password stack (system-login)" || bad "patched gutted the stock stack"
grep -q '^Fingerprint=true' "$BASE/fake/usr/share/sddm/themes/hexciri/theme.conf" && bad "patched leaves theme.conf Fingerprint=true" || ok "patched strips theme.conf Fingerprint flag"
grep -q 'SDDM fingerprint lines stripped' "$BASE/sddm-run.log" && ok "patched logs the strip" || bad "patched did not log strip"

# --- 3. patched, no reader, clean stock file -> byte-identical ---
printf '%s' "$STOCK_SDDM" > "$BASE/stock-before.txt"
run_sddm "$NEW" 1 nodevice "$STOCK_SDDM" || bad "patched clean-stock run failed"
cmp -s "$BASE/stock-before.txt" "$BASE/fake/etc/pam.d/sddm" && ok "patched leaves clean stock sddm byte-identical" || bad "patched modified a clean stock file"
grep -q 'left alone (password-only login)' "$BASE/sddm-run.log" && ok "patched logs left-alone on clean file" || bad "no left-alone log"

# --- 4. patched, laptop: reader + enrolled -> lines added, password first ---
run_sddm "$NEW" 0 enrolled "$STOCK_SDDM" || bad "patched laptop run failed"
grep -q 'pam_unix.so try_first_pass likeauth nullok' "$BASE/fake/etc/pam.d/sddm" && ok "laptop: pam_unix-first line added" || bad "laptop: no pam_unix-first line"
grep -q 'auth      sufficient pam_fprintd.so' "$BASE/fake/etc/pam.d/sddm" && ok "laptop: pam_fprintd added" || bad "laptop: no pam_fprintd"
head -1 "$BASE/fake/etc/pam.d/sddm" | grep -q 'pam_unix.so try_first_pass' && ok "laptop: pam_unix is first line (password alone logs in)" || bad "laptop: pam_unix not first"
grep -q 'auth        include     system-login' "$BASE/fake/etc/pam.d/sddm" && ok "laptop: stock stack preserved under fingerprint lines" || bad "laptop: stock stack lost"

# --- 5. patched, reader present but nothing enrolled -> strip, no add ---
run_sddm "$NEW" 0 present "$BROKEN_SDDM" || bad "patched reader-no-enroll run failed"
grep -q pam_fprintd "$BASE/fake/etc/pam.d/sddm" && bad "reader-no-enroll still has pam_fprintd" || ok "reader-no-enroll strips pam_fprintd, adds nothing"

# --- 6. theme.conf gate in install.sh ---
grep -B1 "printf 'Fingerprint=true" "$NEW" | grep -q 'hexciri_has_fingerprint_reader && hexciri_finger_enrolled' && ok "theme.conf Fingerprint=true gated on reader+enrolled" || bad "theme.conf gate not reader-gated"

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

echo "sim32: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
