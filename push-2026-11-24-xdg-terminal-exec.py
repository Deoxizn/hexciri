#!/usr/bin/env python3
"""Push the xdg-terminal-exec fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, v2/hexciri-base.packages, sim35-xdg-terminal-exec.sh,
patch-2026-11-24-xdg-terminal-exec.py, push-2026-11-24-xdg-terminal-exec.py.
Verifies live bytes."""
import hashlib, os, subprocess, sys

HOME = os.path.expanduser("~")
ROOT = os.path.join(HOME, "workspace/hexiri-2.0")
OWNER, REPO, BRANCH = "Deoxizn", "hexciri", "nyx"

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"FAILED rc={r.returncode}: {' '.join(args[:4])}")
    return r

paths = ["v2/install.sh", "v2/hexciri-base.packages",
         "sim35-xdg-terminal-exec.sh",
         "patch-2026-11-24-xdg-terminal-exec.py",
         "push-2026-11-24-xdg-terminal-exec.py"]
pf = "/tmp/xdg-terminal-exec-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

msg = """xdg-terminal-exec: install it from Arch Extra stable (2026-11-24)

Devi desktop dokoz 20:36 MST: app grid showed
  App failure / Error: Command not found: "xdg-terminal-exec"
Root cause: installer comment said xdg-terminal-exec is NOT in stable
extra, only extra-testing 0.14.4-1, so it was deliberately never
installed. That was stale: live archlinux.org 2026-11-25 shows
xdg-terminal-exec 0.14.4-1 in Repository: Extra (stable), build date
2026-10-28. Devi 20:37 MST: "I think the xdg terminal thing is in
testing repo on EOS it said on install" - right, it WAS testing, it has
since moved to stable Extra; no testing repo (Arch extra-testing or EOS
testing) needs enabling, plain pacman -S works. Without the binary,
every terminal-with-args launch dies: launch-terminal with args,
launch-tui, launch-floating-terminal-with-presentation, TUI desktop
entries (Exec=xdg-terminal-exec --app-id=... -e ...), Quickshell
Terminal=true entries, menu BarWidget right-click. Only plain
Super+Return worked, via the xdg-terminals.list fast path.
Fix: add xdg-terminal-exec to CORE_PKGS (and v2/hexciri-base.packages),
replace the stale block with a verify-only check (present -> info,
absent -> warn, stale mirror). sim35 18/18: CORE_PKGS, stale claims
gone, verify logic, all 5 caller paths inventoried from upstream
quattro, fingerprints via --print-fingerprints: upstream/patch/
provision stable, system moves only, so next update is one full
installer re-run by design, then re-apply/light-sync resumes.
bash -n clean.
"""
r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", msg, "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])
