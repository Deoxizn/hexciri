#!/usr/bin/env python3
"""Fix tmux placement failure, 2026-11-24 (Devi: hexciri update to 2cdc33c7
failed at placement verification, exit 1, Super+Space / Super+Alt+Space
then broken).

Root cause, proven against live nyx 2cdc33c7:
- Learn fix (2cdc33c7) copied config/tmux into the FORK (FORK_OUT/config/
  tmux/tmux.conf) and added a placement check for
  $HEXCIRI_PATH/config/tmux/tmux.conf.
- Placement (step "Placing forked tree") copies ONLY shell, default,
  themes, bin, install, icons (+ logo/icon txt) to /usr/share/hexciri.
  It NEVER copies config/. So $HEXCIRI_PATH/config/tmux/tmux.conf can
  never exist, and the check dies on every update. Tmux was just the
  first die: the next three checks in the same block
  ($HEXCIRI_PATH/config/chromium-flags.conf, config/alacritty/,
  config/ghostty/) would have died in turn, same cause.
- Upstream bin/omarchy-menu-tmux-keybindings falls back to
  $OMARCHY_PATH/config/tmux/tmux.conf (= $HEXCIRI_PATH/config/tmux/
  tmux.conf) when ~/.config/tmux/tmux.conf is absent, so that path
  must really exist in the placed tree, not just in the fork.
- Binds: the die happened AFTER rm -rf /usr/share/hexciri + cp -a of
  the new tree, but BEFORE the post-placement steps and before
  hexciri-update-restart, so the update aborted with a new tree in
  place and the shell never restarted. A successful re-run (this fix)
  reaches hexciri-update-restart, which restarts the shell and reloads
  Hyprland config; if Super+Space / Super+Alt+Space are still dead
  after that, it is a separate binds bug (separate agent investigating).

Fix, in v2/install.sh only, on live nyx 2cdc33c7:
1. Placement cp line gains "$FORK_OUT/config" (FORK_OUT/config is
   already curated: only the copy_subsets subsets land there - hypr,
   kitty, tmux, alacritty, ghostty, chromium-flags.conf, shell.json -
   no omarchy-named files, no foot/herdr/obsidian clutter).
2. Place tmux.conf as a user file (place_user_file, same pattern as
   kitty.conf, re-run preserves the user's file) so tmux itself loads
   the Hexciri config on start, not just the Learn keybindings display.
Works on /tmp/tmux-live/v2/install.sh (live nyx 2cdc33c7 copy), NOT the
shared ~/workspace/hexiri-2.0/v2/install.sh (sibling agents may be
editing it concurrently, and the AI/Foot agent is blocked awaiting a
go-ahead, not editing).
"""
import sys

P = "/tmp/tmux-live/v2/install.sh"
s = open(P, encoding="utf-8").read()
orig = s

def rep(old, new, what):
    global s
    assert s.count(old) == 1, f"anchor not unique/found: {what} (count={s.count(old)})"
    s = s.replace(old, new)
    print("patched:", what)

# 1. Placement: copy config/ to /usr/share/hexciri, next to the other
# forked trees. Without this, $HEXCIRI_PATH/config/* can never exist.
rep(
    '''sudo cp -a "$FORK_OUT/shell" "$FORK_OUT/default" "$FORK_OUT/themes" "$FORK_OUT/bin" "$FORK_OUT/install" "$FORK_OUT/icons" "$HEXCIRI_PATH/"''',
    '''sudo cp -a "$FORK_OUT/shell" "$FORK_OUT/default" "$FORK_OUT/themes" "$FORK_OUT/bin" "$FORK_OUT/install" "$FORK_OUT/icons" "$FORK_OUT/config" "$HEXCIRI_PATH/"
# config/ was missing from the placement copy (2026-11-24): the Learn
# fix copied config/tmux into the fork and verified
# $HEXCIRI_PATH/config/tmux/tmux.conf, but placement never copied
# config/ at all, so that check died on every update. Same for
# chromium-flags.conf / alacritty / ghostty, checked right after it.
# FORK_OUT/config is already curated (copy_subsets only), no
# omarchy-named files, no foot/herdr/obsidian clutter.''',
    "placement copies config/",
)

rep(
    '''info "Installed: $HEXCIRI_PATH/shell, $HEXCIRI_PATH/default, $HEXCIRI_PATH/themes, $HEXCIRI_PATH/bin, $HEXCIRI_PATH/install (browser-policy helpers), $HEXCIRI_PATH/icons, $HEXCIRI_PATH/logo.txt, $HEXCIRI_PATH/icon.txt"''',
    '''info "Installed: $HEXCIRI_PATH/shell, $HEXCIRI_PATH/default, $HEXCIRI_PATH/themes, $HEXCIRI_PATH/bin, $HEXCIRI_PATH/install (browser-policy helpers), $HEXCIRI_PATH/icons, $HEXCIRI_PATH/config, $HEXCIRI_PATH/logo.txt, $HEXCIRI_PATH/icon.txt"''',
    "placement info line mentions config/",
)

# 2. User tmux config, same pattern as the kitty block just above it:
# place_user_file preserves the user's file on a re-run, backs it up
# on a fresh install with a pre-existing file.
rep(
    '''# Env files: HEXCIRI_PATH and PATH, for logins and uwsm sessions (sudo steps)''',
    '''# Tmux config: upstream config/tmux/tmux.conf is the fallback
# hexciri-menu-tmux-keybindings reads, but tmux itself only loads
# ~/.config/tmux/tmux.conf on start. Place it like kitty.conf above,
# so Super+Alt+Return actually runs with the Hexciri config, not
# tmux defaults. place_user_file keeps the user's file on a re-run.
if [ -f "$FORK_OUT/config/tmux/tmux.conf" ]; then
  place_user_file "$FORK_OUT/config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  info "Placed: ~/.config/tmux/tmux.conf (Hexciri tmux config)"
else
  warn "config/tmux/tmux.conf not found in fork, tmux will run with defaults and Learn > Tmux falls back to nothing."
fi

# Env files: HEXCIRI_PATH and PATH, for logins and uwsm sessions (sudo steps)''',
    "user tmux.conf placement (like kitty)",
)

assert s != orig
open(P, "w", encoding="utf-8").write(s)
print("OK, patched", P)
