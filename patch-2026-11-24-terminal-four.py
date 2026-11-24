#!/usr/bin/env python3
"""Install > Terminal: four rows + foot.desktop placement fix (2026-11-24).

Devi 15:37 MST: "omarchys install>terminal has: alacritty kitty ghostty
foot, not just the two..." And 15:39 MST, pasted update failure:
  ==> Placing forked tree
  [hexciri] Placed desktop entry: ~/.local/share/applications/foot.desktop
  ...
  ==> Verifying placement
  ERROR: missing: applications/foot.desktop, install-terminal foot
  installs without its desktop entry
  Something went wrong during the update! Failed exit 1.

Root causes, both verified by sim28 against live nyx HEAD cf3bb1a:
1. THE UPDATE KILLER (proven, reproduces Devi's paste exactly):
   the 81356136 AI/Foot correction added a placement check for
   $HEXCIRI_PATH/applications/foot.desktop (install-terminal foot reads
   it at runtime: cp "$HEXCIRI_PATH/applications/foot.desktop"
   ~/.local/share/applications/), but placement (sudo cp -a) copies
   only shell default themes bin install icons config to
   /usr/share/hexciri. applications/ is never placed there: the fork's
   applications/*.desktop files are only placed as USER entries to
   ~/.local/share/applications/ (the "Placed desktop entry" line Devi
   saw). So every update with installer >= 8135613 dies at verification,
   exit 1, after the tree was already replaced, and the shell never
   restarts (same shape as the 6e48f01 tmux/config failure: verification
   died on config/tmux/tmux.conf because placement never copied
   config/). Fix, same pattern as that tmux fix: applications/ joins
   the placement copy. FORK_OUT/applications is curated (copy_subsets
   copies only omarchy-browser, omarchy-terminal, foot .desktop files),
   so no Omarchy web-app clutter lands in /usr/share/hexciri.
2. THE TWO ROWS (fork side, verified NOT a fork bug): the fork pipeline
   on live HEAD emits all four install.terminal.* rows (alacritty,
   foot, ghostty, kitty) with backing bins (hexciri-install-terminal,
   hexciri-launch-floating-terminal-with-presentation, hexciri-pkg-present)
   and data (config/alacritty, config/ghostty, config/foot,
   default/alacritty/Alacritty.desktop, applications/foot.desktop), and
   the trim list contains none of the four terminals (foot left the trim
   in 8135613; alacritty/ghostty were never in it). The menu shell
   re-reads the jsonc live (FileView watchChanges) and lists disabled
   rows dimmed, so with a successful update the four rows show. The
   visible "two" is the stale menu left by the aborting update: the
   verification death aborts before the shell restart, so the menu
   Devi sees is from before the restore landed. No audit change needed;
   the gap this patch closes is that placement verification only
   checked '"install.terminal"' + '"install.terminal.foot"' and never
   the alacritty/ghostty/kitty rows, so a dropped terminal row would
   have passed sim unnoticed. All four rows are placement-checked now,
   plus the four desktop_id arms in the placed install-terminal bin.

Kitty stays default everywhere (default terminal, dock pin, keybinds,
setup default). Foot is an option only. Alacritty/Ghostty are install
options only, not installed by default (in no package list).

Base: live nyx HEAD ecb2a7e64c66102b4a88ad09b8758b90e099e6ee (font
Maple reinstall fix, rebased 2026-11-24 after wallcraft/theme-sync
604300c2 + font cf3bb1a; earlier base cf3bb1a3), install.sh sha256
4311a6811d5d3e3306598639e9598a49a2671704930d6b21dfd7a1bcfe4b78b7.
Works on MENU_INSTALL_PATH (default /tmp/term-fix/install.sh), NOT on
the shared ~/workspace/hexiri-2.0/v2/install.sh: wallcraft + font agents
run concurrently and that file is shared.
"""
import hashlib
import os

P = os.environ.get("MENU_INSTALL_PATH", "/tmp/term-fix/install.sh")
BASE_SHA = "4311a6811d5d3e3306598639e9598a49a2671704930d6b21dfd7a1bcfe4b78b7"

data = open(P, "rb").read()
assert hashlib.sha256(data).hexdigest() == BASE_SHA, \
    f"install.sh is not live nyx HEAD cf3bb1a ({hashlib.sha256(data).hexdigest()}), refusing to patch"
s = data.decode()
orig = s

def rep(old, new, count=1):
    global s
    assert s.count(old) == count, f"anchor not found exactly {count}x: {old[:100]!r} (found {s.count(old)})"
    s = s.replace(old, new, 1)

# 1. Placement: applications/ joins the copy to /usr/share/hexciri.
# Same shape as the config/ tmux fix directly above it: the 81356136
# verification checks $HEXCIRI_PATH/applications/foot.desktop and
# install-terminal foot reads it at runtime, but placement never copied
# applications/ at all, so every update since died at verification.
rep('sudo cp -a "$FORK_OUT/shell" "$FORK_OUT/default" "$FORK_OUT/themes" "$FORK_OUT/bin" "$FORK_OUT/install" "$FORK_OUT/icons" "$FORK_OUT/config" "$HEXCIRI_PATH/"',
    'sudo cp -a "$FORK_OUT/shell" "$FORK_OUT/default" "$FORK_OUT/themes" "$FORK_OUT/bin" "$FORK_OUT/install" "$FORK_OUT/icons" "$FORK_OUT/config" "$FORK_OUT/applications" "$HEXCIRI_PATH/"')
rep("""# icons/ is required (copy_subset dies if upstream lacks it), but
# logo.txt / icon.txt are optional in copy_subsets (warn only), so""",
"""# applications/ was missing from the placement copy (2026-11-24, Devi:
# update died at "missing: applications/foot.desktop"): the 81356136
# verification checks $HEXCIRI_PATH/applications/foot.desktop and
# install-terminal foot copies it from there at runtime, but placement
# only ever put the fork's applications/*.desktop files in
# ~/.local/share/applications/ as user entries, never in the placed
# tree, so the check died on every update since. Same fix as config/
# in the tmux placement fix above. FORK_OUT/applications is already
# curated (copy_subsets copies only omarchy-browser, omarchy-terminal
# and foot .desktop files), no Omarchy web-app clutter.
# icons/ is required (copy_subset dies if upstream lacks it), but
# logo.txt / icon.txt are optional in copy_subsets (warn only), so""")

# 2. Stale comment on the user-entry loop: it already places foot.desktop
# too (the "Placed desktop entry" line in Devi's paste), not only the two
# wrappers. The loop itself is unchanged.
rep("""# Browser + terminal desktop entries: upstream applications/ ships
# omarchy-browser.desktop and omarchy-terminal.desktop, renamed to
# hexciri-*.desktop by the fork. They are the default-browser / default-
# terminal launchers (and the dock's stand-ins for WebBrowser /
# TerminalEmulator windows), so they are placed even though they are NOT
# dock pins: the pinned list is brave-origin / kitty directly, and pinning
# these wrappers too would duplicate both. Only these two are placed: the
# other applications/*.desktop files are Omarchy web apps (ChatGPT, Herdr,
# Discord, ...) and AI/out-of-scope entries.""",
"""# Browser + terminal desktop entries: upstream applications/ ships
# omarchy-browser.desktop and omarchy-terminal.desktop, renamed to
# hexciri-*.desktop by the fork. They are the default-browser / default-
# terminal launchers (and the dock's stand-ins for WebBrowser /
# TerminalEmulator windows), so they are placed even though they are NOT
# dock pins: the pinned list is brave-origin / kitty directly, and pinning
# these wrappers too would duplicate both. Plus foot.desktop (2026-11-24):
# install-terminal foot installs it as the Foot desktop entry, so it is
# placed as a user entry here too. Only these three are placed: the other
# applications/*.desktop files are Omarchy web apps (ChatGPT, Herdr,
# Discord, ...) and AI/out-of-scope entries.""")

# 3. Placement verification: all four terminal rows, not just the header
# + foot. The sim gap that let "only two terminals" go unverified: the
# row list never checked alacritty/ghostty/kitty individually.
rep("""for _row in '"install.browser"' '"install.terminal"' '"install.terminal.foot"' '"install.ai"'""",
    """for _row in '"install.browser"' '"install.terminal"' '"install.terminal.alacritty"' '"install.terminal.kitty"' '"install.terminal.ghostty"' '"install.terminal.foot"' '"install.ai"'""")

# 4. Placed install-terminal must map all four terminals to a desktop
# entry, or the row installs the package and then has no entry/config
# to copy (ghostty uses the shipped com.mitchellh.ghostty.desktop id
# and needs no custom copy; the other three copy from the placed tree).
rep("""[ -f "$HEXCIRI_PATH/applications/foot.desktop" ] || die "missing: applications/foot.desktop, install-terminal foot installs without its desktop entry\"""",
"""[ -f "$HEXCIRI_PATH/applications/foot.desktop" ] || die "missing: applications/foot.desktop, install-terminal foot installs without its desktop entry"
# Install > Terminal is four rows (2026-11-24, Devi: alacritty, kitty,
# ghostty, foot, not just two): the placed install-terminal must map
# every one to a desktop entry, or its row installs the package and
# then copies nothing. Ghostty needs no custom desktop file (it uses
# the shipped com.mitchellh.ghostty.desktop id); the other three copy
# theirs from the placed tree, which is why applications/ is placed.
for _term in alacritty foot ghostty kitty; do
  grep -q "^$_term) desktop_id=" "$HEXCIRI_PATH/bin/hexciri-install-terminal" || die "install-terminal has no desktop entry for $_term, Install > Terminal > $_term installs a terminal with no desktop entry"
done
unset _term""")

# 5. Summary item 21: record the placement fix + four-row check.
rep("install-terminal foot copies config/foot + applications/foot.desktop.",
    "install-terminal foot copies config/foot + applications/foot.desktop. Install > Terminal is four rows now (Alacritty, Kitty, Ghostty, Foot, Kitty stays default): the 81356136 Foot verification checked $HEXCIRI_PATH/applications/foot.desktop but placement never copied applications/ there, so every update since died at verification and the shell never restarted; applications/ joins the placement copy (same as config/ in the tmux fix, curated to the three desktop files only), and placement now checks all four terminal rows plus the four desktop_id arms in install-terminal.")

assert s != orig
with open(P, "w") as f:
    f.write(s)
print("patched", P)
print("new sha256:", hashlib.sha256(s.encode()).hexdigest())
print("lines:", s.count("\n"))
