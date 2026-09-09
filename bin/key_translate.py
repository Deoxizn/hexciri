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