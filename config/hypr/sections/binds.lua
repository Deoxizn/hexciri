-- Hexciri core binds (machine-managed section — see sync_hyprland).
-- Mirrors config/niri/cfg/keybinds.kdl core. Uses stock mainMod.

-- Root menu / keybind reference / agent
hl.bind(mainMod .. " + ALT + Space", hl.dsp.exec_cmd("hexciri-menu"))
hl.bind(mainMod .. " + K",           hl.dsp.exec_cmd("hexciri-keybinds"))
hl.bind(mainMod .. " + grave",       hl.dsp.exec_cmd("hexciri-agent"))

-- Search / calculator (fuzzel providers)
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("hexciri-fuzzel search"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("hexciri-fuzzel calc"))

-- System monitor (bottom)
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " -e btm"))

-- Default apps (terminal/editor/browser/file manager via hexciri defaults layer)
hl.bind(mainMod .. " + Return",   hl.dsp.exec_cmd("hexciri-terminal"))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("zeditor"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("xdg-open https://"))
-- NOTE: stock Mod+W (launchPrefix .. BROWSER with BROWSER="firefox") is dead
-- — firefox is replaced by Brave Origin — and is neutralized at deploy with
-- NO replacement: browser already lives on Mod+Shift+B. One browser launcher.
-- Mod+Shift+F = File manager, niri verb. Dispatches the user's Defaults pick
-- (strata on hyprland boxes, nautilus on niri) via hexciri-defaults run files.
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("hexciri-defaults run files"))

-- Floating toggle on Mod+T (Omarchy parity): the niri verb and the stock
-- float slot agree here — tiling/floating flip, no menus involved.
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))

-- Layout cycle (dwindle/scrolling/monocle) on Mod+L (Omarchy parity): takes
-- over the stock session-lock slot — neutralized at deploy like the other
-- owned combos, since lock already lives on Mod+Ctrl+L (hexciri-lock, with
-- the panel-off loop) and needs no plain-L duplicate.
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hexciri-hyprland-layout"))

-- Monocle stack flipping: every window is fullscreen, so directional focus
-- is useless — cycle the stack instead (forward/back, wrapping). Alt+Tab
-- does this globally too; these are the Mod-driven equivalents. Brackets, not
-- PageUp/PageDown: laptop Fn-combos for paging don't reach the compositor
-- with Mod held, but [ ] are physical keys everywhere.
-- Per the wiki's monocle quirks, plain cycle_next() does NOT work in monocle
-- (focus moves without restacking — invisible): the layout messages
-- cyclenext/cycleprev are the anointed path (verified live: ok under
-- monocle, unknown-message under dwindle as expected).
hl.bind(mainMod .. " + bracketright", hl.dsp.layout("cyclenext"))
hl.bind(mainMod .. " + bracketleft", hl.dsp.layout("cycleprev"))

-- Workspaces: niri verbs (Mod+digit switch / Mod+SHIFT+digit move). Stock
-- CachyOS binds Mod+ALT+digit to switch and Mod+SHIFT+CONTROL|ALT+digit to
-- move, and its Mod+SHIFT+digit(1-3) nudges windows between MONITORS — the
-- deploy patch removes those three so the move verb is unambiguous. Digit
-- binds use keycodes (code:10..18 = the number row) exactly like stock
-- digitCode()/Omarchy, so they work on every layout (AZERTY included).
hl.bind(mainMod .. " + code:10", hl.dsp.focus({ workspace = "1" }))
hl.bind(mainMod .. " + code:11", hl.dsp.focus({ workspace = "2" }))
hl.bind(mainMod .. " + code:12", hl.dsp.focus({ workspace = "3" }))
hl.bind(mainMod .. " + code:13", hl.dsp.focus({ workspace = "4" }))
hl.bind(mainMod .. " + code:14", hl.dsp.focus({ workspace = "5" }))
hl.bind(mainMod .. " + code:15", hl.dsp.focus({ workspace = "6" }))
hl.bind(mainMod .. " + code:16", hl.dsp.focus({ workspace = "7" }))
hl.bind(mainMod .. " + code:17", hl.dsp.focus({ workspace = "8" }))
hl.bind(mainMod .. " + code:18", hl.dsp.focus({ workspace = "9" }))
hl.bind(mainMod .. " + SHIFT + code:10", hl.dsp.window.move({ workspace = "1" }))
hl.bind(mainMod .. " + SHIFT + code:11", hl.dsp.window.move({ workspace = "2" }))
hl.bind(mainMod .. " + SHIFT + code:12", hl.dsp.window.move({ workspace = "3" }))
hl.bind(mainMod .. " + SHIFT + code:13", hl.dsp.window.move({ workspace = "4" }))
hl.bind(mainMod .. " + SHIFT + code:14", hl.dsp.window.move({ workspace = "5" }))
hl.bind(mainMod .. " + SHIFT + code:15", hl.dsp.window.move({ workspace = "6" }))
hl.bind(mainMod .. " + SHIFT + code:16", hl.dsp.window.move({ workspace = "7" }))
hl.bind(mainMod .. " + SHIFT + code:17", hl.dsp.window.move({ workspace = "8" }))
hl.bind(mainMod .. " + SHIFT + code:18", hl.dsp.window.move({ workspace = "9" }))

-- Window close (same as stock — harmless duplicate, keeps muscle memory)
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Power menu (stock kill on this combo is patched out at deploy — see header)
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("hexciri-power"))

-- Lock (hexciri-lock adds the panel-off loop on top of the shell lock)
hl.bind(mainMod .. " + CONTROL + L", hl.dsp.exec_cmd("hexciri-lock"))

-- Clipboard history
hl.bind(mainMod .. " + CONTROL + V", hl.dsp.exec_cmd("hexciri-clipboard"))
-- Clipboard panel (moved off Mod+V for universal paste — same family)
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("noctalia msg panel-toggle clipboard"))

-- Universal copy/paste (Omarchy parity): Super chords work everywhere —
-- terminals get Ctrl+Shift, everything else gets Ctrl+C/V. Synthetic keys go
-- down/up split (50ms oneshot) so key state never sticks or repeats.
-- Terminals are matched by window class (no tag system here).
local function send_key_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end
local TERMINAL_CLASSES = { kitty = true, foot = true, ghostty = true, Alacritty = true,
  ["tui.float"] = true, ["app.hexciri.ff"] = true }
local function active_is_terminal()
  local ok, w = pcall(hl.get_active_window)
  if not ok or not w then return false end
  return TERMINAL_CLASSES[w.class] == true
end
local function universal_key(gui_mods, gui_key, term_mods, term_key)
  return function()
    if active_is_terminal() then
      send_key_once(term_mods, term_key)()
    else
      send_key_once(gui_mods, gui_key)()
    end
  end
end
hl.bind(mainMod .. " + C", universal_key("CTRL", "C", "CTRL SHIFT", "C"))
hl.bind(mainMod .. " + V", universal_key("CTRL", "V", "CTRL SHIFT", "V"))

-- Messenger webapp
hl.bind(mainMod .. " + CONTROL + M", hl.dsp.exec_cmd("hexciri-launch-or-focus-webapp messenger https://www.messenger.com"))

-- Screen record (region/screenshot stay on stock noctalia binds)
hl.bind("ALT + Print", hl.dsp.exec_cmd("hexciri-screenrecord"))

-- Notifications (same verbs as the niri binds)
hl.bind(mainMod .. " + comma",            hl.dsp.exec_cmd("noctalia msg notification-clear-active"))
hl.bind(mainMod .. " + CONTROL + period", hl.dsp.exec_cmd("noctalia msg notification-clear-history"))
hl.bind(mainMod .. " + CONTROL + S",      hl.dsp.exec_cmd("noctalia msg settings-toggle"))
