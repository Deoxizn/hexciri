<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

Arch × Niri × Noctalia

[hexciri.dirty.pizza](https://hexciri.dirty.pizza)

</div>

## Highlights

- **Ships on Niri + Noctalia, out of the box** — the scrollable-tiling
  Wayland compositor with the Noctalia desktop shell. No swapping, no lock-in
  to learn around: monitors, keybindings and theme all follow one config.
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
- **A minimal Arch experience** — your system starts clean: Arch, Niri,
  and the Noctalia shell — nothing you didn't ask for; add the rest on
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
| terminal | `kitty` | `hexciri-defaults` → Terminal |
| shell | `bash` (login) · `fish` (kitty) | `hexciri-defaults` → Shell |
| browser | `brave-origin` | `hexciri-defaults` → Browser |
| files | `strata` | `hexciri-defaults` → Files |
| editor | `zed` | `hexciri-defaults` → Editor |
| agent | `opencode` (`Mod`+backtick) | `hexciri-defaults` → Agent |
| kernel | auto: `linux` (stock) on fresh installs | `hexciri-kernel` (custom post-install) |
| gpu | autodetect (mesa/vulkan per vendor; nvidia-open Turing+, 580xx legacy Maxwell/Pascal/Volta via AUR build) | `hexciri-gpu` |
| monitors | preconfigured (scale 2) | `~/.config/niri/monitors.kdl` |
| bluetooth | on (bluez + bar widget) | — |
| theme | `sakurazuki` | `hexciri-theme-set` |
| channel | `stable` | `hexciri-channel-set` |
| boot | systemd-boot, SDDM password/fingerprint greeter | — |
| prompt/fetch | starship + fastfetch w/ emblem | `~/.config/starship.toml`, `~/.config/fastfetch/config.jsonc` |

`Mod` is the Super key. Press **`Mod`+K** — or run `hexciri-keybinds` — for a
searchable list of every keybind. Keybindings are one source of truth, rendered
into niri's config, so they never drift.

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

**Fuzzel mode launchers** (`hexciri-fuzzel`, walker/elephant-style — same themed box as the app launcher):

| key | mode |
|---|---|
| `Mod`+Shift+S | web search (default provider) |
| `Mod`+Shift+C | calculator (qalc → clipboard + notify) |

Search providers and the default are configurable — `~/.config/hexciri/search-providers`
(one line per provider, see the file's comments) and **System ▸ Config ▸ Search
provider** picker. The same picker sets which provider the `Mod`+Shift+S bind
uses; per-provider search is also available on demand via
`hexciri-fuzzel search <name>`. Volume, brightness and mic keys work as labeled.

## Menus

Everything reachable from `Mod`+Alt+Space (root menu). `hexciri-*` commands
dispatch the same menus from a terminal.

```
Root menu (Mod+Alt+Space)
├─ Applications            (hexciri-launch)
├─ System
│  ├─ Config
│  │  ├─ Niri              (all fragments)
│  │  ├─ Noctalia config
│  │  ├─ Search provider   (pick the default web search)
│  │  ├─ Search providers file  (edit the provider list)
│  │  ├─ Fastfetch config
│  │  ├─ Hexciri lockscreen
│  │  └─ Hooks
│  ├─ Default Apps
│  ├─ Kernel
│  ├─ Maintenance
│  ├─ Network
│  ├─ Security
│  └─ Reset defaults
├─ Themes                  (hexciri-theme-set)
├─ Update                  (hexciri-update)
├─ Clipboards              (hexciri-clipboard)
└─ Power menu              (Mod+Escape → hexciri-power)
```

Submenus are `> `-suffixed rows in fuzzel; `Mod`+K lists every keybind.

## Channels

| channel | Arch mirror | pkgs | kernel menu |
|---|---|---|---|
| `stable` (default) | `stable-mirror.omarchy.org` (month-held) | `pkgs.omarchy.org/stable` | `linux`, `linux-lts` |
| `bleeding` | official Arch (`geo.mirror.pkgbuild.com`) | `pkgs.omarchy.org/edge` | `linux`, `linux-lts`, omarchy EEVDF + BORE |

Stable — month-held packages (kept for users who want slower, vetted releases);
bleeding — normal Arch rolling release plus the omarchy **edge** repo, which
carries omarchy's own kernel line as ordinary repo packages: `linux-omarchy`
(EEVDF) and `linux-omarchy-bore` (BORE). Install/update them via
**System ▸ Kernel** (or `hexciri-kernel`), where **Recommended (auto-detect)**
has `hexciri-scheduler` read this machine (NVIDIA dGPU / X3D → BORE, else
EEVDF) and pick the matching build. Because they're real repo packages they
update with plain `pacman -Syu` — no fetch loop, no AUR rebuilds, and the
omarchy keyring is bootstrapped on install. Stock `linux`/`linux-lts` stay the
kernel-menu base everywhere; omarchy kernels are a bleeding-channel extra.
Legacy 580xx drivers are AUR-built in dependency order by `hexciri-gpu`.

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

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)