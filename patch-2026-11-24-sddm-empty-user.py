#!/usr/bin/env python3
"""Patch SDDM empty-username login (2026-11-24, dokoz + laptop).

Root cause: branding/sddm/Main.qml set currentUser = config.Username or
userModel.lastUser. On a fresh install SDDM has never logged anyone in,
so /var/lib/sddm/state.conf has no [Last] User, lastUser is "", and the
theme has no username field at all, so Enter submits sddm.login("",
password) and PAM dies "User not known to the underlying authentication
module". Fix: QML falls back to the first account in userModel, installer
seeds /var/lib/sddm/state.conf LastUser and writes RememberLastUser=true,
and the greeter refuses to submit an empty username.
Edits v2/install.sh (provision range) and branding/sddm/Main.qml.
"""
import pathlib, sys

ROOT = pathlib.Path.home() / "workspace/hexiri-2.0"
INSTALL = ROOT / "v2/install.sh"
QML = ROOT / "branding/sddm/Main.qml"

def replace_once(text, old, new, label):
    n = text.count(old)
    assert n == 1, f"{label}: expected 1 occurrence, found {n}"
    return text.replace(old, new)

# --- Main.qml: first-user fallback ---
qml = QML.read_text()
old_user = """  property string currentUser: {
    if (config.Username && config.Username.length > 0) return config.Username
    return userModel.lastUser
  }
"""
new_user = """  // First login after a fresh install has no last user yet: SDDM only
  // writes /var/lib/sddm/state.conf [Last] User on a successful login,
  // and this theme has no username field at all, so userModel.lastUser
  // is "" and sddm.login("", password) dies in PAM with "User not known
  // to the underlying authentication module" (dokoz + laptop, 2026-11-24).
  // Fall back to the first account in the user model, so a fresh box
  // logs in on its first SDDM attempt. DisplayRole is what Omarchy's
  // own theme uses for model names; UserRole+1 is SDDM's NameRole.
  property string currentUser: {
    if (config.Username && config.Username.length > 0) return config.Username
    if (userModel.lastUser && userModel.lastUser.length > 0) return userModel.lastUser
    if (userModel.rowCount() > 0) {
      var first = userModel.data(userModel.index(0, 0), Qt.DisplayRole)
      if (first && first.toString().length > 0) return first.toString()
      first = userModel.data(userModel.index(0, 0), Qt.UserRole + 1)
      if (first && first.toString().length > 0) return first.toString()
    }
    return ""
  }
"""
qml = replace_once(qml, old_user, new_user, "currentUser")
old_login = """              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.infoText = ""
                sddm.login(root.currentUser, password.text, root.sessionIndex)
                event.accepted = true
              }
"""
new_login = """              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.infoText = ""
                if (root.currentUser.length === 0) {
                  root.errText = "no user account found"
                  event.accepted = true
                  return
                }
                sddm.login(root.currentUser, password.text, root.sessionIndex)
                event.accepted = true
              }
"""
qml = replace_once(qml, old_login, new_login, "empty-login guard")
QML.write_text(qml)

# --- install.sh: RememberLastUser + seed state.conf + health line ---
text = INSTALL.read_text()
old_theme_conf = """  printf '[Theme]\\nCurrent=hexciri\\n' > "$TMP_SDDM_THEME"
"""
new_theme_conf = """  printf '[Theme]\\nCurrent=hexciri\\n[Users]\\nRememberLastUser=true\\nRememberLastSession=true\\n' > "$TMP_SDDM_THEME"
"""
text = replace_once(text, old_theme_conf, new_theme_conf, "RememberLastUser")

old_seed_anchor = """  unset SDDM_BG
else
  warn "No SDDM theme source found, keeping the EndeavourOS default SDDM theme."
"""
new_seed = """  unset SDDM_BG
  # Seed SDDM's last-user state (2026-11-24, empty-username login):
  # SDDM only writes /var/lib/sddm/state.conf [Last] User on a
  # successful login, so a fresh install has no last user and the
  # greeter (no username field) used to submit "" to PAM. The QML
  # fallback to the first user in the model is the real fix; seeding
  # here is belt-and-braces so lastUser is already correct on the
  # first boot, and it is never overwritten when a last user exists.
  if [ ! -s /var/lib/sddm/state.conf ] || ! grep -q '^User=' /var/lib/sddm/state.conf 2>/dev/null; then
    _sddm_state="$(mktemp)"
    printf '[Last]\\nUser=%s\\nSession=/usr/share/wayland-sessions/hexciri.desktop\\n' "$USER" > "$_sddm_state"
    if sudo install -Dm644 "$_sddm_state" /var/lib/sddm/state.conf 2>/dev/null; then
      info "SDDM last user seeded: $USER (/var/lib/sddm/state.conf)"
    else
      warn "could not seed /var/lib/sddm/state.conf, first SDDM login relies on the theme's first-user fallback"
    fi
    rm -f "$_sddm_state"
    unset _sddm_state
  fi
else
  warn "No SDDM theme source found, keeping the EndeavourOS default SDDM theme."
"""
text = replace_once(text, old_seed_anchor, new_seed, "state.conf seed")

old_health = """if [ -f /usr/share/sddm/themes/hexciri/Main.qml ]; then
  hc_info "  sddm theme: /usr/share/sddm/themes/hexciri (Main.qml present)"
else
  warn "  sddm theme: hexciri theme not installed, SDDM uses its default theme (cosmetic only, login still works)"
fi
"""
new_health = old_health + """if [ -f /var/lib/sddm/state.conf ] && grep -q '^User=' /var/lib/sddm/state.conf 2>/dev/null; then hc_info "  sddm last user: $(grep '^User=' /var/lib/sddm/state.conf | cut -d= -f2)"; else warn "  sddm last user: /var/lib/sddm/state.conf has no Last User, first SDDM login relies on the theme's first-user fallback (re-run the installer to seed it)"; fi
"""
text = replace_once(text, old_health, new_health, "health last-user")
INSTALL.write_text(text)
print("patched OK: branding/sddm/Main.qml + v2/install.sh")
