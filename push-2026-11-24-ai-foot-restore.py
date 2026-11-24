#!/usr/bin/env python3
"""Push the AI + Foot correction to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim24-ai-foot-restore.sh,
patch-2026-11-24-ai-foot-restore.py, push-2026-11-24-ai-foot-restore.py.
Verifies live bytes. Pushes from /tmp/ai-foot-push (separate source dir),
NOT from ~/workspace/hexiri-2.0.
Refuses to push if live nyx HEAD is no longer 6e48f01 (rebased 2026-11-24
15:29 MST onto tmux 6e29d3d4 + binds 6e48f01 after Devi's 'push it all';
earlier base 2cdc33c7 would clobber them).
Operator steps (NOT done by this script): copy the patched install.sh
from /tmp/ai-foot-live/install.sh to /tmp/ai-foot-push/v2/install.sh
after patch + sim24 pass, copy the other three files from
~/workspace/hexiri-2.0/ to /tmp/ai-foot-push/, then run this script.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "6e48f018c67c5ff2c18dbb99221a7f0304aae65a"
SRC = "/tmp/ai-foot-push"

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

paths = ["v2/install.sh", "sim24-ai-foot-restore.sh",
         "patch-2026-11-24-ai-foot-restore.py",
         "push-2026-11-24-ai-foot-restore.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/ai-foot-restore-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "menu: restore AI install/remove + Foot option, correct 74fe03b3 drops (2026-11-24)\n\nDevi 14:46 MST: two drops in the 74fe03b3 full Install/Remove restore were wrong. (1) AI install/remove: Devi never said no Agent options, he just prefers opencode. Restore Install > AI (amp, antigravity, chatgpt, claude, grok-bot, hermes, lm-studio, ollama, openclaw, perplexity, t3-code) and Remove > AI (same 11), with backing bins install-ai-*, remove-ai-*, install-hermes-cli, install-openclaw-cli, install-t3code-app, openclaw-onboard. Herdr still out (no bin, no row). Opencode stays the pacman default, no account prompt. (2) Foot: restore Install > Terminal > Foot as an option only, Kitty stays default (default terminal, dock pin, keybinds). Foot leaves the trim list: trim-bloat ran at install and on every post-update hook, so it would have uninstalled a user-chosen Foot on the next update. Foot is still not installed by default (no package list). Upstream has no remove.terminal.* subtree, so Foot removes via Remove > Package. Hard defaults combed: no folio/nautilus/herdr/docker in any restored bin. Rebased onto 6e48f01: tmux placement fix (6e29d3d4) and binds chain guard (6e48f01) preserved, Learn menu fix (2cdc33c7) preserved: tmux config, learn.zed/fish/kitty/quickshell. Sim harness fix: simwork/sim7.sh now defines binds_chain_ok verbatim (6e48f01 added the guard call but not the sim definition). sim24 passes, same checks fail on the unpatched file. bash -n clean.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
