-- Hexciri — Hyprland config (entry point, native Lua 0.56+)
-- https://github.com/deoxizn/hexciri
--
-- Since 0.55 the Lua format is the primary config; hyprlang .conf is deprecated
-- and dropped around 0.57. This file is the entry point only: it requires the
-- per-concern fragments below. require() is relative to ~/.config/hypr/.
--
--   require("hypr.conf.env")            -- hl.env(...) — Wayland hints for every app
--   require("hypr.conf.input")          -- hl.config({ input = ... }) — kb/touchpad
--   require("hypr.conf.monitors")       -- hl.monitor(...) — screens, scale, mode, VRR
--   require("hypr.conf.looknfeel")      -- theme-owned feel: borders (gradient), gaps
--   require("hypr.conf.window-rules")   -- window rules (samples; edit to taste)
--   require("hypr.conf.keybinds")       -- hl.bind(...) — rendered from
--                                       --   config/keybinds/intents.toml (single source)
--   require("hypr.conf.autostart")      -- hl.on("hyprland.start", ...) — boot services
--
-- Split so each concern is easy to find, edit and back up on its own.
-- To add MORE custom keybinds without touching the schema, append hl.bind(...)
-- lines here after the requires — config reloads automatically on save.

require("hypr.conf.env")
require("hypr.conf.input")
require("hypr.conf.monitors")
require("hypr.conf.looknfeel")
require("hypr.conf.window-rules")
require("hypr.conf.keybinds")
require("hypr.conf.autostart")