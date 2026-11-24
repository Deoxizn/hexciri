#!/usr/bin/env python3
"""Super+Alt+Space menu empty after update (2026-11-24, Devi 15:52 MST).

Devi: "just ran update and the whole super alt menu is gone.. just says
nothing is there..."

Root cause, proven by running the live-HEAD fork sim (sim7) and parsing
its output the way the shell parses it:
- The cf3bb1a maple row (Install > Style > Font > Maple Mono CN) is the
  ONLY injected menu row whose action holds double quotes:
  hexciri-font-set "Maple Mono NF CN". Its Python literal writes those
  as \\" -- but inside a double-quoted Python string \\" collapses to a
  bare ", so the emitted jsonc line holds BARE quotes inside the JSON
  string value: ..."action":"... hexciri-font-set "Maple Mono NF CN"'...
  JSON needs \\" there; the author needed \\\\\\" in the Python literal.
- MenuModel.js readMenuJsonc does stripJsonc (full-line // comments +
  trailing commas) then JSON.parse. One bad row makes the WHOLE file
  unparseable (json.loads fails at line 199, column 248 in the fork
  output), readMenuJsonc returns null, keepMenuRows keeps previous rows
  -- but a fresh shell after the update has NO previous rows, so the
  menu model is empty and Menu.qml shows menu.nothingHere ("nothing is
  there"). The fork output parses fine once that line is fixed (369
  entries, 9 root entries: apps appearance trigger setup install remove
  update learn system; maple action round-trips with its quotes).
- Why now: updates between cf3bb1a (22:37 UTC) and 7cfd163 kept dying
  at placement verification (tmux config, then applications/foot.desktop),
  so the broken jsonc never landed. 7cfd163 fixed placement, Devi's
  15:52 MST update was the first to place it, and the shell restarted
  onto the unparseable file. 7cfd163 itself changed nothing in the row.
- Why nothing caught it: every menu check in the installer is grep for
  row presence. Grep sees the maple row just fine. sim28 passed 100%
  and shipped a menu that cannot parse. No check anywhere parses the
  jsonc.

Fix (v2/install.sh only):
1. _maple_row: emit escaped quotes (\\\\\\" in the Python literal, so
   the jsonc holds \\" and the shell action still sees "Maple Mono NF CN").
2. Fork stage: after every menu write in the audit block, parse the
   forked jsonc exactly like MenuModel.js does and require the 9 root
   entries + the maple action with its quoted font name. A broken menu
   now dies in the fork, before placement, never live.
3. Placement verification: parse the placed jsonc the same way (same
   strip, same 9 roots) right after the existence check. Defense in
   depth: the fork check is the gate, this one is the proof on the live
   tree.

Usage: python3 patch-2026-11-24-menu-empty.py [path/to/install.sh]
Default path is /tmp/menu-empty-1124/v2/install.sh (staging copy of
live nyx 7cfd163).
"""
import hashlib
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "/tmp/menu-empty-1124/v2/install.sh"
BASE_SHA = "aab5d55564ffe3f4a944e3250f24369694c7b5e412250dffee85358a560c2c35"

with open(PATH, "rb") as f:
    data = f.read()
assert hashlib.sha256(data).hexdigest() == BASE_SHA, (
    "base install.sh sha mismatch, refusing to patch (rebase first)")
text = data.decode()
orig = text
changed = []
BS = chr(92)

# 1. Maple row: bare quotes -> escaped quotes in the emitted jsonc.
old_maple = 'hexciri-font-set ' + BS + '"Maple Mono NF CN' + BS + '"'
new_maple = 'hexciri-font-set ' + BS * 3 + '"Maple Mono NF CN' + BS * 3 + '"'
assert text.count(old_maple) == 1, "maple row anchor not found exactly once"
text = text.replace(old_maple, new_maple)
changed.append("maple row: action quotes escaped in emitted jsonc (was bare, unparseable)")

# 2. Fork-stage parse validation, at the end of the menu audit block.
old_audit_tail = 'for c in changed:\n    print("menu audit: " + c)\nif not changed:\n    print("menu audit: no changes needed")'
assert text.count(old_audit_tail) == 1, "menu audit tail anchor not found exactly once"
new_audit_tail = r'''# 9. The forked menu jsonc must still parse exactly like the shell parses
# it (2026-11-24, Devi: whole Super+Alt+Space menu empty after update).
# MenuModel.js stripJsonc drops full-line // comments and trailing
# commas, then JSON.parse; ONE bad row makes the WHOLE file unparseable,
# readMenuJsonc returns null, and a fresh shell has no previous rows, so
# the menu opens on nothingHere. The cf3bb1a maple row did exactly this:
# its action held bare "Maple Mono NF CN" quotes (Python \" in the row
# literal collapses to a bare quote; JSON needs \"). Grep checks for row
# presence cannot see this. Parse here, in the fork, so a broken menu
# dies before placement, never live.
import json
_menu_raw = open(menu).read()
_menu_stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', _menu_raw, flags=re.M)
_menu_stripped = re.sub(r',(\s*[}\]])', r'\1', _menu_stripped)
try:
    _menu_parsed = json.loads(_menu_stripped)
except Exception as _e:
    raise SystemExit("menu jsonc does not parse, shell would show an empty menu: %s" % _e)
for _r in ('apps', 'appearance', 'trigger', 'setup', 'install', 'remove', 'update', 'learn', 'system'):
    if _r not in _menu_parsed:
        raise SystemExit("menu jsonc missing root entry %s, shell would show an empty menu" % _r)
if 'hexciri-font-set "Maple Mono NF CN"' not in _menu_parsed.get('install.style.font.maple', {}).get('action', ''):
    raise SystemExit("menu maple row action lost its quoted font name")
changed.append("menu jsonc parses (%d entries, 9 root entries)" % len(_menu_parsed))

for c in changed:
    print("menu audit: " + c)
if not changed:
    print("menu audit: no changes needed")'''
text = text.replace(old_audit_tail, new_audit_tail)
changed.append("fork stage: menu jsonc parsed like MenuModel.js (9 roots + maple action)")

# 3. Placement verification: parse the placed jsonc, same strip, same roots.
old_verify = '[ -f "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" ] || die "missing: default/hexciri/hexciri-menu.jsonc, Super+Alt+Space menu has no routes"'
assert text.count(old_verify) == 1, "placement menu verify anchor not found exactly once"
new_verify = old_verify + r'''
# The menu jsonc must PARSE, not just exist (2026-11-24, Devi: whole
# menu empty after update): the cf3bb1a maple row had bare double quotes
# inside its action string, so MenuModel.js JSON.parse failed on the whole
# file and a fresh shell showed nothingHere. Grep row checks cannot see
# this; parse it exactly like the shell does (full-line // comments +
# trailing commas stripped) and require the 9 root entries.
python3 - "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" <<'PYEOF' || die "hexciri-menu.jsonc does not parse, Super+Alt+Space menu would be empty (see above)"
import json, re, sys
raw = open(sys.argv[1]).read()
stripped = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
try:
    d = json.loads(stripped)
except Exception as e:
    print("menu jsonc parse error: %s" % e)
    sys.exit(1)
for r in ('apps', 'appearance', 'trigger', 'setup', 'install', 'remove', 'update', 'learn', 'system'):
    if r not in d:
        print("menu jsonc missing root entry: %s" % r)
        sys.exit(1)
print("menu jsonc parses: %d entries" % len(d))
PYEOF'''
text = text.replace(old_verify, new_verify)
changed.append("placement verification: placed menu jsonc parsed (9 roots)")

# 4. Changelog item 21: record the fix.
old_changelog = 'plus the four desktop_id arms in install-terminal.'
assert text.count(old_changelog) == 1, "changelog anchor not found exactly once"
new_changelog = old_changelog + ' Menu jsonc now parses (2026-11-24, Devi: whole Super+Alt+Space menu empty after update): the cf3bb1a maple row had bare double quotes inside its action string, so the shell JSON.parse failed on the whole file and a fresh shell showed nothingHere; the row now emits escaped quotes, the fork patch parses the menu before placement, and placement verification parses it again.'
text = text.replace(old_changelog, new_changelog)
changed.append("changelog item 21: menu-empty root cause + parse guards")

assert text != orig
with open(PATH, "w") as f:
    f.write(text)
print("patched", PATH)
for c in changed:
    print(" -", c)
print("new sha256:", hashlib.sha256(text.encode()).hexdigest())
print("lines:", text.count("\n") + 1)
