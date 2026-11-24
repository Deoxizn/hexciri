#!/usr/bin/env python3
"""Push the Install > Terminal four-rows + foot.desktop placement fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim28-terminal-four.sh,
patch-2026-11-24-terminal-four.py, push-2026-11-24-terminal-four.py.
Verifies live bytes. Pushes from /tmp/term-fix/push (separate source dir),
NOT from ~/workspace/hexiri-2.0.
Refuses to push if live nyx HEAD is no longer ecb2a7e (rebased 2026-11-24
onto wallcraft/theme-sync 604300c2 + font Maple reinstall ecb2a7e after
Devi's 'push it all'; earlier base cf3bb1a3 would clobber them).
Operator steps (NOT done by this script): copy the patched install.sh
from /tmp/term-fix/install.sh to /tmp/term-fix/push/v2/install.sh
after patch + sim28 pass, copy the other three files from /tmp/term-fix/
to /tmp/term-fix/push/, then run this script.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "ecb2a7e64c66102b4a88ad09b8758b90e099e6ee"
SRC = "/tmp/term-fix/push"
GH = "/opt/hatch/bin/github"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

# 1. Live HEAD must still be the base this patch was built on.
r = run([GH, "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
live = json.loads(r.stdout)["result"]["content"][0]["text"]
live_sha = json.loads(live)["sha"]
assert live_sha == BASE_HEAD, f"live nyx HEAD moved: {live_sha}, refusing to push (rebase first)"
print("live nyx HEAD is still", BASE_HEAD)

paths = ["v2/install.sh", "sim28-terminal-four.sh",
         "patch-2026-11-24-terminal-four.py",
         "push-2026-11-24-terminal-four.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/term-fix/push-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run([GH, "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "menu: Install > Terminal four rows + foot.desktop placement fix (2026-11-24)\n\nDevi 15:37 MST: upstream Install > Terminal has Alacritty, Kitty, Ghostty, Foot, not just two. And 15:39 MST, pasted update failure: 'ERROR: missing: applications/foot.desktop, install-terminal foot installs without its desktop entry', update exit 1.\n\nRoot causes, sim28 vs live HEAD ecb2a7e: (1) THE UPDATE KILLER: the 81356136 Foot correction added a placement check for $HEXCIRI_PATH/applications/foot.desktop (install-terminal foot reads it at runtime), but placement copied only shell/default/themes/bin/install/icons/config to /usr/share/hexciri, never applications/ (the fork's applications/*.desktop files only ever landed as user entries in ~/.local/share/applications/), so every update since died at verification after the tree was replaced, and the shell never restarted. Fix, same pattern as the config/ tmux fix: applications/ joins the placement copy (FORK_OUT/applications is curated to browser/terminal/foot only, no web-app clutter). (2) THE TWO ROWS: the fork pipeline already emits all four install.terminal.* rows with backing bins/data, trim removes none of them, and the menu re-reads the jsonc live and lists disabled rows dimmed, so the visible two were the stale menu left by the aborting update, not a fork bug; no audit change needed. The gap closed here is that placement verification only checked the header + foot rows and never alacritty/ghostty/kitty individually, so all four rows plus the four desktop_id arms in install-terminal are placement-checked now. Kitty stays default everywhere; Foot/Alacritty/Ghostty are install options only, not installed by default. Rebased onto wallcraft/theme-sync 604300c2 + font Maple reinstall ecb2a7e, nothing of either clobbered. sim28 58/58 (fork pipeline verbatim, placement emulation with the patched cp list, verification lines verbatim, negative controls reproduce Devi's error on the unpatched file, idempotent re-run). bash -n clean.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run([GH, "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
