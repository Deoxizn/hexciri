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

## 2. Kernel: CachyOS over omarchy?

Today: `--kernel stock|lts|omarchy|bore|muqss`. The omarchy kernels
(`linux-omarchy[-bore|-muqss]`) come from the omarchy repo/mirror and are the
framework's custom kernel story.

1.5 candidate: re-add **Chaotic-AUR** (it shipped before; the mirror set is
`default/pacman/mirrorlist-<channel>`) and offer **CachyOS kernels**
(`linux-cachyos`, `linux-cachyos-bore`, …) as `--kernel` picks. Rationale:
CachyOS is far more known than omarchy, widely wanted, and its kernel line is
optimized (BORE scheduler, LTO/PGO tunables) — a better-known drop-in for the
same "custom kernel" slot.

### What it touches

- `install.sh` kernel case (`omarchy|bore|muqss` → add `cachyos|…`), the
  single-kernel replace policy, and `hexciri-gpu`/`hexciri-kernel`'s recorded
  boot default.
- The kernel hedge still stands either way: stock kernel as a boot fallback,
  never a custom kernel as the *only* one.

### Open questions

- Chaotic-AUR as the delivery (its `chaotic-aur` mirror/repo) vs CachyOS's own
  repo — Chaotic is the "already known" one the user wants; it also keys into
  the AUR pipeline install.sh may want anyway (quickshell, dankshell, caelestia).
- Repo/mirror trust: omarchy today, +chaotic tomorrow — keep both mirrorlists or
  swap?
- Kernel naming (fastfetch/changelog): does a cachyos pick change what `hexciri`
  reports, or stay `linux`?

## 3. Carry-over / build order (proposed, not approved)

1. Research dankshell (config path, theming surface, compositor support).
2. shell spawn generalization — the install.sh autostart swap already keys off
   `$SHELL_PICK`; widen it from `noctalia|none` to the new set.
3. hexciri-session / session-set / install `known_shell` lists — one shared set.
4. Theme hook: add per-shell render fragment, noctalia paths untouched.
5. Kernel: Chaotic-AUR mirror + CachyOS `--kernel` names + boot-default record.
6. Validate: hyprland+caelestia (this machine's ground truth), niri+noctalia
   (default), both channels.