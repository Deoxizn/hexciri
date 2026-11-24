#!/usr/bin/env python3
"""Push the Install > Style > Background -> Strata fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim22-bg-install-strata.sh,
patch-2026-11-24-bg-install-strata.py, push-2026-11-24-bg-install-strata.py.
Verifies live bytes. Pushes from /tmp/bg-push (separate source dir), NOT
from ~/workspace/hexiri-2.0, because a sibling agent (minimal re-apply) is
concurrently editing ~/workspace/hexiri-2.0/v2/install.sh from the same
base; the patched install.sh was built in /tmp/bg-live from live HEAD.
Refuses to push if live nyx HEAD is no longer 91299f9.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "91299f92262074e9ca28cba7e1c1607a11c36d37"
SRC = "/tmp/bg-push"

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

paths = ["v2/install.sh", "sim22-bg-install-strata.sh",
         "patch-2026-11-24-bg-install-strata.py",
         "push-2026-11-24-bg-install-strata.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/bg-install-strata-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "menu: Install > Style > Background opens in Strata, not folio (2026-11-24)\n\nMenu row install.style.background calls hexciri-theme-bg-install, which ended with bare `folio \"$THEME_USER_BACKGROUNDS\"`. Folio is not installed in Hexciri v2 (file manager is Strata via GitHub, not Folio; no nautilus either), so the command failed silently and nothing opened. The fork rename only mapped folio -> strata for the uwsm-app invocation in launch-files; the bare folio call was never touched. Fix (fork patch): theme-bg-install opens the folder with hexciri-launch-files (Strata via uwsm-app), and launch-files now forwards \"$@\" to strata (zero args expands to nothing, so Super+Shift+F is unchanged; hexciri-launch-nautilus forwards its path too). Strata accepts a path: launch-files-cwd already passes one. No Folio/nautilus install. Placement verification dies if either patch is missing. sim22 12/12, and the same checks fail on the unpatched file (pristine fork still has the folio call). bash -n clean.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
