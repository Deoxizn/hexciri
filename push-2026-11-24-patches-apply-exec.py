#!/usr/bin/env python3
"""Push the patches/apply.sh exec-bit fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, v2/hexciri-update-hexciri, sim30-patches-apply.sh,
patch-2026-11-24-patches-apply-exec.py, push-2026-11-24-patches-apply-exec.py.
Built in /tmp/patches-apply-push from live HEAD a812b576. Refuses to push
if live nyx HEAD has moved (rebase first). Verifies live bytes after
the push with a fresh raw fetch + sha256.
"""
import hashlib, json, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "a812b576f7f8a236104ff13c137aa48da81c3f60"
SRC = "/tmp/patches-apply-push"
EXPECT_INSTALL = "441d084e834090aa7d6428858f4b1f92ae8ae1179ad0ac2fff8079799f3d2c5b"
EXPECT_UPDATER = "3920cc9e4e4032d31616bb4818da4b1b28dd6adc3853e448d8b6edb9fa3e1cdd"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

# 1. Live HEAD must still be the base this patch was built on.
r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
live = json.loads(r.stdout)["result"]["content"][0]["text"]
live_sha = json.loads(live)["sha"]
assert live_sha == BASE_HEAD, f"live nyx HEAD moved: {live_sha}, refusing to push (rebase first)"
print("live nyx HEAD is still", BASE_HEAD)

paths = ["v2/install.sh", "v2/hexciri-update-hexciri", "sim30-patches-apply.sh",
         "patch-2026-11-24-patches-apply-exec.py",
         "push-2026-11-24-patches-apply-exec.py"]
import os
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())
assert hashlib.sha256(open(os.path.join(SRC, "v2/install.sh"), "rb").read()).hexdigest() == EXPECT_INSTALL, \
    "patched install.sh sha mismatch, refusing to push"
assert hashlib.sha256(open(os.path.join(SRC, "v2/hexciri-update-hexciri"), "rb").read()).hexdigest() == EXPECT_UPDATER, \
    "patched updater sha mismatch, refusing to push"

pf = "/tmp/patches-apply-push-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "fix: patches/apply.sh exec-bit guard killed every update after the patches refactor (2026-11-24)\n\nDevi 16:54 MST, laptop: update died at the fork-patch step:\nERROR: v2/patches/apply.sh not in the installer tree\n(/home/devi/.local/opt/hexciri-nyx/v2/patches)\n\nRoot cause, proven against live nyx a812b576: apply.sh is mode 100644\nin the repo (github push-files does not preserve exec bits, AGENTS.md\nlesson). install.sh guarded it with [ -x \"$PATCHES_DIR/apply.sh\" ],\nso on every fresh git clone the guard failed even though git pull had\nbrought the whole patches dir fine. Nothing needs +x: install.sh\ninvokes apply.sh via bash, and apply.sh invokes each patch via bash.\n\nFix: (1) install.sh guard -x -> -f, with a comment saying why, die\nmessage now says \"missing from\" instead of \"not in\". (2)\nhexciri-update-hexciri verifies v2/patches/apply.sh is present after\na git sync / tarball extract, so a missing-patches sync fails early\n(and the tarball fallback gets a chance) instead of forking 94 MB of\nOmarchy and dying at the patch step. sim30 22/22: unpatched fork\ndies with Devi's exact error, patched fork completes (1644 files,\nmenu jsonc parses, bootstrap.lua/hexciri.lua/tmux/foot.desktop all\npresent), bash -n clean, upstream/provision/system fingerprints\nstable, patch fingerprint changed (updater is in patch_fp list, so\nnext update is a re-apply: fork + placement only).",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
new = json.loads(json.loads(r.stdout)["result"]["content"][0]["text"])
print("new nyx HEAD:", new["sha"])
print(new["commit"]["message"].split("\n")[0])
assert new["sha"] != BASE_HEAD, "HEAD did not move after push"

# 2. Verify live bytes: fresh raw fetch, sha256 must match the patched files.
import urllib.request
for rel, expect in [("v2/install.sh", EXPECT_INSTALL),
                    ("v2/hexciri-update-hexciri", EXPECT_UPDATER)]:
    raw = urllib.request.urlopen(
        f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{BRANCH}/{rel}").read()
    live_bytes_sha = hashlib.sha256(raw).hexdigest()
    print(f"live {rel} sha256:", live_bytes_sha)
    assert live_bytes_sha == expect, f"LIVE BYTES MISMATCH after push: {rel}"
print("LIVE BYTES VERIFIED")
print("NYX PUSH DONE")
