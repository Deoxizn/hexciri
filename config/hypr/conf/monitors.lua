-- Hexciri — Hyprland fragment: Monitors / outputs
-- Required by hyprland.lua. On a WM swap this is the ONLY fragment replaced
-- whole-hog by the carry-over (your installed monitor layout overwrites
-- hexciri's copy), so keep it to pure hl.monitor() calls and comments about them.
--
-- The block below is the default for this machine's laptop panel (eDP-1,
-- 2880x1920@120, 2x HiDPI — the same default omarchy ships). On a desktop, or
-- if your panel has a different name, run:  hyprctl monitors
-- then edit the output name and set your values. Settings you can set:
--   mode "2880x1920@120"       -- WIDTHxHEIGHT@REFRESH — resolution + refresh
--   scale 2                    -- UI scaling; 1 for native, 1.25/1.5/2 fractional
--   position "0x0"             -- arrange multi-monitor layout (negative allowed)
--   reserved_area { ... }      -- space for panels/bars
-- The output = "" fallback rule catches every other monitor (mode "preferred",
-- position "auto") so unlisted screens never come up blank.
--
-- The niri counterpart (config/niri/monitors.kdl) documents the options in the
-- "Per-output settings you can set:" block — same semantics here.

hl.monitor({
    output = "eDP-1",
    mode = "2880x1920@120",
    position = "0x0",
    scale = 2,
    -- vrr = 1,                -- VRR: match refresh to content (reduces tearing)
})

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})