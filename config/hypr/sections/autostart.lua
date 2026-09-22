-- Hexciri autostart (machine-managed section — see sync_hyprland).
-- Mirrors config/niri/cfg/autostart.kdl.

hl.on("hyprland.start", function()
    hl.exec_cmd("hexciri-theme-ensure")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
