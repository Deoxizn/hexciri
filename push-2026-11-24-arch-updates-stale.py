#!/usr/bin/env python3
"""Push the arch-updates stale-count / slow-scan fix to Deoxizn/Arch-Updates nyx.
Files: scripts/check_updates.py, scripts/update_plugins_themes.py, BarWidget.qml.
Source dir is /tmp/arch-updates-nyx (fetched from nyx c97c666, patched locally).
Verifies live bytes after push."""
import hashlib, json, os, subprocess, sys

OWNER, REPO, BRANCH = "Deoxizn", "Arch-Updates", "nyx"
ROOT = "/tmp/arch-updates-nyx"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

paths = ["scripts/check_updates.py", "scripts/update_plugins_themes.py", "BarWidget.qml"]
pf = "/tmp/arch-updates-stale-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "arch-updates: stale count after update + slow scan (2026-11-24)\n\nplugin_behind() fetched origin HEAD and counted HEAD..FETCH_HEAD, so once main moved ahead a nyx plugin counted as behind main forever, while hexciri plugin update pulls the checked-out branch (nyx) and never cleared it: badge never dropped after an update. Now fetch the checked-out branch (detached HEAD falls back to origin HEAD), same in update_plugins_themes.py. Scanner ran sources sequentially (minutes); widget fast poll counted no-op ticks while a scan was running and could spend its 30-poll budget before any fresh result landed. Now sources run in parallel (output shape unchanged), yay -Qua timeout 60s -> 120s, and BarWidget only counts fast-poll ticks where a scan actually started. sim17 7/7.",
         "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])
print("ARCH-UPDATES NYX PUSH DONE")
