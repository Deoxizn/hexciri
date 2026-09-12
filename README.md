<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

**CachyOS dotfiles: theme hook + menu**

Install CachyOS with a WM/Shell (Niri today, MangoWM planned), clone the
dots, run one script.

</div>

## What this is

hexciri is dots + scripts for a CachyOS box that already has a WM/Shell. What
the repo actually does: every menu option dispatches to a real controller in
`bin/`, and `hexciri-theme-set` recolors the desktop in one hook. It never
touches the installer, kernel, GPU stack, or package manager — those stay
CachyOS's.

What hexciri does own:

- **The menu** — every option in the root menu dispatches to a real controller
  in `bin/`: share & capture, hardware toggles, packages picker, power, lock,
  keybinds, network, themes, reminders, screen recording. Nothing dangles.
- **The theming** — one click (or `hexciri-theme-set <name>`) recolors the whole
  desktop, 30+ apps in all. 22 themes ship included; extras are one line each
  in a list.
- **Your wallpapers survive theme changes** — drop your own images into
  `~/.config/hexciri/wallpapers`, or point it at your own folder via
  `config/wallpaper-sources/extra.list`, and they show up in the picker and
  stay across every theme swap.
- **The keybindings, one source of truth** — rendered into Niri's config so
  they never drift. `hexciri-keybinds` prints them all; `Mod`+K searches them
  from a picker.

## Install

1. **Install CachyOS** with a WM/Shell (Niri today, MangoWM planned).
2. Bring the dots — curl or clone, same script:

```bash
curl -LO https://hexciri.dirty.pizza/install.sh
sh install.sh
```

or:

```bash
git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
~/.local/opt/hexciri/install.sh
```

That symlinks the controllers into `~/.local/bin` and re-applies the layer
via `bin/hexciri-sync`. Updating is a pull plus a re-run. Version is the git
SHA.

## Highlights

- **Themes that color everything** — one click recolors the whole desktop,
  30+ apps in all. 22 themes ship included; extras are one line each in a list.
- **Your wallpapers survive theme changes** — drop your own images into
  `~/.config/hexciri/wallpapers`, or point it at your own folder via
  `config/wallpaper-sources/extra.list`, and they stay across every theme swap.
- **Transparent terminals** — kitty at reduced background opacity with blur
  behind it, so your wallpaper shows through.
- **The keybindings, one source of truth** — rendered into Niri's config so
  they never drift. `hexciri-keybinds` lists every one; `Mod`+K searches it.

## Sources

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)
</content>
