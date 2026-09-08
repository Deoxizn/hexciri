-- hexciri — input rendered for hyprland
-- source: config/niri/input.kdl (niri fragment; regenerate with: hexciri-config-render input hyprland)
-- Confirmed 0.56 Lua keys; niri-only semantics that Hyprland lacks are
-- surfaced as NOTE comments, never silently dropped (policy §7).
hl.config({ input = {
            kb_layout = "us",
            touchpad = { natural_scroll = true, disable_while_typing = true },
            -- NOTE: niri `tap` is the Hyprland default; no toggle needed.
} })

