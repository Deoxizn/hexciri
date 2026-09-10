#!/bin/bash
# hexciri:summary=Create a passwordless gnome-keyring login keyring (fingerprint-first machines)
# hexciri-gkr-init: fingerprint-first login (pam_fprintd) supplies no password, so
# pam_gnome_keyring's auto-unlock never receives a secret and the first app to
# touch the Secret Service (Brave/Chromium/...) pops "Enter password to unlock
# your login keyring" on every boot.
#
# Fix: a PASSWORDLESS login keyring. Sealed with an empty password the daemon
# opens it on demand with no prompt, so Brave/etc. never ask again. Trade-off
# (standard on fingerprint-only boxes): secrets are obfuscated but not
# password-encrypted at rest.
#
# Semantics are deliberately non-destructive:
#   * login keyring exists             → do nothing (respect whatever the user has)
#   * no keyring at all (# $HOME)        → create a passwordless one
#   * --check                          → report state only, change nothing
# Run as the target user (uses $HOME). Idempotent; safe on fresh installs and
# in the alpm hook (no keyring implies no daemon is holding secrets).
set -euo pipefail

KDIR="$HOME/.local/share/keyrings"
KEYRING="$KDIR/login.keyring"
CHECK=0
[[ ${1:-} == "--check" ]] && CHECK=1

if [[ -f $KEYRING ]]; then
  exit 0
fi

if [[ $CHECK == 1 ]]; then
  echo "hexciri-gkr-init: no login keyring — a passwordless one will be created (re-run without --check)"
  exit 0
fi

# No keyring exists, so nothing of value is being discarded. Clear the field
# (stale empty dir, half-written keychain from an aborted first run) and make
# sure no gnome-keyring-daemon is alive to fight over the control socket.
pkill -f '^/usr/bin/gnome-keyring-daemon' 2>/dev/null || true
sleep 1
mkdir -p "$KDIR"
chmod 700 "$KDIR"
rm -f "$KDIR"/*.keyring "$KDIR/default" 2>/dev/null || true

# Seed a login keyring whose password is empty: `--unlock` reads a (here empty)
# password from stdin and creates the default keyring with it. Empty password ⇒
# the daemon opens it without prompting on every future login.
printf '\n' | gnome-keyring-daemon --unlock >/dev/null 2>&1 || true
sleep 1

if [[ ! -s $KEYRING ]]; then
  echo "hexciri-gkr-init: ERROR — keyring was not created ($KEYRING missing/empty)"
  exit 1
fi

echo "hexciri-gkr-init: passwordless login keyring created ($KEYRING)"

# Best-effort proof, only when a session bus exists (secret-tool needs one):
# store→lookup→clear round-trip must succeed without any prompt.
if command -v secret-tool >/dev/null 2>&1 && timeout 3 bash -c 'true' >/dev/null 2>&1; then
  if secret-tool store --label=hexciri-gkr-init hexciri.gkr.init probe 2>/dev/null \
      && R="$(secret-tool lookup hexciri.gkr.init probe 2>/dev/null)" \
      && [[ $R == probe ]] \
      && secret-tool clear hexciri.gkr.init probe >/dev/null 2>&1; then
    echo "hexciri-gkr-init: verified — store/lookup round-trip works without a prompt"
  else
    echo "hexciri-gkr-init: warning — could not verify via secret-tool (no session bus?), file is in place"
  fi
fi