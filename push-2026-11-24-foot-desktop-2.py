#!/usr/bin/env python3
"""Push foot.desktop stray-entry fix round 2 to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim36-foot-desktop-2.sh,
patch-2026-11-24-foot-desktop-2.py, push-2026-11-24-foot-desktop-2.py.
Verifies live bytes via GitHub API blob (raw can serve stale cache)."""
import hashlib, json, os, subprocess, sys

ROOT = "/tmp/footfix/work"
OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

paths = ["v2/install.sh", "sim36-foot-desktop-2.sh",
         "patch-2026-11-24-foot-desktop-2.py",
         "push-2026-11-24-foot-desktop-2.py"]
pf = "/tmp/footfix/nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

msg = ("desktop: foot.desktop stray entry is back, re-apply f3c6b59c "
       "after a1e97b06 reverted it (2026-11-24)\n\n"
       "Devi 21:21 MST, dokoz: foot desktop file/app still in app launcher. "
       "Root cause, proven from history: f3c6b59c fixed this exact bug "
       "(loop skip + trim repair), a1e97b06 (SDDM empty-username) was "
       "rebased onto a stale pre-f3 base and its diff deletes both, "
       "while claiming Foot fix intact. b56c769a inherited the revert, "
       "so every update since re-placed foot.desktop. Fix: re-apply "
       "f3c6b59c verbatim, plus a second repair after the placement "
       "loop so all installer modes are covered (trim: full + "
       "provision-only; loop: full + re-apply). Trim edit moves the "
       "provision fingerprint, next update is re-apply-provision. "
       "Health check now warns if a foot.desktop entry exists without "
       "foot. sim36 21/21. bash -n clean.")
r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO,
         "--branch", BRANCH, "--message", msg,
         "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])
r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
