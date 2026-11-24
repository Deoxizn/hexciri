#!/usr/bin/env python3
"""Push the Maple Mono NF CN font-list fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim26-maple-mono-nf.sh,
patch-2026-11-24-maple-mono-nf.py, push-2026-11-24-maple-mono-nf.py.
Pushes from /tmp/maple-push (separate source dir), NOT from
~/workspace/hexiri-2.0, because sibling agents (noise/binds) may be
editing ~/workspace/hexiri-2.0/v2/install.sh concurrently; the
patched install.sh was built in /tmp/maple-live from live HEAD 5135dc1d.
Refuses to push if live nyx HEAD is no longer 5135dc1d.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "5135dc1dac60200358d2ac1d6039b3cc55f4df82"
SRC = "/tmp/maple-push"

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

paths = ["v2/install.sh", "sim26-maple-mono-nf.sh",
         "patch-2026-11-24-maple-mono-nf.py",
         "push-2026-11-24-maple-mono-nf.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/maple-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "fix: list dual-width fonts so Maple Mono NF CN shows in Appearance > Font (PR #16025, 2026-11-24)\n\nRoot cause (Devi, confirmed with real fontconfig runs on the v7.9 files): the font picker lists hexciri-font-list, which asked only for spacing=100 (pure monospace). Maple Mono NF CN reports spacing=90 (dual-width: Latin one cell, CJK two), so it was silently filtered out even when installed. Upstream PR #16025 (open, branch maple-mono-font) fixes omarchy-font-list to query both spacings; applied here as a fork patch, pin stays 94a8c3c. Spacing was also the cleared hunch from the first report: plain Maple Mono NF is spacing=100 and already passed the filter.\n\nAlso in this push: (1) hexciri-font-set writes a second fonts.conf match block for JetBrainsMono Nerd Font, because 50-omarchy.conf (leftover in /etc/fonts/conf.d/) assigns monospace to it before the user rule's monospace test can fire, so the menu never showed the chosen font as current; a fonts.conf repair step rewrites existing single-block files on update, keeping the chosen family. (2) AUR step installs maplemono-nf (7.9-1; there is no ttf-maple-mono-nf); maplemono-nf-cn is NOT auto-installed (16 TTFs, 320 MiB, per the PR; Devi already has it). (3) Install > Style > Font > Maple Mono CN row, the PR's row renamed, installing via yay because hexciri-pkg-add is pacman-only and maplemono-nf-cn is AUR-only in Hexciri (the PR depends on omarchy-pkgs#1341, which Hexciri does not have); plus the i18n label. sim26 52/52: fork pipeline verbatim, real-CN functional test (patched list offers Maple Mono NF CN, unpatched omits it), font-set/repair end-to-end with discriminating baselines, idempotent re-run. bash -n clean.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
