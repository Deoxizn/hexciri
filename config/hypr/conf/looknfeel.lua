-- Hexciri — Hyprland fragment: Look & feel — THEME-OWNED.
-- Required by hyprland.lua. The hexciri theme hook (hexciri-sync.sh) REWRITES
-- the two color locals below on every theme change, so:
--   • keep this file to theme surface only (borders, gaps, feel)
--   • don't put layout/keybind tweaks here — those live in the other fragments
-- Per-color gradient form: { colors = { "rgba(...)", ... }, angle? = 45 }.
-- The border is a 2-stop gradient on the active side; the angle gives the
-- vertical family the theme hook keeps stable.

-- theme-owned: hexciri-sync.sh patches these two on every theme change
local active_border   = "rgba(7c3aedff)"
local inactive_border = "rgba(1a1a2e99)"

hl.config({
    general = {
        border_size = 2,
        gaps_in = 2,          -- gap between windows (css_gaps)
        gaps_out = 0,         -- gap between windows and monitor edges
        layout = "dwindle",
        resize_on_border = true,
        col = {
            active_border   = { colors = { active_border }, angle = 45 },
            inactive_border = { colors = { inactive_border } },
        },
    },
    decoration = {
        blur = {
            enabled = true,
            size = 8,
            passes = 3,
            ignore_opacity = true,
        },
        shadow = {
            enabled = true,
            color = { colors = { "rgba(00000044)" } },
        },
    },
    misc = {
        force_default_wallpaper = 0,   -- 0 = off (no default anime background)
        vrr = 2,                       -- VRR: match refresh to content
    },
})