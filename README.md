<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

Arch × Niri × Noctalia

[hexciri.dirty.pizza](https://hexciri.dirty.pizza)

</div>

## Highlights

- **Your WM, your shell — never locked in** — ships on Niri + Noctalia,
  but Hyprland, Sway and Mango are installed-and-configured options too,
  with or without a desktop shell. Switch with one command or one menu pick:
  your monitors, keybindings and theme follow you to the new one.
- **Themes that color everything** — one click (or `hexciri-theme-set <name>`)
  recolors the whole desktop, 30+ apps in all. 22 themes ship included; extras
  are one line each in a list.
- **Your wallpapers survive theme changes** — drop your own images into
  `~/.config/hexciri/wallpapers`, or point it at your own folder via
  `wallpaper-sources/extra.list`, and they show up in the picker and stay across
  every theme swap.
- **Transparent terminals** — kitty at reduced background opacity with blur
  behind it, so your wallpaper shows through.
- **Gaming, ready** — Steam, Heroic, Lutris, RetroArch, Minecraft, Battle.net,
  GeForce NOW, Xbox Cloud, controllers, GPU setup.
- **A minimal Arch experience** — your system starts clean: Arch, your chosen
  WM, and the Noctalia shell — nothing you didn't ask for; add the rest on
  demand.
- **It's Arch. Only calmer.** — same package manager, same knowledge:
  everything that runs on Arch runs here. But the default repo holds packages
  back a month, so updates don't surprise you. Rolling release is one `--channel
  bleeding` away.

## Install

Boot the Arch ISO, then run:

```bash
curl -LO https://hexciri.dirty.pizza/hexciri && sh hexciri
```

## Your WM, your shell

Hexciri is not tied to one window manager. You pick the pair:

| WM | shell |
|---|---|
| `niri` (default) | `noctalia` (default) |
| `hyprland` | `none` (bare WM) |
| `sway` | |
| `mango` | |

Switching is one menu pick (**System ▸ Session**) or one command:

```bash
hexciri-session-set wm=sway shell=noctalia
```

What happens: the new WM is installed, a login entry is created, and your
monitors, environment, input settings, keybindings and theme are carried over
into that WM's own config format. Your current session is untouched — log out,
pick the new WM at the login screen, done. Switch back any time.

Fresh installs pick with `install.sh --wm sway --shell none`; nothing is
installed for a WM you never choose.

## Themes

Switch themes from the **Themes** menu or `hexciri-theme-set <name>` — colors,
windows, terminals and apps (30+) all change together. 22 ship included; pick
up extras and keep your own wallpapers with the list below.

## Extra themes & wallpapers

Both are plain text lists — add a line, run **Update ▸ Themes** (themes) or
**Update ▸ Wallpaper** (wallpapers), done. Remove a line and it's gone.

**Extra themes** — `~/.config/hexciri/theme-sources/extra.list`:

```text
# one theme per line, owner/name form
HANCORE-linux/aamis
OldJobobo/dracula
```

**Extra wallpaper folders** — `~/.config/hexciri/wallpaper-sources/extra.list`:

```text
# one folder per line; ~ means your home
~/Pictures/Wallpapers
/mnt/Photos/wallpapers
```

Not a list person? The plain `~/.config/hexciri/wallpapers` folder works too —
drop files in and they're picked up, no list entry needed, and they stay across
theme changes.

## Defaults

| slot | default | change it |
|---|---|---|
| WM | `niri` | `hexciri-session-set wm=…` (System ▸ Session) |
| shell | `noctalia` | `hexciri-session-set shell=…` |
| terminal | `kitty` | `hexciri-defaults` → Terminal |
| shell | `bash` (login) · `fish` (kitty) | `hexciri-defaults` → Shell |
| browser | `brave-origin` | `hexciri-defaults` → Browser |
| files | `strata` | `hexciri-defaults` → Files |
| editor | `zed` | `hexciri-defaults` → Editor |
| agent | `opencode` (`Mod`+backtick) | `hexciri-defaults` → Agent |
| kernel | auto: `linux` (stock), `linux-lts` pinned on legacy NVIDIA | `hexciri-kernel` (custom post-install) |
| gpu | autodetect (mesa / nvidia-open / 580xx+LTS pin) | `hexciri-gpu` |
| monitors | preconfigured (scale 2) | in your WM's own config |
| bluetooth | on (bluez + bar widget) | — |
| theme | `sakurazuki` | `hexciri-theme-set` |
| channel | `stable` | `hexciri-channel-set` |
| boot | systemd-boot, SDDM password/fingerprint greeter | — |
| prompt/fetch | starship + fastfetch w/ emblem | `~/.config/starship.toml`, `~/.config/fastfetch/config.jsonc` |

`Mod` is the Super key. Press **`Mod`+K** — or run `hexciri-keybinds` — for a
searchable list of every keybind for whichever WM you're on. Keybindings are
one and the same across WMs, so muscle memory survives a switch.

**Main ones:**

| key | does |
|---|---|
| `Mod`+D | open the app launcher |
| `Mod`+Return | open a terminal |
| `Mod`+Space | quick run bar (fuzzel) |
| `Mod`+Q | close the focused window |
| `Mod`+F | fullscreen the window |
| `Mod`+1 … `Mod`+9, `Mod`+0 | jump to a workspace |
| `Mod`+Shift+1 … 9 | move the window to a workspace |
| `Mod`+Left/Right or H/L | move between windows |
| `Mod`+Ctrl+arrows | drag a window along |
| `Mod`+Ctrl+L | lock the screen |
| `Mod`+Print | screenshot the screen |
| `Ctrl`+Print | screenshot and copy a chosen area |
| `Alt`+Print | record the screen |
| `Mod`+Escape | power menu (shutdown/reboot/logout…) |

Volume, brightness and mic keys work as labeled.

## Channels

| channel | Arch mirror | pkgs | kernel menu |
|---|---|---|---|
| `stable` (default) | `stable-mirror.omarchy.org` | `pkgs.omarchy.org/stable` | `linux`, `linux-lts` |
| `bleeding` | `mirror.omarchy.org` | `pkgs.omarchy.org/edge` | + `linux-omarchy`, `-bore`, `-muqss` |

Stable — month-held packages; bleeding — normal Arch rolling release.

## Already on Arch?
Vanilla Arch with systemd-boot + NetworkManager? Skip the ISO flow:

```bash
git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
~/.local/opt/hexciri/install.sh  # stable channel
~/.local/opt/hexciri/install.sh --channel bleeding  # Rolling Release
```

The clone is the runtime — install.sh symlinks its commands into `~/.local/bin`
and wires the configs, once at bootstrap. Updating is just a pull (**Update ▸
Repo**, or `hxup`'s system update pulls the repo as part of `pacman -Syu`).

> **Upgrading an install older than v0.1.3?** Old installs hard-copied commands
> into `/usr/local/bin`; newer ones use symlinks, so a plain `pacman -Syu`
> won't fix a stale one. Run this once:
>
> ```bash
> git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
> ~/.local/opt/hexciri/install.sh --update
> ```
>
> That replaces the old copies with symlinks and keeps your settings as they
> are (it never touches installed packages, kernels, services or the channel).
> Afterwards, the normal pull-based updates apply. What changed, release by
> release? Read `CHANGELOG.md`.

## Sources

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Hyprland](https://github.com/hyprwm/Hyprland) × [Sway](https://github.com/swaywm/sway) × [MangoWM](https://github.com/mangowm/mango) × [dwl](https://github.com/djpohly/dwl) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)