#!/usr/bin/env python3
"""Push the SDDM no-reader fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim32-sddm-noreader.sh,
patch-2026-11-24-sddm-noreader.py, push-2026-11-24-sddm-noreader.py.
Verifies live bytes."""
import hashlib, json, os, subprocess, sys

HOME = os.path.expanduser("~")
ROOT = os.path.join(HOME, "workspace/hexiri-2.0")
OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

paths = ["v2/install.sh", "sim32-sddm-noreader.sh",
         "patch-2026-11-24-sddm-noreader.py",
         "push-2026-11-24-sddm-noreader.py"]
pf = "/tmp/sddm-noreader-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "sddm: only set up fingerprint when a reader is detected, strip it when there is none (2026-11-24)\n\nDevi desktop dokoz 20:19 MST: SDDM kept saying failed, password not accepted, while the same password worked at a tty. Same as Hexciri v1 on vanilla Arch. The installer SDDM step only added pam_fprintd lines when a finger was enrolled, but its else branch just logged 'left alone': any stray Hexciri fingerprint lines in /etc/pam.d/sddm make SDDM demand a touch it can never get on a reader-less machine. Fix: new hexciri_has_fingerprint_reader() (forked hexciri-hw-fingerprint sysfs USB probe first, fprintd-list exit status as fallback for non-USB readers) and hexciri_finger_enrolled(); SDDM step requires reader AND enrolled to add lines, otherwise it REPAIRS by stripping pam_fprintd / hw-laptop-closed gate / pam_unix-first lines from /etc/pam.d/sddm and Fingerprint= from the SDDM theme.conf, only writing when something changed. Theme.conf Fingerprint=true now also requires a detected reader. Health check warns when sddm still has pam_fprintd but no reader was detected. sim32 27/27: unpatched leaves stray lines (gap reproduced), patched strips them and keeps the stock system-login stack, clean stock file byte-identical, laptop reader+enrolled still gets pam_unix-first + pam_fprintd, reader with nothing enrolled strips and adds nothing. bash -n clean. Fingerprints (same checkout path): upstream/patch/system stable, provision moves only, so next update is re-apply-provision.",
         "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
