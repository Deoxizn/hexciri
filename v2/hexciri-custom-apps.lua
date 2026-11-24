-- Hexciri custom window rules (2026-11-24, Devi: Hexciri Lua in the
-- theme hook work, custom parts only). Omarchy's apps/ already covers
-- Steam, Battle.net, terminals and the TUI tag; this file is ONLY what
-- it does not: the TUI float size, the fastfetch float size, and the
-- mpv / imv opacity overrides. Installed by the installer into
-- default/hypr/apps/hexciri.lua; apps.lua require_all.files()
-- auto-loads every file in that dir, so no edit to hexciri.lua is
-- needed. Syntax-checked at install time.

-- TUI apps: float at 1000x720, centered. Every TUI launches via
-- xdg-terminal-exec --app-id=TUI.float, so one rule catches them all
-- (agent console, install/remove menus, maintenance, network QR, etc).
o.window({ class = "^(TUI\\.float)$" }, { float = true, size = { 1000, 720 }, center = true })

-- Fastfetch terminal (Mod+Alt+F): float at 1210x720, centered.
o.window({ class = "^(app\\.hexciri\\.ff)$" }, { float = true, size = { 1210, 720 }, center = true })

-- Media player: floating, follows the video's native resolution
-- (mpv autofit in ~/.config/mpv/mpv.conf), so no size here. PiP is
-- excluded by title so it keeps the stock size/pin treatment.
-- Opaque, always: 1.0 override, Devi 2026-11-11.
o.window({ class = "^(mpv)$", title = "negative:^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, { float = true, center = true, opacity = "1.0 override 1.0 override" })

-- Image viewer: opaque, always: 1.0 override, Devi 2026-11-11.
o.window({ class = "^(imv)$" }, { opacity = "1.0 override 1.0 override" })
