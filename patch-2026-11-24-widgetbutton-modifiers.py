#!/usr/bin/env python3
"""WidgetButton forwards click modifiers, so Shift+right-click is real.

Devi 2026-11-24 13:53 MST: right-click opening the settings menu stole
the option to swap formats (clock: right-click cycled the label format).

Root cause, two parts:
1. Nyxiri clock/weather/workspaces standalone settings popups (2026-11-20)
   took over plain right-click: clock lost cycleFormat, weather lost its
   status notification. Workspaces right-click never cycled anything, so
   it stays settings.
2. Upstream WidgetButton's pressed signal carries only the button:
   onClicked passes mouse.button, modifiers are dropped, so a widget
   cannot tell Shift+right-click from a plain right-click at all.

Fix:
- hexciri fork patch (this script): shell/Ui/WidgetButton.qml forwards
  the modifiers: signal pressed(int button, int modifiers),
  triggerPress(button, modifiers) with modifiers defaulting to
  Qt.NoModifier, onClicked passes mouse.modifiers. Backward compatible:
  handlers taking only the button ignore the extra signal arg, and the
  triggerPress(button) callers in Bar.qml / KeyboardPanel keep working.
  Placement verification dies if the forwarding is missing.
- omarchy-clock nyx: plain right-click cycles the format again,
  Shift+right-click opens ClockSettings (separate push).
- omarchy-weather nyx: plain right-click sends the weather-status
  notification again, Shift+right-click opens WeatherSettings
  (separate push).

Base: live nyx install.sh blob 600cadfc5784ddfcc8b49047e289cd94c62aa8b4
(Settings menu row removal f3ba3dab, already live).
"""
import hashlib

ROOT = "/home/hatch/workspace/hexiri-2.0"
PATH = ROOT + "/v2/install.sh"

with open(PATH, "rb") as f:
    data = f.read()
blob = b"blob " + str(len(data)).encode() + b"\0" + data
assert hashlib.sha1(blob).hexdigest() == "600cadfc5784ddfcc8b49047e289cd94c62aa8b4", \
    "base is not live HEAD (settings menu row push), refusing to patch"
s = data.decode()

# --- 1. New fork patch step, before the dock pinned-list step.
ANCHOR = 'step "Patching dock pinned list: Strata, Spotify, Brave Origin, Zed, Kitty"'
assert s.count(ANCHOR) == 1
BLOCK = '''# --- Patch WidgetButton to forward click modifiers (2026-11-24) ---
# Upstream WidgetButton's pressed signal carries only the button:
# onClicked passes mouse.button, modifiers are dropped. A widget
# therefore cannot tell Shift+right-click from a plain right-click.
# Nyxiri clock/weather need that distinction (2026-11-24, Devi:
# right-click opening settings stole the format swap): plain
# right-click cycles the clock format / sends the weather notification,
# Shift+right-click opens the standalone settings window. Forwarding is
# backward compatible: handlers that only take the button ignore the
# extra signal arg, and the triggerPress(button) callers in Bar.qml /
# KeyboardPanel keep working, modifiers defaults to Qt.NoModifier.
step "Patching WidgetButton to forward click modifiers"
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys
root = sys.argv[1]
path = root + "/shell/Ui/WidgetButton.qml"
with open(path) as f:
    s = f.read()
orig = s
old_sig = "  signal pressed(int button)"
assert s.count(old_sig) == 1, "WidgetButton pressed signal anchor not found"
s = s.replace(old_sig, """  // Hexciri (2026-11-24): pressed carries the click modifiers too,
  // so a widget can tell Shift+right-click (open its settings) from a
  // plain right-click (clock: cycle format, weather: status notification).
  signal pressed(int button, int modifiers)""", 1)
old_trig = """  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
  }"""
assert s.count(old_trig) == 1, "WidgetButton triggerPress anchor not found"
s = s.replace(old_trig, """  function triggerPress(button, modifiers) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button, modifiers !== undefined ? modifiers : Qt.NoModifier)
  }""", 1)
old_click = "    onClicked: function(mouse) { if (root.pressable) root.triggerPress(mouse.button) }"
assert s.count(old_click) == 1, "WidgetButton onClicked anchor not found"
s = s.replace(old_click, "    onClicked: function(mouse) { if (root.pressable) root.triggerPress(mouse.button, mouse.modifiers) }", 1)
if s != orig:
    with open(path, "w") as f:
        f.write(s)
    print("WidgetButton: pressed forwards click modifiers (Shift+right-click distinguishable)")
else:
    print("WidgetButton: modifiers forwarding already applied, skipping")
PY

'''
s = s.replace(ANCHOR, BLOCK + ANCHOR, 1)

# --- 2. Placement verification: die if the forwarding is missing.
ANCHOR2 = '''grep -q '/usr/share/hexciri/bin/hexciri-shell hexciri.dock apps' "$HEXCIRI_PATH/default/hexciri/hexciri-menu.jsonc" || die "menu apps row does not call hexciri-shell by absolute path"'''
assert s.count(ANCHOR2) == 1
s = s.replace(ANCHOR2, ANCHOR2 + '''
grep -q 'signal pressed(int button, int modifiers)' "$HEXCIRI_PATH/shell/Ui/WidgetButton.qml" || die "WidgetButton does not forward click modifiers, Shift+right-click settings cannot be told from plain right-click (2026-11-24)"''', 1)

with open(PATH, "w") as f:
    f.write(s)
print("patched v2/install.sh")
print("new blob sha1:", hashlib.sha1(b"blob " + str(len(s.encode())).encode() + b"\0" + s.encode()).hexdigest())
print("lines:", s.count("\n"))
