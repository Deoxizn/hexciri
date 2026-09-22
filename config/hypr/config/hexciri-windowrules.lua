-- Hexciri window rules for Hyprland (additive overlay).
-- Required AFTER the stock windowrules (see hyprland.lua): anonymous rules
-- resolve last-match-wins, so this file must load after config.windowrules.
-- Mirrors config/niri/cfg/window-rules.kdl (hexciri-specific bits only —
-- stock CachyOS windowrules.lua already covers PiP, gaming, modals, etc.).

-- TUI apps — float at 1000x720, centered.
-- Used by hexciri-agent (opencode), install/remove menus, maintenance,
-- network QR, reminders, share, hw disk-speedtest, setup, system, etc.
-- All of them launch via `xdg-terminal-exec --app-id=TUI.float`, so one
-- rule catches every TUI. Niri equivalent: match app-id="TUI\\.float",
-- open-floating + fixed 1000x720.
hl.window_rule({ match = { class = "^(TUI\\.float)$" }, float = true, size = { "1000", "720" }, center = true })

-- Fastfetch terminal (Mod+Alt+F) — float at 1210x720, centered.
hl.window_rule({ match = { class = "^(app\\.hexciri\\.ff)$" }, float = true, size = { "1210", "720" }, center = true })
