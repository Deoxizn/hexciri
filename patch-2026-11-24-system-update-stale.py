#!/usr/bin/env python3
"""Patch Hexciri nyx (2026-11-24, Devi 13:38 + 13:39 MST).

1. Stock system-update icon never clears after an update.
   hexciri.system-update (fork of Omarchy's widget) rechecks only every
   6h and on network-online, and nothing in hexciri update ever told it
   to recheck: after `hexciri update` the refresh icon stayed visible
   for up to 6 hours even though everything was current. Fix: after the
   shell restart in hexciri-update-restart, best-effort
   `hexciri-shell hexciri.system-update refresh` (the widget's own
   ShellIpc refresh, same pattern as `hexciri-shell hexciri.dock
   refresh`), so it re-runs hexciri-update-available immediately.
   No Omarchy server is involved: the widget only runs
   hexciri-update-available (checkupdates = Arch mirrors, plus a local
   git rev-list), and hexciri-version-channel is dead code that only
   greps pacman.conf for pkgs.omarchy.org and reports "unknown" -- it
   makes no network call. The "Omarchy" in the icon is the stock
   widget's refresh glyph; its manifest name/description were already
   renamed to Hexciri by the fork rename map.
2. hexciri-update-available counted git behind without fetching, and
   counted BOTH ~/.local/opt/hexciri (v1 dev path) and
   ~/.local/opt/hexciri-nyx. A stale v1 checkout behind its upstream
   lit the icon forever, and a stale upstream ref did the same.
   Upstream omarchy-update-available DID fetch (timeout 10) before
   rev-list. Fix: fetch first (best-effort, timeout 10), and only
   count the v1 checkout when the nyx checkout does not exist.
3. AUR update slowness (Devi 13:39: "aur update part of the script
   still takes the longest.. is this just how EOS does it?").
   Mostly yes, and it is NOT EOS-specific: eos-update --aur calls the
   same `yay -Sua`, and the time is dominated by downloading/building
   the actual AUR packages (brave-origin-bin, spotify, localsend-bin),
   not by the check. What was fixable in Hexciri: the AUR reachability
   probe before yay ran curl with --connect-timeout 30 --retry 3
   --retry-delay 3 (up to ~99s on a slow AUR before yay even started).
   Shorten the inline fallback to 10s / 1 retry / 2s delay (~12s max).
   The scanner side is fixed in Arch-Updates nyx 880e7c1d (parallel
   scan, branch-aware plugin behind check, yay -Qua timeout 120s).

Base: live nyx install.sh blob 88a459f85be6dfb2e00bfb2f6b35a359c4d6b124
(plugin-enable-multi push already live).
"""
import hashlib
import sys

ROOT = "/home/hatch/workspace/hexiri-2.0"
PATH = ROOT + "/v2/install.sh"

with open(PATH, "rb") as f:
    data = f.read()
blob = b"blob " + str(len(data)).encode() + b"\0" + data
assert hashlib.sha1(blob).hexdigest() == "88a459f85be6dfb2e00bfb2f6b35a359c4d6b124", \
    "base is not live HEAD (plugin-enable push), refusing to patch"
s = data.decode()

# --- 1. update-available: fetch + nyx-checkout priority ---
ANCHOR = '''updates=()
for _checkout in "$HOME/.local/opt/hexciri" "$HOME/.local/opt/hexciri-nyx"; do
  if [[ -d $_checkout/.git ]]; then
    upstream="$(git -C "$_checkout" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -n $upstream ]]; then
      behind="$(git -C "$_checkout" rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
'''
NEW = '''updates=()
# Hexciri (2026-11-24, Devi: stock system-update icon stayed on after an
# update): upstream omarchy-update-available fetched before rev-list, this
# rewrite did not, so behind was counted against a stale upstream ref.
# Fetch first (best-effort, timeout 10), and only count the v1 dev
# checkout (~/.local/opt/hexciri) when the v2 nyx checkout does not
# exist: a stale v1 checkout behind its upstream lit the icon forever.
_checkouts=("$HOME/.local/opt/hexciri-nyx" "$HOME/.local/opt/hexciri")
if [[ ! -d ${_checkouts[0]}/.git ]]; then
  _checkouts=("${_checkouts[1]}")
else
  _checkouts=("${_checkouts[0]}")
fi
for _checkout in "${_checkouts[@]}"; do
  if [[ -d $_checkout/.git ]]; then
    upstream="$(git -C "$_checkout" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -n $upstream ]]; then
      GIT_TERMINAL_PROMPT=0 timeout 10 git -C "$_checkout" fetch --quiet 2>/dev/null || true
      behind="$(git -C "$_checkout" rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
'''
assert s.count(ANCHOR) == 1, "update-available anchor not found exactly once"
assert "Hexciri (2026-11-24, Devi: stock system-update icon stayed on" not in s, "patch already applied"
s = s.replace(ANCHOR, NEW, 1)
# the loop's unset line now names the wrong variable; fix it
old_unset = 'unset _checkout\n\nmapfile -t _pending'
new_unset = 'unset _checkout _checkouts\n\nmapfile -t _pending'
assert s.count(old_unset) == 1, "update-available unset anchor not found"
s = s.replace(old_unset, new_unset, 1)

# --- 2. restart: broadcast refresh to hexciri.system-update ---
# A separate must_replace on the restart bin, appended after the 8d
# Hyprland-reload patch block. It anchors on the resulting file content
# (real newlines/quotes), not on install.sh's escaped Python literals.
ANCHOR2 = '    "restart reloads Hyprland config after the shell restart")\nPY\n'
BLOCK2 = ANCHOR2 + '''
# 8e. Restart refreshes the stock system-update widget (2026-11-24, Devi:
# its icon stayed on after an update because it only rechecks every 6h /
# on network-online and nothing ever told it to refresh. Its own ShellIpc
# refresh, same pattern as `hexciri-shell hexciri.dock refresh`.
# Best-effort: the widget may not be in the active bar (Nyxiri bar uses
# arch-updates).)
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
fork = sys.argv[1]
def read(p):
    with open(p) as f:
        return f.read()
def write(p, t):
    with open(p, "w") as f:
        f.write(t)
def must_replace(path, old, new, what):
    t = read(path)
    assert old in t, what + ": pattern not found in " + path
    assert t.count(old) == 1, what + ": pattern not unique in " + path
    write(path, t.replace(old, new, 1))
    print("  update: " + what)
_p = fork + "/bin/hexciri-update-restart"
must_replace(_p,
    '    hexciri-restart-hyprctl && echo "Hyprland config reloaded (hyprctl reload)"\\n  fi\\nfi',
    '    hexciri-restart-hyprctl && echo "Hyprland config reloaded (hyprctl reload)"\\n  fi\\n\\n  # Hexciri: tell the stock system-update widget to recheck now\\n  # (2026-11-24, Devi: its icon stayed on after an update because it\\n  # only rechecks every 6h / on network-online and nothing ever told\\n  # it to refresh. Its own ShellIpc refresh, same pattern as\\n  # `hexciri-shell hexciri.dock refresh`. Best-effort: the widget may\\n  # not be in the active bar (Nyxiri bar uses arch-updates).)\\n  hexciri-shell hexciri.system-update refresh >/dev/null 2>&1 || true\\nfi',
    "restart refreshes the system-update widget after an update")
PY
'''
assert s.count(ANCHOR2) == 1, "8d end anchor not found exactly once"
s = s.replace(ANCHOR2, BLOCK2, 1)

# --- 3. AUR probe: shorten inline curl fallback ---
old_curl = 'curl -sf --connect-timeout 30 --retry 3 --retry-delay 3 -A "hexciri-update" "https://aur.archlinux.org/rpc/?v=5&type=info&arg=base"'
new_curl = 'curl -sf --connect-timeout 10 --retry 1 --retry-delay 2 -A "hexciri-update" "https://aur.archlinux.org/rpc/?v=5&type=info&arg=base"'
assert s.count(old_curl) == 1, "AUR curl anchor not found exactly once"
s = s.replace(old_curl, new_curl, 1)

# --- 4. placement verification greps ---
ANCHOR3 = '''grep -q 'Hyprland config reloaded (hyprctl reload)' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not reload Hyprland after the shell restart (emergency mode returns after every update, 2026-11-24)"'''
NEW3 = '''grep -q 'Hyprland config reloaded (hyprctl reload)' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not reload Hyprland after the shell restart (emergency mode returns after every update, 2026-11-24)"
grep -q 'hexciri-shell hexciri.system-update refresh' "$HEXCIRI_PATH/bin/hexciri-update-restart" || die "hexciri-update-restart does not refresh the system-update widget after an update (stock icon stays on up to 6h, 2026-11-24)"
grep -q 'timeout 10 git -C "$_checkout" fetch --quiet' "$HEXCIRI_PATH/bin/hexciri-update-available" || die "hexciri-update-available does not fetch before counting git behind (stale ref keeps the update icon on, 2026-11-24)"
grep -q 'connect-timeout 10 --retry 1' "$HEXCIRI_PATH/bin/hexciri-update-aur-pkgs" || die "hexciri-update-aur-pkgs still probes the AUR with a 30s x3 curl (up to ~99s before yay starts, 2026-11-24)"'''
assert s.count(ANCHOR3) == 1, "verification anchor not found exactly once"
s = s.replace(ANCHOR3, NEW3, 1)

with open(PATH, "w") as f:
    f.write(s)
print("patched, new lines:", s.count("\n"))
print("sha256:", hashlib.sha256(s.encode()).hexdigest())
