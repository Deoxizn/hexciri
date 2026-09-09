"""Shared keybind name translators for bin/hexciri-keybinds-render and bin/hexciri-keybinds.
Combo notation in intents.toml uses "Mod" for Super and XDG-era names; each function
translates a combo into the given WM's key syntax.
"""


def key_niri(c):
    return c.replace("Mod", "Mod")


def key_hyp_lua(c):
    m = {
        "Print": "Print", "Return": "Return", "grave": "grave",
        "BracketLeft": "bracketleft", "BracketRight": "bracketright",
        "Comma": "comma", "Escape": "Escape", "Space": "space",
        "Up": "Up", "Down": "Down", "Left": "Left", "Right": "Right",
    }
    out = []
    for p in c.split("+"):
        p = m.get(p, p)
        if p == "Mod":
            out.append("SUPER")
        elif p in ("Ctrl", "Shift", "Alt"):
            out.append(p.upper())
        else:
            out.append(p)
    return " + ".join(out)


def key_sway(c):
    m = {
        "Print": "Print", "Return": "Return", "grave": "grave",
        "BracketLeft": "bracketleft", "BracketRight": "bracketright",
        "Comma": "comma", "Escape": "Escape", "Space": "space",
    }
    mods = ""
    sub = ""
    for p in c.split("+"):
        if p == "Mod":
            mods += "Mod4+"
        elif p == "Ctrl":
            mods += "Ctrl+"
        elif p == "Shift":
            mods += "Shift+"
        elif p == "Alt":
            mods += "Mod1+"
        else:
            sub = m.get(p, p)
    return f"{mods}{sub}"


def key_mango(c):
    m = {"Mod": "SUPER", "Ctrl": "CTRL", "Alt": "ALT", "Shift": "SHIFT"}
    mods, key = [], ""
    for p in c.split("+"):
        p = m.get(p, p)
        if p in ("SUPER", "CTRL", "ALT", "SHIFT"):
            mods.append(p)
        else:
            key = p
    if not key.startswith("XF86"):
        key = key.lower()
    return ("+".join(mods) if mods else "NONE") + "," + key


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def hyp_dsp(action):
    """Legacy-hyprlang dispatcher token -> native 0.56 Lua hl.dsp expression.

    Returns None for combos that have no Lua sibling (the renderer emits a
    `-- comment` instead, and hexciri-keybinds omits them entirely) — this is
    the SINGLE bound/not-bound check shared by both scripts.
    """
    import re

    a = action.strip() if isinstance(action, str) else ""
    if a.startswith("(") or a.startswith("overview"):
        return None
    if a == "closeactive":
        return "hl.dsp.window.close()"
    m = re.match(r"^movefocus ([lrud])$", a)
    if m:
        return f"hl.dsp.focus({{ direction = '{m.group(1)}' }})"
    m = re.match(r"^movewindow ([lrud])$", a)
    if m:
        return f"hl.dsp.window.move({{ direction = '{m.group(1)}' }})"
    m = re.match(r"^movetoworkspace (\d+)$", a)
    if m:
        return f"hl.dsp.window.move({{ workspace = {m.group(1)}, follow = true }})"
    m = re.match(r"^movetoworkspacesilent name:(.+)$", a)
    if m:
        return f"hl.dsp.window.move({{ workspace = {lua_str(m.group(1))}, follow = false }})"
    m = re.match(r"^workspace (\d+)$", a)
    if m:
        return f"hl.dsp.focus({{ workspace = {m.group(1)} }})"
    m = re.match(r"^workspace name:(.+)$", a)
    if m:
        return f"hl.dsp.focus({{ workspace = {lua_str(m.group(1))} }})"
    m = re.match(r"^workspace (e[+-]\d+)$", a)
    if m:
        return f"hl.dsp.focus({{ workspace = {lua_str(m.group(1))} }})"
    if a == "togglefloating":
        return "hl.dsp.window.float({ action = \"toggle\" })"
    if a == "togglefloating maximize":
        return "hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })"
    if a == "fullscreen":
        return "hl.dsp.window.fullscreen({ action = \"toggle\" })"
    if a == "resizeactive":
        return "hl.dsp.window.resize()"
    if a == "togglegroup":
        return "hl.dsp.group.toggle()"
    if a == "focusmode floating":
        return "hl.dsp.focus({ window = \"floating\" })"
    if a == "focusmode tiling":
        return "hl.dsp.focus({ window = \"tiled\" })"
    m = re.match(r"^swapwindow ([lr])$", a)
    if m:
        return f"hl.dsp.window.swap({{ direction = '{m.group(1)}' }})"
    return None