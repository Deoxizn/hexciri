-- hexciri — env rendered for hyprland
-- source: config/niri/env.kdl (niri fragment; regenerate with: hexciri-config-render env hyprland)
-- XDG_CURRENT_DESKTOP follows the target WM; the rest carry the Wayland stack
-- verbatim from the niri env fragment.
hl.env("PATH", "/home/devi/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("GDK_BACKEND", "wayland,x11")

