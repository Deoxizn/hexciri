-- Hexciri — Hyprland fragment: Window rules (workspace targets, floating)
-- Required by hyprland.lua. Mirrors the niri window-rules.kdl samples: the same
-- named-workspace intent (browser/code/chat/media land on their workspaces) and
-- the same floating-popup list. Static hexciri defaults — not theme-generated.
--
-- Named-workspace selectors use the same "name:" form as the keybind render
-- (hl.dsp.focus({ workspace = "browser" }) ↔ workspace = "name:browser" rule).

hl.window_rule({ match = { class = "firefox" }, workspace = "name:browser" })
hl.window_rule({ match = { class = "(nvim|kitty|alacritty)" }, workspace = "name:code" })
hl.window_rule({ match = { class = "(discord|slack|Tg_Web)" }, workspace = "name:chat" })

-- Floating dialogs — always open as floating popups.
hl.window_rule({ match = { class = "pavucontrol" }, float = true })
hl.window_rule({ match = { class = "nm-connection-editor" }, float = true })
hl.window_rule({ match = { class = "blueman-manager" }, float = true })
hl.window_rule({ match = { class = "org.gnome.Calculator" }, float = true })
hl.window_rule({ match = { class = "org.gnome.Settings" }, float = true })
hl.window_rule({ match = { class = "feh" }, float = true })
hl.window_rule({ match = { class = "imv" }, float = true })

-- LocalSend — floating share dialog at 1100x700.
hl.window_rule({ match = { class = "localsend", title = "Share" }, float = true, size = { 1100, 700 } })