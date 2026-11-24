#!/usr/bin/env python3
"""Push the Maple Mono NF CN reinstall fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, v2/hexciri-font-maple-cn-present,
patch-2026-11-24-maple-reinstall.py, sim27-maple-reinstall.sh,
push-2026-11-24-maple-reinstall.py.
Pushes from /tmp/maple-reinstall (separate source dir), NOT from
~/workspace/hexiri-2.0, because sibling agents (terminal, wallcraft)
may be editing ~/workspace/hexiri-2.0/v2/install.sh concurrently.
Refuses to push if live nyx HEAD is no longer 604300c2 (wallcraft /
theme-sync push); rebase first in that case.
"""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"
BASE_HEAD = "604300c299e71e797c9dd013cdedcefcfd105d40"
SRC = "/tmp/maple-reinstall"

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

paths = ["v2/install.sh", "v2/hexciri-font-maple-cn-present",
         "patch-2026-11-24-maple-reinstall.py", "sim27-maple-reinstall.sh",
         "push-2026-11-24-maple-reinstall.py"]
for p in paths:
    fp = os.path.join(SRC, p)
    assert os.path.isfile(fp), f"missing {fp}"
    print(p, "local sha256:", hashlib.sha256(open(fp, "rb").read()).hexdigest())

pf = "/tmp/maple-reinstall-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "fix: do not reinstall Maple Mono NF CN on update when already installed via AUR (2026-11-24)\n\nRoot cause, proven against live nyx cf3bb1a3 and the real AUR packages: the cf3bb1a3 AUR step's only guard was fc-list | grep 'Maple Mono NF', a family-name/fontconfig-cache check that never asked pacman whether any Maple package was installed, so it fell through to yay whenever fc-list did not list the family in the installer's environment. And maplemono-nf / maplemono-nf-cn are split packages of ONE pkgbase (maplemono, AUR 7.9-1): makepkg downloads ALL 11 source zips whatever split you ask for, including MapleMono-NF-CN.zip (320 MiB), so the step re-fetched CN and installed plain maplemono-nf alongside the CN variant Devi already had. There is also a second AUR name for the same font, maple-mono-nf-cn (own pkgbase), which the menu row's disabled check (hexciri-pkg-present maplemono-nf-cn, one exact package) could not see.\n\nFix: (1) AUR step guard is now pacman -Q first, over every known Maple NF package name (both AUR namings, plain + CN + unhinted); any one installed skips, no yay, no download; fc-list stays as second guard for hand-installed fonts. (2) New repo bin v2/hexciri-font-maple-cn-present (exit 0 if any CN package under either AUR name is installed); Install > Style > Font > Maple Mono CN now uses it as its disabled check. (3) Wiring: bin copied into the fork, hashed in patch fingerprint, light-sync list, placement-verification bin list + menu-row grep. sim27 33/33: fork pipeline verbatim, stubbed pacman/fc-list/yay guard matrix (all four installed variants skip, fc-list-only skips, clean machine installs plain maplemono-nf only, never cn), regression proving the unpatched step runs yay with CN installed but fc-list empty, new-bin exit codes, idempotent re-run. bash -n clean. Rebased onto wallcraft/theme-sync 604300c2, nothing of it clobbered.",
         "--source-dir", SRC, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
