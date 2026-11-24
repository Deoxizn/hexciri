-- Hexciri custom binds (2026-11-24, Devi: Hexciri Lua in the theme hook
-- work, custom parts only). Forked Omarchy already has most of v1's
-- binds.lua, so this file is ONLY what Omarchy's bindings/ does not:
--   Super+Space apps, Super+Alt+Space menu, Super+K, Super+Shift+T btm,
--   Super+Shift+B browser, Super+Shift+F files, Super+T float toggle,
--   Super+L layout cycle, universal Super+C/V copy/paste, Super+comma
--   notifications, Super+Escape system menu -- all already in Omarchy,
--   NOT duplicated here. Duplicating them would double-register binds.
-- v1 bits deliberately left out: fuzzel search/calc (no fuzzel in v2,
-- QS menus instead), Noctalia notification/settings binds (no Noctalia
-- in v2), hexciri-agent on Super+grave (AI out of scope for v2 base).
-- Installed by the installer into default/hypr/bindings/hexciri.lua;
-- bindings.lua require_all.files() auto-loads every file in that dir,
-- so no edit to hexciri.lua is needed. Syntax-checked at install time.

-- Monocle stack flipping: every window is fullscreen, so directional
-- focus is useless, cycle the stack instead (forward/back, wrapping).
-- Plain cycle_next() does NOT work in monocle (focus moves without
-- restacking, invisible): cyclenext/cycleprev are the anointed path.
-- Brackets, not PageUp/PageDown: laptop Fn-combos for paging do not
-- reach the compositor with Super held, but [ ] are physical keys.
o.bind("SUPER + bracketright", "Cycle stack forward (monocle)", hl.dsp.layout("cyclenext"))
o.bind("SUPER + bracketleft", "Cycle stack back (monocle)", hl.dsp.layout("cycleprev"))

-- Brave Origin incognito, direct. Omarchy has Super+Shift+Alt+B
-- (private via the defaults layer); this is Hexciri's explicit
-- Ctrl+B launcher for Brave Origin, the v2 browser.
o.bind("SUPER + CTRL + B", "Brave Origin (incognito)", "brave-origin --incognito")

-- Messenger webapp (no extra app, browser webapp via the launch-or-focus
-- webapp helper, which is in the fork).
o.bind("SUPER + CTRL + M", "Messenger webapp", "hexciri-launch-or-focus-webapp messenger https://www.messenger.com")

-- Screen record on Alt+Print. Region/screenshot stay on Omarchy's binds.
o.bind("ALT + Print", "Screen record", "hexciri-capture-screenrecording")
