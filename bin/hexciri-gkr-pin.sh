#!/bin/bash
# hexciri: one-time fix for the gnome-keyring 50.0 crash (run as root):
#   * disable the globally-enabled gnome-keyring socket units so socket
#     activation can no longer start the daemon BEFORE PAM runs — version pin
#     alone leaves PAM auto_start racing the socket and losing
#   * downgrade gnome-keyring to 48.0 (last stable pre-50 build)
#   * park it with IgnorePkg until upstream ships a fixed 50.x
#   * remove the mask/override guard layer from the old crash workaround —
#     with the socket disabled and 48.0 installed, the PAM daemon stays the
#     sole owner of org.freedesktop.secrets and never crashes
# Idempotent; safe to re-run.
set -euo pipefail

GKR_VER="1:48.0-1-x86_64"
GKR_URL="https://archive.archlinux.org/packages/g/gnome-keyring/gnome-keyring-1%3A48.0-1-x86_64.pkg.tar.zst"
GKR_PKG="/var/cache/pacman/pkg/gnome-keyring-${GKR_VER}.pkg.tar.zst"

# ── 0. stale staged PAM file must never get installed ──
rm -f /tmp/sddm.pam

# ── 1. win the socket race: PAM auto_start is the sole starter ──
#    (the gnome-keyring-daemon.socket unit ships enabled at GLOBAL scope in
#    /etc/systemd/user/sockets.target.wants/; see install.sh keyring block)
systemctl --global disable gnome-keyring-daemon.socket gnome-keyring-daemon.service 2>/dev/null || true

# ── 2. downgrade gnome-keyring to 48.0 ──
if pacman -Q gnome-keyring 2>/dev/null | grep -qE '[ :]48\.'; then
  echo "gnome-keyring already at 48.0"
else
  [[ -f $GKR_PKG ]] || curl -fLo "$GKR_PKG" "$GKR_URL"
  pacman -U --noconfirm "$GKR_PKG"
  echo "gnome-keyring downgraded to 48.0"
fi

# ── 3. park it (survives the next pacman run, incl. our alpm hook) ──
#    must live under [options]; appending at EOF lands in the last repo section
if ! grep -Eq '^IgnorePkg[[:space:]]*=.*gnome-keyring' /etc/pacman.conf; then
  sed -i '/^\[options\]/a IgnorePkg = gnome-keyring' /etc/pacman.conf
  echo "parked gnome-keyring via IgnorePkg"
fi

# ── 4. drop the guard layer from the 50.0 workaround ──
#    user-level unit masks + the local dbus override were the workaround;
#    stock units + stock dbus service file are what 48.0 needs
for m in /etc/systemd/user/gnome-keyring-daemon.service \
         /etc/systemd/user/gnome-keyring-daemon.socket \
         /home/devi/.config/systemd/user/gnome-keyring-daemon.service \
         /home/devi/.config/systemd/user/gnome-keyring-daemon.socket; do
  [[ -L $m || -f $m ]] && rm -f "$m"
done
rm -f /usr/local/share/dbus-1/services/org.freedesktop.secrets.service \
      /home/devi/.local/share/dbus-1/services/org.freedesktop.secrets.service
rmdir /etc/systemd/user /usr/local/share/dbus-1/services \
      /home/devi/.local/share/dbus-1/services 2>/dev/null || true
su - devi -c 'systemctl --user daemon-reload' 2>/dev/null || true
echo "guard layer removed (masks + dbus overrides)"

# ── 5. verify ──
echo "--- verify ---"
pacman -Q gnome-keyring
grep -E '^IgnorePkg' /etc/pacman.conf
systemctl --global is-enabled gnome-keyring-daemon.socket 2>/dev/null | sed 's/^/socket globally: /'
systemctl --global is-enabled gnome-keyring-daemon.service 2>/dev/null | sed 's/^/service globally: /'
ls -la /etc/systemd/user/ 2>/dev/null | grep keyring || echo "no system-level keyring masks"
ls -la /home/devi/.config/systemd/user/ 2>/dev/null | grep keyring || echo "no user-level keyring masks"
ls /usr/local/share/dbus-1/services/ /home/devi/.local/share/dbus-1/services/ 2>/dev/null | grep secrets || echo "no secrets dbus overrides"
echo "done — reboot, then re-enroll the fingerprint from the greeter session"