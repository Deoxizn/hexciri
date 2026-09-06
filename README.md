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
  `~/.config/hexciri/wallpapers` and they show up in the picker and stay across
  every theme swap.
- **Transparent terminals** — kitty at reduced background opacity with niri
  blur behind it, so your wallpaper shows through.
- **Gaming, ready** — Steam, Heroic, Lutris, RetroArch, Minecraft, Battle.net,
  GeForce NOW, Xbox Cloud, controllers, GPU setup.
- **A minimal Arch experience** — your system starts clean: Arch, Niri, and a
  themed shell — nothing you didn't ask for; add the rest on demand.
- **Everything's just files** — theming and state live in plain, readable lists
  and configs in your home, so they're easy to tweak, back up, and version. And
  updates never overwrite your edits — an edited config stays yours, with the
  new default saved alongside as `<file>.hexciri`.

## Install

1. Flash the Arch ISO, boot it (UEFI), connect network (`iwctl` for wifi).
2. Run it

```bash
curl -LO https://hexciri.dirty.pizza/hexciri && sh hexciri
```

3. Reboot → straight into Niri. Press `Mod+K` for the searchable keybinding list.

No prompts to answer — kernel, GPU, and channel are all decided for you. The
disk is left unencrypted; the login gate is the SDDM password screen.

## Themes

Switch the whole look of your desktop whenever you like — colors, windows,
terminals and apps all change together. Pick a theme from the **Themes** menu
or run `hexciri-theme-set <name>`.

**22 themes ship with Hexciri**, and you can add more any time — extra themes
are just one line each (`owner/name`) in a simple list. Add a line, run
**Update ▸ Themes**, and it's installed. Remove the line and it's gone.

A theme recolors practically everything you touch:

- the **bar** and desktop shell
- the **terminal** (kitty, fish, fzf, foot, and the cava visualization)
- your **browser** (Firefox, Zen, qutebrowser, hermes)
- your **editor** (Zed, VS Code, Cursor, Windsurf, Typora, Obsidian)
- **Discord/Vesktop, Spotify, Steam, Heroic, tmux, zellij**, GTK and Qt apps,
  superfile and more — 30+ apps in all.

**Your wallpapers stick around.** Drop your own images into
`~/.config/hexciri/wallpapers` — they show up in the wallpaper picker beside
the theme's own, survive every theme change, and a theme swap doesn't overwrite
the wallpaper you're currently using.

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

## Defaults (fresh install)

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
| monitors | preconfigured (laptop panel `eDP-1`, scale 2; desktops name their output) | `~/.config/niri/config.kdl` |
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

Stable is month-held pkgs; bleeding is normal Arch rolling release.

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
> afterwards the normal pull-based updates work as described above.

## Sources

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)