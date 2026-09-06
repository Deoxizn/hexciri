<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

Arch × Niri × Noctalia

[hexciri.dirty.pizza](https://hexciri.dirty.pizza)

</div>

## Install

1. Flash the Arch ISO, boot it (UEFI), connect network (`iwctl` for wifi).
2. Run it 

```bash
curl -LO https://hexciri.dirty.pizza/hexciri && sh hexciri
```

Pipe works identically: `curl -fsSL https://hexciri.dirty.pizza/hexciri | bash`.

The kernel is chosen automatically — stock `linux`, or `linux-lts` pinned on
legacy NVIDIA. Custom kernels (`omarchy` / `bore` / `muqss`) are a post-install
choice via `hexciri-kernel`, not a first-run decision.

The disk is left unencrypted — the login gate is the SDDM password screen
(minimal themed greeter), there is no disk-encryption step to answer.

3. Reboot → straight into Niri
Press `Mod+K` for the searchable keybinding list.

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


## GPU

Autodetected at install (mesa / `nvidia-open` / `580xx` with a hard LTS pin
on NVIDIA GTX 1xxx or older cards). To change later, re-run `hexciri-gpu`.


## Theme engine (colors.toml)

One `colors.toml` recolors the whole desktop. Themes are list-driven — there is
no manual catalog:

- **Omarchy defaults** (22) ride along with the repo sync.
- **Extra themes** are one `<owner>/<name>` per line in an `extra.list` (or a
  full URL when the repo doesn't follow the naming); **Update ▸ Themes** clones,
  pulls and prunes extras to match the list, so removing a line removes a theme.

State: `~/.local/state/hexciri/current/{theme,theme.name,background}`.
Hooks: `~/.config/hexciri/hooks/theme-set.d/` — 29 drop-ins that push the active
palette into 30+ apps (Noctalia + Niri borders, kitty, fish, GTK, Qt/qt6ct,
Discord/Vesktop, Spotify, Zed, VS Code, Firefox, Steam, tmux, zellij, …). The
`noctalia-sync.sh` hook writes `~/.config/noctalia/palettes/hexciri.json` and
patches the shell's config; Strata follows the theme live, no reopen needed.

**Your wallpapers survive theme changes.** A persistent user store —
`~/.config/hexciri/wallpapers` — is merged into the active theme's backgrounds
as `zz-user-*` symlinks, alongside whatever the theme ships. Extra directories
(a `~/Pictures/Wallpapers`, NFS mounts, …) go in `config/wallpaper-sources/extra.list`.
**Update ▸ Wallpaper** re-runs the merge on demand; a theme swap preserves your
links and never stomps the wallpaper you're currently using.

## Highlights

- **Your wallpapers survive theme changes** — personal images merge into the
  active theme's backgrounds as symlinks and stay put across swaps; the picker
  shows theme images AND your set, and theme switches keep your current
  wallpaper.
- **Theme engine** — one `colors.toml` recolors the desktop via a 29-hook set;
  themes are list-driven (Omarchy defaults ride the sync, extras live in one
  editable list), and Strata follows the theme live.
- **Transparent terminals** — kitty runs at reduced background opacity with
  niri window-effect blur behind it. No focus ring / border: niri draws those
  as a solid rectangle behind the window (per its FAQ), which would cover the
  translucency.
- **Gaming** — `hexciri-gaming`: Steam, Heroic, Lutris, RetroArch, Minecraft,
  Battle.net (umu-launcher + GE-Proton), GeForce NOW, Xbox Cloud, GPU setup,
  Xbox controllers. `hexciri-packages` → Gaming for launchers.
- **Never-clobber config deploy** — install.sh sha-tracks configs: untouched
  ones update in place; if you've edited one, yours stays and the repo default
  lands as `<file>.hexciri` alongside (backups in `~/.config/hexciri-backup/`).
- **Floating maintenance** — repo syncs and wallpaper rescans open in their own
  blur-floated terminal window instead of taking over a workspace.

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