-- Hexciri custom binds (2026-11-24, Devi: Hexciri Lua in the theme hook
-- work, custom parts only). Forked Omarchy already has most of v1's
-- binds.lua, so this file is ONLY what Omarchy's bindings/ does not:
--   Super+Space apps, Super+Alt+Space menu, Super+K, Super+Shift+T btm,
--   Super+Shift+B browser, Super+Shift+F files, Super+T float toggle,
--   Super+L layout cycle, universal Super+C/V copy/paste, Super+comma
--   notifications, Super+Escape system menu -- all already in Omarchy,
--   NOT duplicated here. Duplicating them would double-register binds.
-- v1 bits deliberately left out: Noctalia notification/settings binds
-- (no Noctalia in v2), hexciri-agent on Super+grave (AI out of scope
-- for v2 base). fuzzel search/calc are NOT left out: they are restored
-- below, 2026-11-24 (Devi: Mod+Shift+S web search, Mod+Shift+C
-- calculator in v1). No fuzzel in v2, so the search prompt is
-- hexciri-menu-input (QS menu) via the hexciri-web-search bin.
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

-- Hexciri Settings (2026-11-24, Devi): forked omarchy-settings as an
-- app, not a shell plugin. Super+Ctrl+S is reclaimed for it in the
-- installer fork patch: upstream bound it to Share, Share now lives on
-- Super+Ctrl+Shift+S. Super+Alt+S is scratchpad, not Settings.
-- The bind runs hexciri-launch-settings, not the binary directly:
-- when the Qt build has not landed yet it notifies with the rebuild
-- command instead of silently doing nothing (2026-11-24).
o.bind("SUPER + CTRL + S", "Hexciri Settings", "hexciri-launch-settings")

-- Screen record on Alt+Print. Region/screenshot stay on Omarchy's binds.
o.bind("ALT + Print", "Screen record", "hexciri-capture-screenrecording")

-- Web search / calculator, v1 binds restored 2026-11-24 (Devi).
-- Omarchy's regions/global.lua binds these chords to Google Maps /
-- Hey Calendar webapps; the installer fork patch removes those two
-- lines, so these are the only binds on the chords. Search prompts
-- via hexciri-menu-input (QS menu) and opens in Brave Origin, the
-- v2 default browser, via hexciri-web-search (v1 provider table,
-- default google, state file ~/.local/state/hexciri/search-provider).
o.bind("SUPER + SHIFT + S", "Web search", "hexciri-web-search")
-- Calculator is deliberately also on Super+Shift+Q (Omarchy's chord,
-- applications.lua, gnome-calculator in v2): Q and C are the same app,
-- and the cheatsheet already lists Calculator as an alternative-chord
-- action, so both chords show on one row instead of two.
o.bind("SUPER + SHIFT + C", "Calculator", "gnome-calculator")
