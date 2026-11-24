#!/usr/bin/env python3
"""Push the Super+Alt+Space menu-empty fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim29-menu-empty.sh,
patch-2026-11-24-menu-empty.py, push-2026-11-24-menu-empty.py.
Built in /tmp/menu-empty-1124 from live HEAD 7cfd163. Refuses to push
if live nyx HEAD has moved (rebase first). Verifies live bytes after
the push with a fresh raw fetch + sha256.
"""
import hashlib, json, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "7cfd163afc5f5d003ba0d5130896f8518938b7c8"
SRC = "/tmp/menu-empty-1124"
EXPECT_SHA = "42815f0058f69f65616fb592d95beb11390a2f401a907e66a356c5ed2678966a"

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

paths = ["v2/install.sh", "sim29-menu-empty.sh",
         "patch-2026-11-24-menu-empty.py",
         "push-2026-11-24-menu-empty.py"]
import os
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())
assert hashlib.sha256(open(os.path.join(SRC, "v2/install.sh"), "rb").read()).hexdigest() == EXPECT_SHA, \
    "patched install.sh sha mismatch, refusing to push"

pf = "/tmp/menu-empty-1124-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "menu: fix empty Super+Alt+Space menu, parse the menu jsonc (2026-11-24)\n\nDevi 15:52 MST: ran update, whole Super+Alt+Space menu gone, just says nothing is there.\n\nRoot cause, proven by forking live HEAD and parsing its menu the way the shell parses it: the cf3bb1a maple row (Install > Style > Font > Maple Mono CN) is the only injected row whose action holds double quotes (hexciri-font-set \"Maple Mono NF CN\"), and its Python literal writes them as \\\" -- which inside a double-quoted Python string collapses to a bare quote. The emitted jsonc line therefore holds bare quotes inside the JSON string value, so MenuModel.js JSON.parse fails on the WHOLE file (line 199, column 248), readMenuJsonc returns null, and a fresh shell after the update has no previous rows, so the menu opens on nothingHere. Why now: updates between cf3bb1a and 7cfd163 kept dying at placement verification (tmux, then applications/foot.desktop), so the broken jsonc never landed; 7cfd163 fixed placement and Devi's update was the first to place it. 7cfd163 changed nothing in the row. Why nothing caught it: every menu check is grep for row presence, and grep sees the row fine; sim28 passed 100% on a menu the shell cannot read.\n\nFix: (1) _maple_row emits escaped quotes (\\\\\\\" in the Python literal), so the jsonc holds \\\" and the shell action still sees \"Maple Mono NF CN\". (2) Fork stage: after every menu write, the audit block parses the forked jsonc exactly like MenuModel.js (full-line // comments + trailing commas stripped, JSON.parse) and requires the 9 root entries + the maple action with its quoted font name; a broken menu dies in the fork, before placement, never live. (3) Placement verification parses the placed jsonc the same way. sim29 30/30: patched fork menu parses (369 entries, 9 roots), verbatim placement snippet parses the placed menu, unpatched fork menu FAILS to parse at line 199 (bug reproduced), terminal-four rows + foot.desktop placement still pass, fork idempotent. bash -n clean. Upstream/provision/system fingerprints stable, patch changed (fresh fork on next update).",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
new = json.loads(json.loads(r.stdout)["result"]["content"][0]["text"])
print("new nyx HEAD:", new["sha"])
print(new["commit"]["message"].split("\n")[0])
assert new["sha"] != BASE_HEAD, "HEAD did not move after push"

# 2. Verify live bytes: fresh raw fetch, sha256 must match the patched file.
import urllib.request
raw = urllib.request.urlopen(
    f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{BRANCH}/v2/install.sh").read()
live_bytes_sha = hashlib.sha256(raw).hexdigest()
print("live v2/install.sh sha256:", live_bytes_sha)
assert live_bytes_sha == EXPECT_SHA, "LIVE BYTES MISMATCH after push"
print("LIVE BYTES VERIFIED")
print("NYX PUSH DONE")
