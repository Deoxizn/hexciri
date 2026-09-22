<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

**CachyOS dotfiles for Niri and Hyprland: a real menu and a theme engine.**

</div>

## What this is

CachyOS is the house (Arch Linux, tuned for speed). hexciri is the furniture:
a menu where every button works, and one theme pick that recolors all 30+
apps at once. It never touches the foundation — kernel, drivers and updates
stay exactly as CachyOS ships them.

Niri and Hyprland are just two different window managers it runs on. Same
menu, same themes, same keys on both.

## Install

1. Install CachyOS with Niri or Hyprland (normal installer, pick either).
2. Run one script, answer two questions (system update? reboot?):

```bash
curl -LO https://hexciri.dirty.pizza/install.sh
sh install.sh
```

Done. Safe to re-run any time — it only fills in what's missing. Staying
current later is `Update > Hexciri` from the menu.

## The menu

`Mod+Alt+Space` opens nine buckets: Learn, Packages, Share & Capture,
Reminders, Hardware, Themes, System, Restart, Update. Every row does its
thing; `Esc` always goes back a level. (`Mod+Space` is the app launcher,
`Mod+K` searches every keybind.)

## Themes

```bash
hexciri-theme set <name>     # recolors everything at once
hexciri-theme list           # pick from a preview list
```

One pick repaints your terminal, editor, browser, bar, lock screen, file
manager and login screen from the same palette — 22 themes ship, any GitHub
theme is one command away, and your own scripts in
`~/.config/hexciri/hooks/theme-set.d/` run along (edits are kept as yours
forever). Drop images in `~/.config/hexciri/wallpapers` and they show up in
every theme's picker, surviving every swap.

## Apps

Install adds what hexciri needs (kitty, Zed, Brave Origin, OpenCode…) and
removes what they replace — once. Afterwards your installs and removals are
yours; updates never undo them. File manager and image viewer follow the WM:
nemo + qview on Hyprland, nautilus + imv on Niri — switchable any time in
`System > Default Apps`.

## Niri vs Hyprland

Nearly everything is shared. The few WM-specific pieces (keybinds, autostart,
border colors) install only for whichever WM is active, detected automatically
(`~/.config/hexciri/wm` pins it).

Switch without reinstalling:

```bash
hexciri-wm-switch --to niri        # or hyprland; --dry-run plans first
```

It installs the other side, moves your old configs to a timestamped backup,
flips your defaults, and removes what the new WM replaces. Relogin, pick the
new session, done.

## Keys that matter

`Mod` is Super. `Mod+Return` terminal · `Mod+Q` close · `Mod+T` float toggle ·
`Mod+L` cycle layouts · `Mod+1…9` workspaces (`Shift` moves windows) ·
`Mod+Shift+F` files · `Mod+Shift+B` browser · `Mod+Escape` power ·
`Mod+Ctrl+V` clipboard. All of them: `Mod+K`.

## When something looks off

1. Press `Update > Hexciri` — every press re-applies links, keybinds,
   firewall and sshd settings, and heals anything missing.
2. Still off? Re-run `install.sh` — safe on a working box too.
3. Forgot a key? `Mod+K`. Need a doc? `Learn` in the root menu.
