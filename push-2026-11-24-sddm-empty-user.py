#!/usr/bin/env python3
"""Push the SDDM empty-username fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, branding/sddm/Main.qml, sim34-sddm-empty-user.sh,
patch-2026-11-24-sddm-empty-user.py, push-2026-11-24-sddm-empty-user.py.
Verifies live bytes."""
import hashlib, json, os, subprocess, sys

HOME = os.path.expanduser("~")
ROOT = os.path.join(HOME, "workspace/hexiri-2.0")
OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

paths = ["v2/install.sh", "branding/sddm/Main.qml",
         "sim34-sddm-empty-user.sh",
         "patch-2026-11-24-sddm-empty-user.py",
         "push-2026-11-24-sddm-empty-user.py"]
pf = "/tmp/sddm-empty-user-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

msg = """sddm: fix empty-username login on fresh installs (2026-11-24)

Devi desktop dokoz 20:31 MST (and laptop too, "had they issue too"):
SDDM greeter sent an EMPTY username to PAM, "User not known to the
underlying authentication module", Authentication for user "" failed.
Password worked at a tty, /etc/pam.d/sddm was clean, no fingerprint
lines, faillock empty. Root cause is the Hexciri SDDM theme, not PAM:
branding/sddm/Main.qml set currentUser = config.Username or
userModel.lastUser, SDDM only writes /var/lib/sddm/state.conf [Last]
User on a successful login, and the theme has no username field at
all, so a fresh box has lastUser "" and Enter submits sddm.login("",
password). Chicken-and-egg: no SDDM login can ever succeed to record
a last user. Fix: Main.qml falls back to the first account in
userModel (DisplayRole, then NameRole Qt.UserRole+1, the pattern
Omarchy's own theme uses), and refuses to submit an empty username
("no user account found" instead of a PAM auth failure). Installer
also seeds /var/lib/sddm/state.conf LastUser=$USER on first install
(never overwrites an existing LastUser) and writes
RememberLastUser=true / RememberLastSession=true into
/etc/sddm.conf.d/20-hexciri-theme.conf; health check reports the last
user. sim34 13/13: QML logic mirror 6 cases (fresh install -> devi,
lastUser/config.Username still win), seed writes LastUser=devi and
never overwrites, fingerprints via --print-fingerprints: upstream /
patch / system stable, provision moves only, so next update is
re-apply-provision, which recopies the theme. bash -n clean. QML was
not parsed by a real Qt runtime in this VM (no qml6 here); the edit
is a small property block following Omarchy's own model-access pattern.
"""
r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", msg, "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])
r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
