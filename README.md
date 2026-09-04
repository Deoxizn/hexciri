<div align="center">

<img src="branding/hexciri.png" alt="Hexciri" width="450">

</div>


Arch-based Niri + Noctalia distro. Own void, own mirrors policy, own theme engine.

## Install

1. Flash the Arch ISO, boot it (UEFI), connect network (`iwctl` for wifi).
2. Run one line 

```bash
curl -fsSL https://hexciri.dirty.pizza/bootstrap.sh | sudo bash
```

Flags only pre-fill defaults — everything is still asked:

| flag | default | notes |
|---|---|---|
| `--channel=stable\|bleeding` | `stable` | bleeding unlocks omarchy/bore/muqss kernels |
| `--kernel=stock\|lts\|omarchy\|bore\|muqss` | auto (LTS pin on 1xxx, stock otherwise) | custom kernels need bleeding |
| `--ref=<tag\|branch>` | newest `v*` tag | pin for testing |
| `--no-luks` | ask | skip the encryption prompt |

```bash
# example: bleeding + BORE from the first prompt on
curl -fsSL https://hexciri.dirty.pizza/bootstrap.sh | sudo bash -s -- --channel bleeding --kernel bore
```

3. Reboot → straight into Niri
Press `Mod+K` for the searchable keybinding list.

## Defaults (fresh install)

| slot | default | change it |
|---|---|---|
| terminal | `kitty` | `hexciri-defaults` → Terminal |
| shell | `fish` | `hexciri-defaults` → Shell |
| browser | `brave-origin` | `hexciri-defaults` → Browser |
| files | `strata` | `hexciri-defaults` → Files |
| editor | `zed` | `hexciri-defaults` → Editor |
| agent | `opencode` (`Mod+`` `) | `hexciri-defaults` → Agent |
| kernel | `linux` (+`linux-lts` fallback) | `hexciri-kernel` (bore/muqss on bleeding) |
| gpu | autodetect (mesa / nvidia-open / 580xx+LTS pin) | `hexciri-gpu` |
| theme | `sakurazuki` | `hexciri-theme-set` |
| channel | `stable` | `hexciri-channel-set` |
| boot | systemd-boot, plymouth splash, SDDM autologin | — |
| prompt/fetch | starship + fastfetch w/ emblem | `~/.config/starship.toml`, `~/.config/fastfetch/config.jsonc` |

## Channels

| channel | Arch mirror | pkgs | kernel menu |
|---|---|---|---|
| `stable` (default) | `stable-mirror.omarchy.org` | `pkgs.omarchy.org/stable` | `linux`, `linux-lts` |
| `bleeding` | `mirror.omarchy.org` | `pkgs.omarchy.org/edge` | + `linux-omarchy`, `-bore`, `-muqss` |

Stable is month-held pkgs; bleeding is normal Arch rolling release.


## GPU (autodetect, Niri needs modeset)

```bash
hexciri-gpu [--kernel=stock|lts|omarchy|bore|muqss] [-y]
```

| card | driver | kernel rule |
|---|---|---|
| Turing+ (RTX 2xxx+, GTX 16xx) | `nvidia-open` 6xx DKMS | any (`--kernel` free) |
| Maxwell/Pascal/Volta (incl. all 1xxx) | `nvidia-580xx` DKMS | **LTS only** (non-LTS `--kernel` refused) |
| pre-Maxwell | nouveau (no driver to install) | any |
| Intel/AMD only | mesa + vulkan per vendor | any |

Always applied on NVIDIA: nouveau blacklist, early-KMS modules, suspend
persistence, modeset flags on hexciri boot entries, reboot prompt.


## Theme engine (colors.toml)

```bash
hexciri-theme-list
hexciri-theme-set <name>
hexciri-theme-install <git-url> | hexciri-theme-remove <name>
```

State: `~/.local/state/hexciri/current/{theme,theme.name,background}`.
Hook: `~/.config/hexciri/hooks/theme-set.d/` → `noctalia-sync.sh` writes
`~/.config/noctalia/palettes/hexciri.json`, patches `config.toml` + Niri borders.

## Already on Arch?
Vanilla Arch with systemd-boot + NetworkManager? Skip the ISO flow:

```bash
git clone https://github.com/Deoxizn/hexciri.git ~/hexciri
cd ~/hexciri
./install.sh                     # stable channel
./install.sh --channel bleeding  # Rolling Release
```