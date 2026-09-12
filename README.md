<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

**CachyOS × Niri × Noctalia**

A post-install layer for CachyOS: the menu, the theming, and the keybinding
source of truth. Not a distro. Not an installer. CachyOS brings the desktop
with no desktop, the kernels, the GPU stack, the firmware and the drivers —
hexciri layers the shell on top.

</div>

## What this is

hexciri turns a **CachyOS install with no desktop** into the desktop you
already know: Niri (the WM) + the Noctalia shell, all wired to one keybinding
menu and one theming system. Everything CachyOS already handles — GPU/HW
autodetection, driver install (its installer reads this machine's hardware and
pins the right mesa/nvidia stack itself), firmware, microcode, kernels and the
rolling release — is left to CachyOS. hexciri does not install, rebuild, hold
or swap any of it.

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

It owns nothing that CachyOS's installer, kernel or package manager already
does. Rolling release stays CachyOS's rolling release; stock kernels stay
stock.

## Install

1. **Install CachyOS** with the **no desktop** option (their installer does the
   GPU/HW detection, drivers, firmware and kernels for you).
2. Clone hexciri and run the layer:

```bash
git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
~/.local/opt/hexciri/install.sh
```

That symlinks the controllers into `~/.local/bin` and wires the configs once.
Updating is just a pull plus the layer re-apply.

Because it's a clone, not a served artifact, there's no bootstrapping URL, no
channel ceremony, no release cadence. Version is the git SHA.

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
- **It's CachyOS. Only calmer.** — same package manager, same knowledge:
  everything that runs on CachyOS runs here. The stock channels CachyOS ships
  stay the default; hexciri just makes it look like home.

## Sources

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)
</content>
