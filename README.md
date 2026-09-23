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
forever).

Your stuff, by path: wallpapers live in `~/.config/hexciri/wallpapers`
(extra folders in `~/.config/hexciri/wallpaper-sources/extra.list`);
extra themes in `~/.config/hexciri/theme-sources/extra.list` — one
`owner/repo` per line. Both survive every swap and update.

## Apps

Install adds what hexciri needs (kitty, Zed, Brave Origin, OpenCode…) and
removes what they replace — once. Afterwards your installs and removals are
yours; updates never undo them. File manager and image viewer follow the WM:
strata + qview on Hyprland, nautilus + imv on Niri — switchable any time in
`System > Default Apps`.

## Niri or Hyprland

Same menu, themes and keys on both — only the tiling style differs:

| | Niri | Hyprland |
|---|---|---|
| Tiling | scrollable columns | classic tiles + floating |
| `Mod+L` | — (nothing to cycle) | cycles dwindle → scrolling → monocle |
| Files / images | nautilus + imv | strata + qview |

Switch without reinstalling:

```bash
hexciri-wm-switch --to niri        # or hyprland; --dry-run plans first
```

It installs the other side, moves your old configs to a timestamped backup,
flips your defaults, and removes what the new WM replaces. Relogin, pick the
new session, done.

## Keys that matter

`Mod` is Super. All of them, searchable: `Mod+K`.

| Keys | Do |
|---|---|
| `Mod+Alt+Space` | hexciri menu |
| `Mod+Space` | app launcher |
| `Mod+Return` | terminal |
| `Mod+Q` | close window |
| `Mod+T` | float / tile toggle |
| `Mod+L` | cycle layouts (Hyprland) |
| `Mod+1…9` | workspaces (`Shift` moves windows) |
| `Mod+Shift+F` | files |
| `Mod+Shift+B` | browser |
| `Mod+Shift+S` / `Mod+Shift+C` | web search / calculator |
| `Mod+Shift+T` | system monitor |
| `Mod+Ctrl+V` | clipboard history |
| `Mod+Escape` | power menu |

Search and calculator aren't apps — they're menu modes: `Mod+Shift+S`
searches the web (and your files), `Mod+Shift+C` is a full calculator, both
with history. `Mod+Ctrl+V` is the same idea for everything you copied.

## When something looks off

1. Press `Update > Hexciri` — every press re-applies links, keybinds,
   firewall and sshd settings, and heals anything missing.
2. Still off? Re-run `install.sh` — safe on a working box too.
3. Forgot a key? `Mod+K`. Need a doc? `Learn` in the root menu.
