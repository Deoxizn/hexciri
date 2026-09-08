# Hexciri 1.5 plans

Status: thinking, not committed to. Two directions: more shell choice, and a kernel change.

The v1.4 shell plumbing is deliberately generic — a shell is (a) a package,
(b) a spawn line in each WM's autostart, (c) a theme hook target, (d) an IPC
surface. Everything below is scoping how far that plumbing stretches.

## 1. Shell matrix: noctalia → more

Today `~/.config/hexciri/shell` accepts `noctalia|none` (`hexciri-session`
tolerates `caelestia` only via `pgrep quickshell`). The obvious 1.5 additions:

| shell | taxonomy | spawn the machinery needs |
|-------|----------|------------------------------|
| `noctalia` | native shell (default) | `noctalia` — done |
| `none` | no shell | comment the spawn out — done |
| `caelestia` | **Quickshell-based** shell (the omarchy x caelestia remux on this machine; hyprland-tied) | `quickshell -c caelestia` + its config under `~/.config/caelestia/` |
| `quickshell` | the toolkit itself — bare quickshell example/Zui config, no shell branding | `quickshell` (whatever its default config is) |
| `dankshell` | Quickshell-based homegrown shell (DankMaterialShell) | custom QML config + spawn — **needs research: exact package, config path, theming surface** |

The Quickshell family shares the runtime (`quickshell`, Qt6/QML); they differ
by **config**, not by daemon. That keeps the 1.5 work uniform: add the shell's
config into the repo, teach the spawn/theme/IPC layers the new name.

### What "add a shell" touches (from v1.4 machinery)

1. **package list** in `install.sh` per pick (today: `noctalia` under `SHELL_PKGS`).
2. **autostart spawn per WM** — `install.sh` swaps the spawn line per WM and
   comments it for `shell=none` (niri KDL / hyprland `hl.exec_cmd` / sway `exec`
   / mango `exec-once`). A new shell = a new spawn value in that same line.
3. **theme hook** `hooks/theme-set.d/hexciri-sync.sh` — step 1 is the shell
   render (palette → shell config). A Quickshell shell needs its own QML/color
   surface; noctalia's `config.toml` + qt6ct + wallpaper steps stay untouched.
4. **IPC** `bin/hexciri-compositor` — screenshot/grim are WM-side, not shell-side;
   **lock** is the shell-owned op. Quickshell shells would need lock via their own
   session-lock surface or the generic `swaylock` fallback.

Keybindings are WM-side already (`intents.toml` → per-WM render) — a shell swap
touches nothing there.

### Open questions

- Is `quickshell` (bare toolkit) a meaningful choice, or should 1.5 only ship
  caelestia + dankshell? (bare toolkit = no bar/lock/OSD — the `none` corner
  with extra steps)
- Caelestia is Hyprland-tied (the remux is); dankshell support matrix TBD. Do
  these live only under `wm=hyprland`, or is any-WM × any-shell still the rule?
- Theming: DankMaterialShell's palette hooks (config path, live-reload) are
  unknown here — research needed before a per-shell render is scoped.

## 2. Kernel: omarchy edge repo on bleeding, CachyOS removed (final)

Decided + shipped (revised — CachyOS direction reverted after the second box
proved the direct-fetch path fragile): **CachyOS is gone entirely**
(`bin/hexciri-cachyos`, tier fetch, driver fetch, AUR ignore-stamp — all
deleted). Custom kernels now come from the **omarchy edge repo** as ordinary
repo packages (install + update via plain `pacman -Syu`, no fetch loop, no AUR
rebuilds). Custom kernels stay post-install personalization (System ▸ Kernel),
so `--kernel` stays `stock|lts` and install.sh never stages them.

- `pacman-bleeding.conf` ships `[omarchy]` → `https://pkgs.omarchy.org/edge/$arch`;
  `install.sh` bootstraps omarchy-keyring whenever the deployed conf carries the
  repo. Stable stays **stock/lts only** (vetted repo) — omarchy kernels are a
  bleeding extra, matching "stability-first users don't switch kernels anyway".
- `bin/hexciri-scheduler` — reads this machine (NVIDIA sysfs GPU, X3D CPU, RAM,
  laptop battery) and recommends **BORE** for interactive/gaming or **EEVDF**;
  runs the detect pass at install and again on kernel change; `run` applies it.
- `bin/hexciri-kernel` — menu now `Recommended (auto-detect)`, Stock, LTS,
  `linux-omarchy` (EEVDF), `linux-omarchy-bore` (BORE) + Status.
- Legacy 580xx drivers — EOL in official repos — now **AUR-built** by
  `hexciri-gpu` (`aur_install_580xx`: full `nvidia-580xx` split in dependency
  order as a regular user, temp passwordless-pacman sudoers rule, signing-key
  import, `--skippgpcheck` fallback). This fixes the second-box failure where the
  old chroot resolver silently skipped the driver and Pascal booted to nouveau
  (black-screen hard-lock). Updates ride the existing `yay -Sua` pass.
- `hexciri-update` has no cachyos refresh loop anymore; `hexciri-gpu` /
  `hexciri-gaming` kernel lists + boot-default mapping moved to omarchy names.
- Per-PC makepkg tuning (`lib/makepkg-tuning.sh`) — jobs + CPU tier written to
  `/etc/makepkg.conf.d/` on fresh installs and by `hexciri-sync` on every update.

## 3. Carry-over / build order (proposed, not approved)

1. Research dankshell (config path, theming surface, compositor support).
2. shell spawn generalization — the install.sh autostart swap already keys off
   `$SHELL_PICK`; widen it from `noctalia|none` to the new set.
3. hexciri-session / session-set / install `known_shell` lists — one shared set.
4. Theme hook: add per-shell render fragment, noctalia paths untouched.
5. Kernel: ✅ done (see §2) — omarchy-edge kernels + AUR 580xx, scheduler
   autodetect, makepkg tuning, CachyOS removed.
6. Validate: hyprland+caelestia (this machine's ground truth), niri+noctalia
   (default), both channels.