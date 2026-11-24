#!/usr/bin/env python3
"""Push the Learn menu rework to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim24-learn-menu.sh,
patch-2026-11-24-learn-menu.py, push-2026-11-24-learn-menu.py.
Pushes from /tmp/learn-push (separate source dir), NOT from
~/workspace/hexiri-2.0, because a sibling agent (AI/Foot restore) may be
editing ~/workspace/hexiri-2.0/v2/install.sh concurrently; the patched
install.sh was built in /tmp/learn-live from live HEAD 74fe03b3.
Refuses to push if live nyx HEAD is no longer 74fe03b3.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "74fe03b3442d3d69beb0bfc18de857a295a32612"
SRC = "/tmp/learn-push"

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

paths = ["v2/install.sh", "sim24-learn-menu.sh",
         "patch-2026-11-24-learn-menu.py",
         "push-2026-11-24-learn-menu.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/learn-menu-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "menu: Learn rework, fix Tmux, add Kitty/Quickshell/Fish/Zed (2026-11-24)\n\nDevi: Learn menu cleanup. Audit of all 9 upstream Learn rows: keybindings / Hexciri / Hyprland / Arch / Bash kept (all live); Tmux row kept but its backing config/tmux/tmux.conf was never copied into the fork, so hexciri-menu-tmux-keybindings died with 'Tmux config not found' even though tmux is in APP_PKGS (copy added, rename pass turns the omarchy-menu-tmux-keybindings bind into hexciri-); Neovim -> Zed (neovim is trimmed in v2, Zed is the default editor); Community dropped (Omarchy Discord invite, Hexciri has no Discord); Fish + Kitty + Quickshell added (interactive shell, default terminal, the shell itself). Health check gains a tmux line so a missing tmux binary shows up instead of being guessed at. Placement verification dies if the tmux config or any new Learn row is missing, and learn.neovim / learn.community are now in the dead-row list. sim24 33/33, same checks fail on the unpatched file. bash -n clean.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
