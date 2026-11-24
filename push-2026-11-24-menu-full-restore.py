#!/usr/bin/env python3
"""Push the full Install/Remove menu restore to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim23-menu-full-restore.sh,
patch-2026-11-24-menu-full-restore.py, push-2026-11-24-menu-full-restore.py.
Verifies live bytes. Pushes from /tmp/menu-push (separate source dir), NOT
from ~/workspace/hexiri-2.0, because a sibling agent (minimal re-apply) is
concurrently editing ~/workspace/hexiri-2.0/v2/install.sh; the patched
install.sh was built in /tmp/menu-live2 from live HEAD 92a97d86.
Refuses to push if live nyx HEAD is no longer 92a97d86.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "92a97d86a3cac1fe7928fed74d503c03adcaf480"
SRC = "/tmp/menu-push"

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

paths = ["v2/install.sh", "sim23-menu-full-restore.sh",
         "patch-2026-11-24-menu-full-restore.py",
         "push-2026-11-24-menu-full-restore.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/menu-full-restore-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "menu: restore full Install/Remove, minus Omarchy specifics (2026-11-24)\n\nDevi: full install/remove back, except Omarchy specifics like preinstalls, with hard defaults combed and fixed. The 2026-11-23 audit restored Install/Remove only where a backing bin was already in the fork, and is_allowed_bin deliberately excluded install-service-*, install-terminal-*, install-browser, install-dev-env and install-dictation-*, so those whole subtrees dropped. Restored now, with bins + data files copied: Browser (7), Terminal (alacritty/ghostty/kitty), Editor (vscode/cursor/sublime/helix/vim), Service (12), Development (all but docker-dbs, mise-based), Gaming extras (vibes, xbox-cloud, xbox-controllers, retro-launcher), and Remove Service (5), Development, Dictation (3), Gaming (7), Security fido2/sshd. Still dropped: AI (agents out of scope), Windows + preinstalls (Omarchy-specific), Docker rows, factory-reset (btrfs-only), Foot (Kitty is the Hexciri equivalent), Emacs (dead upstream, calls a bin that does not exist). Hard defaults combed: no folio/nautilus in any restored row or bin; chromium flags extension paths resolve to /usr/share/hexciri/default/chromium/ (copied whole); Tailscale Taildrop unit ExecStart fixed to /usr/share/hexciri/bin and installed/removed by its bins; Setup > Defaults > Dictation picking works again (install-dictation-* back in the fork). Placement verification dies if any restored row, bin, data file or the tailscale unit is missing. sim23 199/199, same checks fail on the unpatched file. bash -n clean.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
