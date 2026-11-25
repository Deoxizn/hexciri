#!/usr/bin/env python3
"""Patch v2/install.sh: SDDM fingerprint only when a reader is detected.

Devi 2026-11-24 20:19 MST, desktop dokoz (no fingerprint reader): SDDM
kept saying failed, password not accepted, while the same password works
at a tty. Same as Hexciri v1 on vanilla Arch: fingerprint stuff must only
be set up when a reader is detected.

What was wrong: the installer SDDM step only added pam_fprintd lines when
a finger was enrolled, but nothing ever REPAIRED /etc/pam.d/sddm on a
machine with no reader. Any stray Hexciri fingerprint lines in that file
(pam_fprintd, the hw-laptop-closed gate, the pam_unix-first line) make
SDDM demand a touch it can never get, so password login fails at the
greeter while tty login works. The old else branch just logged "left
alone" and walked away.

Fix:
1. New helpers hexciri_has_fingerprint_reader() (forked
   hexciri-hw-fingerprint sysfs USB probe first, fprintd-list exit status
   as fallback for non-USB readers) and hexciri_finger_enrolled().
2. SDDM step now requires reader AND enrolled to add lines; otherwise it
   REPAIRS: strips every Hexciri fingerprint line from /etc/pam.d/sddm
   and Fingerprint= from the SDDM theme.conf, only writing when something
   actually changed.
3. SDDM theme.conf Fingerprint=true now also requires a detected reader.
4. Health check warns when /etc/pam.d/sddm still has pam_fprintd but no
   reader was detected, and reports password-only otherwise.
"""
import hashlib
import sys

P = "/home/hatch/workspace/hexiri-2.0/v2/install.sh"
s = open(P).read()
orig = s

# --- 1+2. Helpers + SDDM fingerprint step rewrite -------------------------
old_head = """# --- SDDM fingerprint (login unlock, 2026-11-23) ---"""
assert s.count(old_head) == 1

old_step = '''step "Configuring SDDM fingerprint (login unlock)"
if command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'; then'''
assert s.count(old_step) == 1

old_else = '''else
  info "No fingers enrolled, /etc/pam.d/sddm left alone (enroll one, then re-run the installer or Setup > Security > Fingerprint)"
fi'''
assert s.count(old_else) == 1

new_helpers = '''# hexciri_has_fingerprint_reader / hexciri_finger_enrolled (2026-11-24,
# Devi desktop dokoz, no reader: SDDM password login failed while the same
# password worked at a tty, same as Hexciri v1 on vanilla Arch). Fingerprint
# setup must only happen when a reader is actually detected, and a machine
# with no reader must have any stray fingerprint lines stripped, not left
# alone: pam_fprintd in /etc/pam.d/sddm makes SDDM demand a touch it can
# never get, so password login fails at the greeter only. The sysfs USB
# probe (forked hexciri-hw-fingerprint) works before fprintd is installed;
# fprintd-list's exit status is the fallback for non-USB readers (Touch ID
# behind a Secure Enclave): exit 0 means a device answered, non-zero means
# "No devices available".
hexciri_has_fingerprint_reader() {
  if [ -x "$HEXCIRI_PATH/bin/hexciri-hw-fingerprint" ]; then
    "$HEXCIRI_PATH/bin/hexciri-hw-fingerprint" 2>/dev/null && return 0
  fi
  if command -v fprintd-list >/dev/null 2>&1; then
    /usr/bin/fprintd-list "$USER" >/dev/null 2>&1 && return 0
  fi
  return 1
}
hexciri_finger_enrolled() {
  command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'
}
'''

s = s.replace(old_head, old_head + "\n" + new_helpers.rstrip("\n"), 1)
s = s.replace(old_step,
              'step "Configuring SDDM fingerprint (login unlock)"\nif hexciri_has_fingerprint_reader && hexciri_finger_enrolled; then', 1)

new_else = '''else
  # Repair, not "left alone": no reader, or a reader with nothing enrolled.
  # Any Hexciri fingerprint lines already in /etc/pam.d/sddm (earlier run,
  # manual Setup > Security > Fingerprint, stale order) demand a touch
  # SDDM can never get on this machine, so password login fails at the
  # greeter while the same password works at a tty. Strip them; the stock
  # password stack (auth include system-login and friends) stays in the
  # file underneath, untouched by these patterns.
  if [ -f /etc/pam.d/sddm ] && grep -Eq 'pam_fprintd\\.so|hexciri-hw-laptop-closed|try_first_pass likeauth nullok' /etc/pam.d/sddm; then
    _sddm_tmp="$(mktemp)"
    if sudo sed -e '/pam_fprintd\\.so/d' -e '/hexciri-hw-laptop-closed/d' -e '/try_first_pass likeauth nullok/d' /etc/pam.d/sddm > "$_sddm_tmp" 2>/dev/null && sudo install -Dm644 "$_sddm_tmp" /etc/pam.d/sddm; then
      info "No fingerprint reader detected, SDDM fingerprint lines stripped from /etc/pam.d/sddm (password-only login restored)"
    else
      warn "could not strip SDDM fingerprint lines from /etc/pam.d/sddm, password login may still fail (strip them by hand: sudo sed -i -e '/pam_fprintd\\.so/d' -e '/hexciri-hw-laptop-closed/d' -e '/try_first_pass likeauth nullok/d' /etc/pam.d/sddm)"
    fi
    rm -f "$_sddm_tmp"
    unset _sddm_tmp
  else
    info "No fingerprint reader detected, /etc/pam.d/sddm left alone (password-only login)"
  fi
  if [ -f /usr/share/sddm/themes/hexciri/theme.conf ] && grep -q '^Fingerprint=' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null; then
    sudo sed -i '/^Fingerprint=/d' /usr/share/sddm/themes/hexciri/theme.conf 2>/dev/null && info "SDDM theme Fingerprint flag removed (no reader)" || true
  fi
fi'''
s = s.replace(old_else, new_else, 1)

# --- 3. Theme.conf Fingerprint=true also requires a detected reader -------
old_theme = '''    if command -v fprintd-list >/dev/null 2>&1 && /usr/bin/fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+:'; then
      printf 'Fingerprint=true\\n' >> "$TMP_SDDM_CONF"'''
assert s.count(old_theme) == 1
s = s.replace(old_theme,
              '''    if hexciri_has_fingerprint_reader && hexciri_finger_enrolled; then
      printf 'Fingerprint=true\\n' >> "$TMP_SDDM_CONF"''', 1)

# --- 4. Health check: pam_fprintd with no reader is the broken state ------
old_health = '''  else
    warn "  fingerprint: enrolled, but /etc/pam.d/sddm has no pam_fprintd, SDDM login stays password-only"
  fi
fi'''
assert s.count(old_health) == 1
new_health = old_health + '''
if ! hexciri_has_fingerprint_reader 2>/dev/null; then
  if grep -q pam_fprintd.so /etc/pam.d/sddm 2>/dev/null; then
    warn "  fingerprint: /etc/pam.d/sddm still has pam_fprintd but no fingerprint reader was detected, SDDM password login may fail (re-run the installer to strip it)"
  else
    hc_info "  fingerprint: no reader detected, SDDM is password-only"
  fi
fi'''
s = s.replace(old_health, new_health, 1)

assert s != orig, "patch made no changes"
open(P, "w").write(s)
print("patched, new sha256:", hashlib.sha256(s.encode()).hexdigest())
print("lines:", s.count("\n"))
