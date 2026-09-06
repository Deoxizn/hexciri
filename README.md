<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

Arch × Niri × Noctalia

[hexciri.dirty.pizza](https://hexciri.dirty.pizza)

</div>

## Highlights

- **Themes that color everything** — one click (or `hexciri-theme-set <name>`)
  recolors the whole desktop, 30+ apps in all. 22 themes ship included; extras
  are one line each in a list.
- **Your wallpapers survive theme changes** — drop your own images into
  `~/.config/hexciri/wallpapers`, or point it at your own folder via
  `wallpaper-sources/extra.list`, and they show up in the picker and stay across
  every theme swap.
- **Transparent terminals** — kitty at reduced background opacity with niri
  blur behind it, so your wallpaper shows through.
- **Gaming, ready** — Steam, Heroic, Lutris, RetroArch, Minecraft, Battle.net,
  GeForce NOW, Xbox Cloud, controllers, GPU setup.
- **A minimal Arch experience** — your system starts clean: Arch, Niri, and
  the Noctalia shell — nothing you didn't ask for; add the rest on demand.
- **Everything's just files** — the theming engine is literally two text lists
  you can read and edit: `theme-sources/extra.list` (extra themes) and
  `wallpaper-sources/extra.list` (extra wallpaper folders). Easy to tweak, back
  up, and version. And updates never overwrite your edits — an edited config
  stays yours, with the new default saved alongside as `<file>.hexciri`.

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
| agent | `opencode` (`Mod+`` `) | `hexciri-defaults` → Agent |
| kernel | auto: `linux` (stock), `linux-lts` pinned on legacy NVIDIA | `hexciri-kernel` (custom post-install) |
| gpu | autodetect (mesa / nvidia-open / 580xx+LTS pin) | `hexciri-gpu` |
| monitors | preconfigured (scale 2) | `~/.config/niri/config.kdl` |
| bluetooth | on (bluez + bar widget) | — |
| theme | `sakurazuki` | `hexciri-theme-set` |
| channel | `stable` | `hexciri-channel-set` |
| boot | systemd-boot, SDDM password/fingerprint greeter | — |
| prompt/fetch | starship + fastfetch w/ emblem | `~/.config/starship.toml`, `~/.config/fastfetch/config.jsonc` |

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
Repo**, or `hxup`'s system update pulls the repo as part of `pacman -Syu`); the
repo is never reinstalled on an update, so no reinstall ever needs sudo.

> **Upgrading an install older than v0.1.3?** Pre-0.1.3 installs hard-copied
> commands into `/usr/local/bin` (and until v0.1.1 had no self-update at all),
> so a mere `pacman -Syu` won't migrate them. Do this once:
>
> ```bash
> git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
> ~/.local/opt/hexciri/install.sh
> ```
>
> That pull + bootstrap clears the stale `/usr/local/bin/hexciri-*` copies, links
> the commands into `~/.local/bin`, and re-wires the one `hexciri-sync` hook —
> afterwards the normal pull-based updates work as described above. v1 configs
> are kept as-is (install.sh never clobbers edits), so the migration also adds
> the `~/.local/bin` PATH entry your old niri config was missing — without it,
> every `hexciri-*` keybind fails silently once the old /usr/local copies are
> gone.

## Sources

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)