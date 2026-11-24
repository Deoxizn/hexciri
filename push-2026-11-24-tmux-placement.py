#!/usr/bin/env python3
"""Push the tmux placement fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim25-tmux-placement.sh,
patch-2026-11-24-tmux-placement.py, push-2026-11-24-tmux-placement.py.
Pushes from /tmp/tmux-push (separate source dir), NOT from
~/workspace/hexiri-2.0, because sibling agents (AI/Foot restore, binds)
may be editing ~/workspace/hexiri-2.0/v2/install.sh concurrently; the
patched install.sh was built in /tmp/tmux-live from live HEAD 2cdc33c7.
Refuses to push if live nyx HEAD is no longer 2cdc33c7.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "2cdc33c797cda4a6bc43af227e0465696b0c7daf"
SRC = "/tmp/tmux-push"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
live = json.loads(r.stdout)["result"]["content"][0]["text"]
live_sha = json.loads(live)["sha"]
assert live_sha == BASE_HEAD, f"live nyx HEAD moved: {live_sha}, refusing to push (rebase first)"
print("live nyx HEAD is still", BASE_HEAD)

paths = ["v2/install.sh", "sim25-tmux-placement.sh",
         "patch-2026-11-24-tmux-placement.py",
         "push-2026-11-24-tmux-placement.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/tmux-placement-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "fix: placement copies config/, tmux check can never pass otherwise (2026-11-24)\n\nUpdate to 2cdc33c7 died at placement verification, exit 1: missing config/tmux/tmux.conf. Root cause: the Learn fix copied config/tmux into the fork and verified $HEXCIRI_PATH/config/tmux/tmux.conf, but placement only copies shell/default/themes/bin/install/icons to /usr/share/hexciri, never config/, so that path can never exist. Tmux was just the first die; chromium-flags.conf / alacritty / ghostty, checked right after, would have died in turn, same cause. Fix: placement cp line gains $FORK_OUT/config (already curated by copy_subsets, no omarchy-named files, no foot/herdr clutter), and tmux.conf is placed as a user file like kitty.conf so tmux itself loads the Hexciri config on start. The die happened after rm -rf + cp -a of the new tree but before hexciri-update-restart, so the shell never restarted; a successful re-run reaches that step, which is the likely heal for Super+Space / Super+Alt+Space. sim25 22/22, same placement simulation fails on the unpatched file. bash -n clean.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
