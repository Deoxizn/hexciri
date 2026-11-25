#!/usr/bin/env python3
"""Fix the patches-refactor update failure (2026-11-24, Devi 16:54 MST).

Root cause, proven against live nyx a812b576:
  v2/patches/apply.sh is mode 100644 in the repo (github push-files does
  not preserve exec bits -- AGENTS.md lesson, same as root install.sh).
  v2/install.sh line 2214 guards it with [ -x "$PATCHES_DIR/apply.sh" ],
  so on every fresh git clone the guard fails and the installer dies with
  "v2/patches/apply.sh not in the installer tree (.../v2/patches)".
  The patches dir IS pulled (git pull brings the whole tree); only the
  +x bit is missing, and nothing needs it: install.sh invokes apply.sh
  via `bash`, and apply.sh invokes each patch via `bash`.

Fix:
  1. install.sh: -x -> -f on the apply.sh guard, with a comment saying
     why (bash-invoked, push-files lands 644). Die message now says
     "missing from" instead of "not in".
  2. v2/hexciri-update-hexciri: after a successful git sync / tarball
     extract, verify v2/patches/apply.sh is present before the installer
     ever forks Omarchy. A missing-patches sync now fails early (and the
     tarball fallback gets a chance) instead of forking 94 MB and then
     dying at the patch step.

Applies to a clone at SRC (default /tmp/patches-apply-fix/patched).
Asserts the live a812b576 anchors; refuses to patch anything else.
"""
import pathlib, sys

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/patches-apply-fix/patched")
INSTALL = SRC / "v2/install.sh"
UPDATER = SRC / "v2/hexciri-update-hexciri"

def must_replace(path, old, new, count=1):
    text = path.read_text()
    n = text.count(old)
    assert n == count, f"{path}: anchor found {n}x, expected {count}x: {old[:90]!r}"
    path.write_text(text.replace(old, new))
    print(f"patched {path.name}: {old[:70]!r} -> {new[:70]!r}")

# --- 1. install.sh guard: -x -> -f ---
old_guard = '''PATCHES_DIR="${HEXCIRI_PATCHES_DIR:-$INSTALLER_DIR/patches}"
if [ -x "$PATCHES_DIR/apply.sh" ]; then'''
new_guard = '''PATCHES_DIR="${HEXCIRI_PATCHES_DIR:-$INSTALLER_DIR/patches}"
# apply.sh is invoked via bash, never exec'd, so -f is the right test,
# not -x: github push-files lands repo files mode 644 (no exec bit),
# and a fresh git clone has apply.sh 644 too. -x died on every update
# with "not in the installer tree" even though the patches dir was
# pulled fine (2026-11-24, Devi 16:54 MST, laptop).
if [ -f "$PATCHES_DIR/apply.sh" ]; then'''
must_replace(INSTALL, old_guard, new_guard)

old_die = '''  die "v2/patches/apply.sh not in the installer tree ($PATCHES_DIR), cannot apply fork patches"'''
new_die = '''  die "v2/patches/apply.sh missing from the installer tree ($PATCHES_DIR), cannot apply fork patches"'''
must_replace(INSTALL, old_die, new_die)

# --- 2. hexciri-update-hexciri: verify patches after sync, before fork ---
old_git = '''  [ -f "$CHECKOUT/v2/install.sh" ] || { detail "cloned tree has no v2/install.sh"; return 1; }'''
new_git = '''  [ -f "$CHECKOUT/v2/install.sh" ] || { detail "cloned tree has no v2/install.sh"; return 1; }
  # Patches must be present before the installer forks Omarchy: a
  # missing v2/patches/apply.sh used to die only at the fork-patch step,
  # after the 94 MB fork (2026-11-24, Devi 16:54 MST). Fail the sync
  # here instead, so the tarball fallback gets a chance.
  [ -f "$CHECKOUT/v2/patches/apply.sh" ] || { detail "cloned tree has no v2/patches/apply.sh"; return 1; }'''
must_replace(UPDATER, old_git, new_git)

old_tar = '''  [ -f "$workdir/$top_dir/v2/install.sh" ] || { rm -rf "$workdir"; detail "extracted tree has no v2/install.sh"; return 1; }'''
new_tar = '''  [ -f "$workdir/$top_dir/v2/install.sh" ] || { rm -rf "$workdir"; detail "extracted tree has no v2/install.sh"; return 1; }
  [ -f "$workdir/$top_dir/v2/patches/apply.sh" ] || { rm -rf "$workdir"; detail "extracted tree has no v2/patches/apply.sh"; return 1; }'''
must_replace(UPDATER, old_tar, new_tar)

print("PATCH OK")
