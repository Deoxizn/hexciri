#!/usr/bin/env python3
"""Fix foot.desktop stray entry, round 2 (Devi 2026-11-24 21:21 MST, desktop dokoz).

"foot desktop.file/app is still there... in app launcher"

Root cause, proven from GitHub history, not guessed:
f3c6b59c (2026-11-24 20:33) fixed this exact bug: placement loop skipped
foot.desktop unless `command -v foot`, NoDisplay became wrappers-only,
and a trim repair removed a stray plain-Exec=foot foot.desktop when
foot is absent. a1e97b06 (SDDM empty-username, 2026-11-24 20:36) was
rebased onto a STALE pre-f3c6b59c base and pushed: its diff deletes
both the loop skip and the trim repair, reverting f3c6b59c outright,
while its report claimed "Foot fix intact". b56c769a (xdg-terminal-exec)
was based on a1e97b06, so live nyx b56c769a still has the reverted
loop ("Plus foot.desktop ... placed as a user entry here too. Only
these three are placed") and no repair at all. Every update since
20:36 has re-placed foot.desktop into ~/.local/share/applications/
on every run, and the repair that would remove it never existed.
NoDisplay did not save it: f3c6b59c already noted the grid lists the
entry anyway.

Fix: re-apply f3c6b59c verbatim, plus one hardening f3c6b59c lacked:
its repair lived ONLY in trim, which runs in full + provision-only
mode and is SKIPPED in --re-apply (fork-patch) mode, while the
placement loop runs in full + re-apply and is skipped in
provision-only mode. So add the same repair immediately after the
placement loop too. Together the two repairs cover all three modes:
full (both), re-apply (loop repair), provision-only (trim repair).
Light-sync runs no installer at all, so it cannot re-place foot
either; the stray is cleaned on the next non-light-sync update,
which this change forces because the trim edit moves the provision
fingerprint (next update = re-apply-provision).

Also add a health-check warn: foot absent but a foot.desktop user
entry exists -> warn, so a future clobber shows up in the log
instead of silently returning to the grid. Health edits move no
fingerprint (provision range ends at the Health header), so the
warn alone would never trigger a run; the trim repair is the trigger.
"""
import sys

PATH = "/tmp/footfix/work/v2/install.sh"
src = open(PATH, encoding="utf-8").read()

# 1. Placement loop: skip foot.desktop unless foot is installed.
OLD = """# these wrappers too would duplicate both. Plus foot.desktop (2026-11-24):
# install-terminal foot installs it as the Foot desktop entry, so it is
# placed as a user entry here too. Only these three are placed: the other
# applications/*.desktop files are Omarchy web apps (ChatGPT, Herdr,
# Discord, ...) and AI/out-of-scope entries.
mkdir -p "$HOME/.local/share/applications"
for desk_file in "$FORK_OUT"/applications/*.desktop; do
  [ -e "$desk_file" ] || continue
  place_user_file "$desk_file" "$HOME/.local/share/applications/$(basename "$desk_file")"
"""
NEW = """# these wrappers too would duplicate both. Only these two are placed:
# the other applications/*.desktop files are Omarchy web apps (ChatGPT,
# Herdr, Discord, ...) and AI/out-of-scope entries.
# foot.desktop is deliberately NOT placed here (2026-11-24, Devi:
# pacman -Q | grep foot came back blank, only the desktop file was
# there, Foot looked installed on top of Kitty). It lives only in
# /usr/share/hexciri/applications/ as install-terminal foot's source;
# install-terminal foot copies it to ~/.local/share/applications/
# itself, at the moment it installs the foot package, so a Foot entry
# appears only when Foot is actually installed.
# 2026-11-24 21:21: this skip was in f3c6b59c and was silently reverted
# by a1e97b06 (SDDM fix rebased on a stale pre-f3c6b59c base); re-applied
# here, do not rebase this file from a base older than f3c6b59c.
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

# 2. NoDisplay is wrappers-only (a real installed Foot stays visible).
OLD_ND = """  if ! grep -q '^NoDisplay=' "$HOME/.local/share/applications/$(basename "$desk_file")"; then
    printf 'NoDisplay=true\\n' >> "$HOME/.local/share/applications/$(basename "$desk_file")"
  fi
  info "Placed desktop entry: $HOME/.local/share/applications/$(basename "$desk_file") (NoDisplay, wrapper only)"
"""
NEW_ND = """  # Foot is a real app, not a wrapper: when it is installed it stays
  # visible, so NoDisplay is wrappers-only (2026-11-24).
  if [ "$(basename "$desk_file")" != "foot.desktop" ] && ! grep -q '^NoDisplay=' "$HOME/.local/share/applications/$(basename "$desk_file")"; then
    printf 'NoDisplay=true\\n' >> "$HOME/.local/share/applications/$(basename "$desk_file")"
  fi
  info "Placed desktop entry: $HOME/.local/share/applications/$(basename "$desk_file") (NoDisplay, wrapper only)"
"""
assert src.count(OLD_ND) == 1, f"NoDisplay anchor found {src.count(OLD_ND)} times"
src = src.replace(OLD_ND, NEW_ND)

# 3. Repair right after the placement loop (runs in full + --re-apply;
# trim repair below runs in full + --re-apply-provision; together they
# cover every installer mode, which f3c6b59c's trim-only repair did not).
OLD_AFTER = """  info "Placed desktop entry: $HOME/.local/share/applications/$(basename "$desk_file") (NoDisplay, wrapper only)"
done

# hexciri CLI on PATH everywhere, not just login shells: /usr/local/bin is
"""
NEW_AFTER = """  info "Placed desktop entry: $HOME/.local/share/applications/$(basename "$desk_file") (NoDisplay, wrapper only)"
done
# Stray Foot entry repair, loop side (2026-11-24 21:21, re-applied f3c6b59c
# plus this second site): earlier installs placed foot.desktop as a user
# entry on every run, so a Foot launcher showed in the grid for a terminal
# that does not exist. Remove it when Foot is not installed; only remove
# the Hexciri-placed copy (plain Exec=foot), never a user-customised entry.
# This site runs in full + --re-apply mode; the trim-site repair below
# runs in full + --re-apply-provision mode. Together they cover every
# installer mode. If Foot IS installed, leave it visible.
if ! command -v foot >/dev/null 2>&1 && [ -f "$HOME/.local/share/applications/foot.desktop" ] && grep -q '^Exec=foot$' "$HOME/.local/share/applications/foot.desktop"; then
  rm -f "$HOME/.local/share/applications/foot.desktop" "$HOME/.local/share/applications/foot.desktop.hexciri.new"
  info "Removed stray desktop entry: foot.desktop (Foot is not installed)"
fi

# hexciri CLI on PATH everywhere, not just login shells: /usr/local/bin is
"""
assert src.count(OLD_AFTER) == 1, f"after-loop anchor found {src.count(OLD_AFTER)} times"
src = src.replace(OLD_AFTER, NEW_AFTER)

# 4. Trim repair (re-apply f3c6b59c verbatim; this edit moves the
# provision fingerprint, so the next update is --re-apply-provision
# and the repair actually runs on Devi's desktop).
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
# 2026-11-24 21:21: re-applied after a1e97b06 silently reverted f3c6b59c;
# a second repair site after the placement loop (above) now covers
# --re-apply mode too, which trim skips.
if ! command -v foot >/dev/null 2>&1 && [ -f "$HOME/.local/share/applications/foot.desktop" ] && grep -q '^Exec=foot$' "$HOME/.local/share/applications/foot.desktop"; then
  rm -f "$HOME/.local/share/applications/foot.desktop" "$HOME/.local/share/applications/foot.desktop.hexciri.new"
  info "Removed stray desktop entry: foot.desktop (Foot is not installed)"
fi
"""
assert src.count(OLD_TRIM) == 1, f"trim anchor found {src.count(OLD_TRIM)} times"
src = src.replace(OLD_TRIM, NEW_TRIM)

# 5. Health check: warn if a foot.desktop user entry exists without foot.
OLD_HC = """command -v kitty >/dev/null 2>&1 && hc_info "  terminal: kitty present" || warn "  terminal: kitty NOT installed, terminal binds fall back to xdg-terminal-exec"
"""
NEW_HC = """command -v kitty >/dev/null 2>&1 && hc_info "  terminal: kitty present" || warn "  terminal: kitty NOT installed, terminal binds fall back to xdg-terminal-exec"
if ! command -v foot >/dev/null 2>&1 && [ -f "$HOME/.local/share/applications/foot.desktop" ]; then warn "  foot entry: ~/.local/share/applications/foot.desktop exists but foot is not installed, Foot will show in the app grid (run: rm ~/.local/share/applications/foot.desktop)"; fi
"""
assert src.count(OLD_HC) == 1, f"health anchor found {src.count(OLD_HC)} times"
src = src.replace(OLD_HC, NEW_HC)

open(PATH, "w", encoding="utf-8").write(src)
print("patched OK")
