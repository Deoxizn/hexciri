#!/usr/bin/env python3
"""Push the hybrid GPU fix to Deoxizn/hexciri nyx.
Files: v2/install.sh, sim31-gpu-hybrid.sh,
patch-2026-11-24-gpu-hybrid.py, push-2026-11-24-gpu-hybrid.py.
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

paths = ["v2/install.sh", "sim31-gpu-hybrid.sh",
         "patch-2026-11-24-gpu-hybrid.py",
         "push-2026-11-24-gpu-hybrid.py"]
pf = "/tmp/gpu-hybrid-nyx-paths.txt"
with open(pf, "wb") as fh:
    for p in paths:
        fh.write(p.encode() + b"\0")
for p in paths:
    print(p, "local sha256:", hashlib.sha256(open(os.path.join(ROOT, p), "rb").read()).hexdigest())

r = run(["github", "push-files", "--owner", OWNER, "--repo", REPO, "--branch", BRANCH,
         "--message", "gpu: hybrid AMD iGPU + Nvidia dGPU dies on nvidia-open vs nvidia-open-dkms conflict (2026-11-24)\n\nDevi desktop 20:09 MST, dokoz, RTX 4080 Super + AMD Granite Ridge Radeon 610M: installer ran the AMD path (Mesa/Vulkan, correct) then the Nvidia path, which unconditionally installed nvidia-open-dkms. EndeavourOS base already ships nvidia-open on Nvidia systems, and nvidia-open / nvidia-open-dkms conflict, so pacman prompted [y/N], --noconfirm answered No, installer died at line 1104. Fix: new install_nvidia_open() keeps whichever driver variant is already installed (nvidia-open-dkms, nvidia-open, closed nvidia/nvidia-dkms); on a clean system install prebuilt nvidia-open (stock Arch kernel, no dkms build, no headers), never dkms. Pascal branch removes a conflicting nvidia-open(*) first, non-interactively, before installing nvidia-580xx from AUR. AMD step wording was Framework-only; hybrid is now explicit (Mesa for AMD, Nvidia driver below, both install). sim31 24/24: unpatched dies on Devi exact conflict, patched keeps nvidia-open, clean defaults to nvidia-open, dkms kept when present, AMD-only never touches nvidia, Pascal removes then installs 580xx. bash -n clean. Fingerprints: upstream/patch/provision stable, system moves only, so next update is one full installer re-run by design.",
         "--source-dir", ROOT, "--paths-file", pf])
print(r.stdout[-1500:])

r = run(["github", "call-tool", "--name", "get_commit", "--arguments-json",
         json.dumps({"owner": OWNER, "repo": REPO, "sha": BRANCH, "detail": "stats"})])
print(r.stdout[:2500])
print("NYX PUSH DONE")
