-- hexciri — autostart rendered for hyprland
-- source: config/niri/autostart.kdl (niri fragment; regenerate with: hexciri-config-render autostart hyprland)

hl.on("hyprland.start", function()
    hl.exec_cmd("hexciri-theme-ensure")
    hl.exec_cmd("bash -c 'hexciri-strata-install --check >/dev/null 2>&1'")
    hl.exec_cmd("noctalia")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("bash -c 'wl-paste --type text --watch cliphist store'")
    hl.exec_cmd("bash -c 'wl-paste --type image --watch cliphist store'")
    hl.exec_cmd("bash -c 'systemctl --user import-environment $(env | cut -d= -f1) && dbus-update-activation-environment --systemd --all'")
end)

