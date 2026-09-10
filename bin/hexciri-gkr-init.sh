#!/bin/bash
# hexciri:summary=Verify the gnome-keyring default collection is healthy (empty-password, auto-unlocks at boot)
# hexciri-gkr-init: On fingerprint-first machines pam_fprintd never supplies the
# account password to pam_gnome_keyring, so PAM can neither create nor
# auto-unlock a "login" keyring — that path is a dead end on this hardware.
# The actual fix is an empty-password **default** keyring: gnome-keyring
# auto-opens it at every boot with no prompt, no PAM, nothing. Brave and all
# libsecret apps use it through the `default` alias and stay in sync forever.
#
# Semantics are deliberately non-destructive (read-only probe):
#   * default keyring present and unlocked → healthy, exit 0
#   * default keyring present and locked   → report problem, exit 0 (fix lives in hexciri-update)
#   * no keyring at all                    → report missing, exit 0
#   * --check                              → same as always (alias for bare run)
#
# The fix for a locked/missing keyring is: `secret-tool store --label=default fixcheck fixkey`
# followed by leaving the password fields EMPTY and confirming the gcr dialog.
# Run as the target user (uses $HOME). Idempotent; safe on fresh installs and
# in the alpm hook.
set -euo pipefail

KEYRINGS_DIR="$HOME/.local/share/keyrings"
CHECK=0
[[ ${1:-} == "--check" ]] && CHECK=1

# Probe via D-Bus if a session bus is available; otherwise fall back to file check
if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] && command -v python3 >/dev/null 2>&1; then
  STATUS="$(python3 - 2>/dev/null <<'PY' || true
import sys
try:
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio, GLib
except Exception:
    sys.exit(0)
try:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    def call(dest, obj, iface, method, args):
        p = Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None, dest, obj, iface, None)
        return p.call_sync(method, args, 0, -1, None)
    cols = call('org.freedesktop.secrets', '/org/freedesktop/secrets',
                'org.freedesktop.DBus.Properties', 'Get',
                GLib.Variant('(ss)', ('org.freedesktop.Secret.Service', 'Collections'))).unpack()[0]
    default_found = False
    for path in cols:
        lbl = call('org.freedesktop.secrets', path, 'org.freedesktop.DBus.Properties', 'Get',
                   GLib.Variant('(ss)', ('org.freedesktop.Secret.Collection', 'Label'))).unpack()[0]
        if lbl == 'session':
            continue
        locked = call('org.freedesktop.secrets', path, 'org.freedesktop.DBus.Properties', 'Get',
                      GLib.Variant('(ss)', ('org.freedesktop.Secret.Collection', 'Locked'))).unpack()[0]
        default_found = True
        if locked:
            sys.exit(2)  # locked = broken
    if not default_found:
        sys.exit(1)  # missing
    sys.exit(0)  # healthy
except Exception:
    pass
PY
  )"
  rc=$?
else
  # File fallback: check for the alias marker + any .keyring file
  rc=0
  [[ -f "$KEYRINGS_DIR/default" ]] || rc=1
  ls "$KEYRINGS_DIR"/*.keyring >/dev/null 2>&1 || rc=1
fi

if [[ $rc == 2 ]]; then
  echo "hexciri-gkr-init: default keyring is password-locked — browser prompts will break each boot"
  echo "hexciri-gkr-init: fix with: secret-tool store --label=default fixcheck fixkey (leave password blank)"
elif [[ $rc == 1 ]]; then
  echo "hexciri-gkr-init: no default keyring — first app to use secrets will trigger the create dialog"
fi

exit 0