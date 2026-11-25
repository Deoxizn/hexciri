#!/usr/bin/env python3
"""Push the foot.desktop stray-entry fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim33-foot-desktop.sh,
patch-2026-11-24-foot-desktop.py, push-2026-11-24-foot-desktop.py.
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

paths = ["v2/install.sh", "sim33-foot-desktop.sh",
         "patch-2026-11-24-foot-desktop.py",
         "push-2026-11-24-foot-desktop.py"]
pf = "/tmp/foot-desktop-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "desktop: stop placing foot.desktop when Foot is not installed (2026-11-24)\n\nDevi desktop 20:26/20:27 MST, dokoz: Foot looked installed on top of Kitty, but pacman -Q | grep foot came back blank, only the desktop file was there. Root cause: the desktop-entry placement loop placed EVERY FORK_OUT/applications/*.desktop into ~/.local/share/applications/, including foot.desktop, whose only job is to be install-terminal foot's source (it copies it there itself when it installs the foot package). Fix: loop skips foot.desktop unless command -v foot; NoDisplay append is wrappers-only so a real installed Foot stays visible; repair in the trim section removes a stray Hexciri-placed foot.desktop (plain Exec=foot) when foot is absent, never a user-customised entry. Repair lives in trim, not by the loop, on purpose: the loop is in the Place-the-forked-tree section, in NO fingerprint range, so a repair there would light-sync and never run; trim is provision range, so provision moves only and the next update re-applies provision. Placed tree keeps foot.desktop, install-terminal foot keeps working. sim33 23/23: unpatched places it with no foot installed, patched removes the stray, never places it when absent, places it visible when foot is installed, leaves a custom entry alone. bash -n clean.",
         "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
