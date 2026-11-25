#!/usr/bin/env python3
"""Fix foot.desktop stray entry (Devi 2026-11-24 20:26/20:27 MST, desktop dokoz).

Devi: "Also seems foot got installed lm top of kitty. Or just a desktop
file for foot there" -- then confirmed: "Just a desktop file...
Pacman -q | grep foot came back blank". Foot package is NOT installed.

Root cause: the desktop-entry placement loop in v2/install.sh places
EVERY file in FORK_OUT/applications/*.desktop into
~/.local/share/applications/ and appends NoDisplay=true. That includes
foot.desktop, whose only job is to be install-terminal foot's source
(it copies it there itself, at the moment it installs the foot package).
So every install/update dropped a Foot launcher entry for a terminal
that does not exist, and the app grid showed Foot on top of Kitty.
NoDisplay did not save it: the entry still exists as a user file and
the grid lists it.

Fix:
1. Placement loop: skip foot.desktop unless `command -v foot` (Foot
   actually installed). The two wrappers (hexciri-browser /
   hexciri-terminal) are still placed unconditionally.
2. NoDisplay append is wrappers-only: Foot is a real app, so when it
   IS installed its entry must stay visible.
3. Repair: remove a stray Hexciri-placed foot.desktop (plain Exec=foot)
   when foot is not installed, plus a leftover .hexciri.new. This
   lives in the trim section, NOT by the placement loop, on purpose:
   the loop sits in the "Place the forked tree" section, which is in
   NO fingerprint range, so a repair there would light-sync and never
   run on existing machines. Trim is in the provision range, so this
   change moves the provision fingerprint and the next update
   re-applies provision. The placed tree keeps foot.desktop
   (/usr/share/hexciri/applications/), so install-terminal foot keeps
   working.
"""
import sys

PATH = "/home/hatch/workspace/hexiri-2.0/v2/install.sh"
src = open(PATH, encoding="utf-8").read()

OLD = """# Browser + terminal desktop entries: upstream applications/ ships
# omarchy-browser.desktop and omarchy-terminal.desktop, renamed to
# hexciri-*.desktop by the fork. They are the default-browser / default-
# terminal launchers (and the dock's stand-ins for WebBrowser /
# TerminalEmulator windows), so they are placed even though they are NOT
# dock pins: the pinned list is brave-origin / kitty directly, and pinning
# these wrappers too would duplicate both. Plus foot.desktop (2026-11-24):
# install-terminal foot installs it as the Foot desktop entry, so it is
# placed as a user entry here too. Only these three are placed: the other
# applications/*.desktop files are Omarchy web apps (ChatGPT, Herdr,
# Discord, ...) and AI/out-of-scope entries.
mkdir -p "$HOME/.local/share/applications"
for desk_file in "$FORK_OUT"/applications/*.desktop; do
  [ -e "$desk_file" ] || continue
  place_user_file "$desk_file" "$HOME/.local/share/applications/$(basename "$desk_file")"
"""

NEW = """# Browser + terminal desktop entries: upstream applications/ ships
# omarchy-browser.desktop and omarchy-terminal.desktop, renamed to
# hexciri-*.desktop by the fork. They are the default-browser / default-
# terminal launchers (and the dock's stand-ins for WebBrowser /
# TerminalEmulator windows), so they are placed even though they are NOT
# dock pins: the pinned list is brave-origin / kitty directly, and pinning
# these wrappers too would duplicate both. Only these two are placed:
# the other applications/*.desktop files are Omarchy web apps (ChatGPT,
# Herdr, Discord, ...) and AI/out-of-scope entries.
# foot.desktop is deliberately NOT placed here (2026-11-24, Devi:
# pacman -Q | grep foot came back blank, only the desktop file was
# there, Foot looked installed on top of Kitty). It lives only in
# /usr/share/hexciri/applications/ as install-terminal foot's source;
# install-terminal foot copies it to ~/.local/share/applications/
# itself, at the moment it installs the foot package, so a Foot entry
# appears only when Foot is actually installed.
mkdir -p "$HOME/.local/share/applications"
for desk_file in "$FORK_OUT"/applications/*.desktop; do
  [ -e "$desk_file" ] || continue
  if [ "$(basename "$desk_file")" = "foot.desktop" ] && ! command -v foot >/dev/null 2>&1; then
    info "Skipped desktop entry: foot.desktop (Foot is not installed, Kitty is the default terminal)"
    continue
  fi
  place_user_file "$desk_file" "$HOME/.local/share/applications/$(basename "$desk_file")"
"""

assert src.count(OLD) == 1, f"placement loop anchor found {src.count(OLD)} times"
src = src.replace(OLD, NEW)

OLD_ND = """  if ! grep -q '^NoDisplay=' "$HOME/.local/share/applications/$(basename "$desk_file")"; then
    printf 'NoDisplay=true\\n' >> "$HOME/.local/share/applications/$(basename "$desk_file")"
  fi
"""
NEW_ND = """  # Foot is a real app, not a wrapper: when it is installed it stays
  # visible, so NoDisplay is wrappers-only (2026-11-24).
  if [ "$(basename "$desk_file")" != "foot.desktop" ] && ! grep -q '^NoDisplay=' "$HOME/.local/share/applications/$(basename "$desk_file")"; then
    printf 'NoDisplay=true\\n' >> "$HOME/.local/share/applications/$(basename "$desk_file")"
  fi
"""
assert src.count(OLD_ND) == 1, f"NoDisplay anchor found {src.count(OLD_ND)} times"
src = src.replace(OLD_ND, NEW_ND)

OLD_TRIM = """  info "Hidden: YAD settings app entry (NoDisplay override, yad package kept for EOS tools)"
else
  warn "yad-settings.desktop not found, nothing to hide"
fi
"""
NEW_TRIM = """  info "Hidden: YAD settings app entry (NoDisplay override, yad package kept for EOS tools)"
else
  warn "yad-settings.desktop not found, nothing to hide"
fi
# Stray Foot entry repair (2026-11-24, Devi: only the desktop file was
# there, foot package not installed, pacman -Q | grep foot blank).
# Earlier installs placed foot.desktop as a user entry on every run, so
# a Foot launcher showed in the grid for a terminal that does not
# exist. Remove it when Foot is not installed; only remove the
# Hexciri-placed copy (plain Exec=foot), never a user-customised entry.
# If Foot IS installed, leave it visible. This lives in the trim
# section, not by the placement loop, on purpose: the loop sits in the
# "Place the forked tree" section, which is in NO fingerprint range,
# so a repair there would light-sync and never run on existing
# machines. Trim is in the provision range, so this change moves the
# provision fingerprint and the next update re-applies provision.
if ! command -v foot >/dev/null 2>&1 && [ -f "$HOME/.local/share/applications/foot.desktop" ] && grep -q '^Exec=foot$' "$HOME/.local/share/applications/foot.desktop"; then
  rm -f "$HOME/.local/share/applications/foot.desktop" "$HOME/.local/share/applications/foot.desktop.hexciri.new"
  info "Removed stray desktop entry: foot.desktop (Foot is not installed)"
fi
"""
assert src.count(OLD_TRIM) == 1, f"trim anchor found {src.count(OLD_TRIM)} times"
src = src.replace(OLD_TRIM, NEW_TRIM)

open(PATH, "w", encoding="utf-8").write(src)
print("patched v2/install.sh")
