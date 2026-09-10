#!/bin/bash
# hexciri:summary=Keep the gnome-keyring login keyring healthy (PAM re-creates it on missing)
# hexciri-gkr-init: fingerprint-first login (pam_fprintd) supplies no password, so
# pam_gnome_keyring's auto-unlock never receives a secret and the first app to
# touch the Secret Service (Brave/Chromium/...) pops "Enter password to unlock
# your login keyring" on every boot.
#
# The robust repair is to let PAM own the keyring: at your next sign-in
# pam_gnome_keyring re-creates a missing login keyring with your account
# password and auto-unlocks it for the whole session — no prompts, stable for
# browser sync. Pre-seeding a keyring ourselves is deliberately Off the table:
# on gnome-keyring 1:48 `gnome-keyring-daemon --unlock` writes only a stub that
# the Secret Service still treats as password-protected (this silently broke a
# running box), so hexciri never fabricates keyring files anymore.
#
# Semantics are deliberately non-destructive:
#   * login keyring exists   → do nothing (respect whatever the user has)
#   * no keyring at all      → do nothing; PAM creates it at the next sign-in
#   * --check                → report state only, change nothing
# Run as the target user (uses $HOME). Idempotent; safe on fresh installs and
# in the alpm hook. The actual lock-and-remove repair lives in hexciri-update
# (session side, where a locked login collection can be detected).
set -euo pipefail

KEYRING="$HOME/.local/share/keyrings/login.keyring"
CHECK=0
[[ ${1:-} == "--check" ]] && CHECK=1

if [[ -f $KEYRING ]]; then
  exit 0
fi

if [[ $CHECK == 1 ]]; then
  echo "hexciri-gkr-init: no login keyring — pam_gnome_keyring re-creates it at your next sign-in"
  exit 0
fi

echo "hexciri-gkr-init: no login keyring; leaving creation to PAM at the next sign-in (recommended)"
exit 0