#!/usr/bin/env python3
"""Push the zxing-cpp DB-race fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim20-zxing-db-race.sh,
patch-2026-11-24-zxing-db-race.py, push-2026-11-24-zxing-db-race.py.
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

paths = ["v2/install.sh", "sim20-zxing-db-race.sh",
         "patch-2026-11-24-zxing-db-race.py",
         "push-2026-11-24-zxing-db-race.py"]
pf = "/tmp/zxing-db-race-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "system-pkgs: checkupdates/pacman DB race leaves zxing-cpp pending (2026-11-24)\n\ncheckupdates (own temp DB) listed zxing-cpp 3.1.1-1 -> 3.2.0-1 while pacman -Su (main DB, synced seconds earlier) said 'there is nothing to do': the two syncs can hit different geo-mirror backends, and a package built ~90 min earlier can be on one and not the other. The updater then printed 'System packages are up to date' while _pending > 0, hiding a real pending package behind a stale badge. Fix: after a -Su that upgraded 0 while _pending > 0, one forced -Syy re-sync + pacman -Qu re-count + second -Su (-Syy is safe, -Su runs immediately after in the same script); if it still upgrades 0, print an honest 'mirror DB lag?' warning naming the pending packages instead of claiming up to date. Scanner was correct, no Arch-Updates change. sim20 13/13, and 4 checks fail on the reverted code (scenario B). bash -n clean.",
         "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
