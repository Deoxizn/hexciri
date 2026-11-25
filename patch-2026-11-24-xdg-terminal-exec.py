#!/usr/bin/env python3
"""Patch live nyx a1e97b06: install xdg-terminal-exec from Arch Extra stable.

Devi desktop dokoz 2026-11-24 20:36 MST: app grid showed
  App failure / Error: Command not found: "xdg-terminal-exec"
Root cause: installer comment (lines 722-735) said xdg-terminal-exec is
NOT in stable extra, only extra-testing 0.14.4-1, so it was deliberately
never installed. That was stale: live archlinux.org 2026-11-25 03:38 UTC
shows xdg-terminal-exec 0.14.4-1 in Repository: Extra (stable), build
date 2026-10-28. Devi 20:37 MST: "I think the xdg terminal thing is in
testing repo on EOS it said on install" - right, it WAS testing, it has
since moved to stable Extra; no testing repo (Arch extra-testing or EOS
testing) needs enabling, plain `pacman -S xdg-terminal-exec` works.
Without the binary, every terminal-with-args launch dies: launch-terminal
with args, launch-tui, launch-floating-terminal-with-presentation, TUI
desktop entries (Exec=xdg-terminal-exec --app-id=... -e ...), Quickshell
Terminal=true entries, menu BarWidget right-click run("xdg-terminal-exec").
Only plain Super+Return worked, via the xdg-terminals.list fast path.
Fix: add it to CORE_PKGS, replace the stale block with a verify-only
check, add it to v2/hexciri-base.packages. CORE_PKGS is in the system
fingerprint range, so system moves only -> next update is one full
installer re-run by design, then re-apply/light-sync resumes.
"""
import sys

ROOT = "/home/hatch/workspace/hexiri-2.0"
P = f"{ROOT}/v2/install.sh"
s = open(P).read()
orig = s

old_pkgs = "  xdg-user-dirs xdg-utils xorg-xwayland\n"
new_pkgs = ("  xdg-user-dirs xdg-utils xdg-terminal-exec xorg-xwayland # xdg-terminal-exec: Arch Extra stable 0.14.4-1, verified live 2026-11-25 (was extra-testing at install time, Devi 20:37 MST). Every terminal-with-args launch needs it: launch-terminal with args, launch-tui, floating-terminal-with-presentation, TUI desktop entries, Quickshell Terminal=true entries. Without it the grid shows \"App failure: Command not found: xdg-terminal-exec\".\n")
assert s.count(old_pkgs) == 1, "CORE_PKGS xdg line not found exactly once"
s = s.replace(old_pkgs, new_pkgs)

old_block = """# xdg-terminal-exec is NOT in stable extra and NOT in the AUR (only
# extra-testing 0.14.4-1), so it must never go in the pacman CORE_PKGS call
# above, and yay -S xdg-terminal-exec can never succeed: do not try it.
# launch-terminal's fast path (xdg-terminals.list, kitty first) works
# without it, and the binary is usually already present on EndeavourOS.
# If it is missing, enable extra-testing and install it from there; until
# then floating/presentation terminals fall back to the fast path.
if ! command -v xdg-terminal-exec >/dev/null 2>&1; then
  if [ "${IS_RERUN:-0}" = "1" ]; then
    info "xdg-terminal-exec not installed (extra-testing only, expected): terminal launches use the xdg-terminals.list fast path"
  else
    warn "xdg-terminal-exec not installed (only in Arch extra-testing, not AUR), terminal launches use the xdg-terminals.list fast path only. Install later from extra-testing if a floating terminal needs it."
  fi
fi
"""
new_block = """# xdg-terminal-exec is in CORE_PKGS above (Arch Extra stable 0.14.4-1,
# verified live on archlinux.org 2026-11-25; the extra-testing note this
# replaced was stale, it moved to stable Extra). Verify it actually
# landed: a stale mirror can still fail the pacman call above, and
# without the binary every terminal-with-args launch dies with
# "App failure: Command not found: xdg-terminal-exec" (desktop dokoz,
# 2026-11-24). Plain Super+Return still works without it via the
# xdg-terminals.list fast path (kitty first), but launch-tui /
# floating-terminal / TUI entries do not.
if command -v xdg-terminal-exec >/dev/null 2>&1; then
  info "xdg-terminal-exec installed: $(command -v xdg-terminal-exec)"
else
  warn "xdg-terminal-exec NOT installed after Core packages (stale mirror?): terminal-with-args launches will fail, plain Super+Return still works via the xdg-terminals.list fast path. Re-run hexciri update once the mirror syncs."
fi
"""
assert s.count(old_block) == 1, "stale xdg-terminal-exec block not found exactly once"
s = s.replace(old_block, new_block)

assert "extra-testing only, expected" not in s
assert "NOT in stable extra" not in s
open(P, "w").write(s)
print(f"install.sh: {len(orig)} -> {len(s)} bytes")

BP = f"{ROOT}/v2/hexciri-base.packages"
b = open(BP).read()
assert b.count("xdg-utils\n") == 1
b = b.replace("xdg-utils\n", "xdg-utils\nxdg-terminal-exec # Arch Extra stable 0.14.4-1, verified 2026-11-25; every terminal-with-args launch needs it\n", 1)
open(BP, "w").write(b)
print("hexciri-base.packages: xdg-terminal-exec added after xdg-utils")
