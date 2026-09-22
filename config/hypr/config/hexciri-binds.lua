-- Hexciri core binds for Hyprland (additive overlay).
-- Required AFTER the stock binds (see hyprland.lua) so the hexciri standard
-- wins on shared combos. Mirrors config/niri/cfg/keybinds.kdl core.
--
-- Deliberately NOT duplicated from stock binds.lua:
--   * file manager (stock Mod+E dolphin stays — each WM keeps its own)
--   * media/brightness keys (stock routes them via noctalia; niri uses
--     wpctl/playerctl/brightnessctl directly — each WM keeps its own)
--   * workspaces/monitors/focus/move (stock covers them)
--
-- One opinionated override: Mod+Escape is the hexciri power menu (Mod+Q
-- closes), while stock binds Mod+Escape to kill. Loaded after stock binds,
-- this file wins — matching niri muscle memory.

local mainMod = "SUPER"

-- Root menu / keybind reference / agent
hl.bind(mainMod .. " + ALT + Space", hl.dsp.exec_cmd("hexciri-menu"))
hl.bind(mainMod .. " + K",           hl.dsp.exec_cmd("hexciri-keybinds"))
hl.bind(mainMod .. " + grave",       hl.dsp.exec_cmd("hexciri-agent"))

-- Search / calculator (fuzzel providers)
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("hexciri-fuzzel search"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hexciri-fuzzel calc"))

-- Default apps (terminal/editor/browser via hexciri defaults layer)
hl.bind(mainMod .. " + Return",  hl.dsp.exec_cmd("hexciri-terminal"))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("zeditor"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("xdg-open https://"))

-- Window close (same as stock — harmless duplicate, keeps muscle memory)
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Power menu (overrides stock kill on this combo — see header)
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("hexciri-power"))

-- Lock (hexciri-lock adds the panel-off loop on top of the shell lock)
hl.bind(mainMod .. " + CONTROL + L", hl.dsp.exec_cmd("hexciri-lock"))

-- Clipboard history
hl.bind(mainMod .. " + CONTROL + V", hl.dsp.exec_cmd("hexciri-clipboard"))

-- Messenger webapp
hl.bind(mainMod .. " + CONTROL + M", hl.dsp.exec_cmd("hexciri-launch-or-focus-webapp messenger https://www.messenger.com"))

-- Screen record (region/screenshot stay on stock noctalia binds)
hl.bind("ALT + Print", hl.dsp.exec_cmd("hexciri-screenrecord"))

-- Notifications (same verbs as the niri binds)
hl.bind(mainMod .. " + comma",         hl.dsp.exec_cmd("noctalia msg notification-clear-active"))
hl.bind(mainMod .. " + CONTROL + period", hl.dsp.exec_cmd("noctalia msg notification-clear-history"))
hl.bind(mainMod .. " + CONTROL + S",   hl.dsp.exec_cmd("noctalia msg settings-toggle"))
