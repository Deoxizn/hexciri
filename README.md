<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

**CachyOS + Niri dotfiles: a real menu and a theme engine.**

Install CachyOS with Niri, clone the dots, run one script.

</div>

## What this is

hexciri is dots + scripts for a CachyOS + Niri box. It never
touches the installer, kernel, GPU stack, or package manager — those stay
CachyOS's. What it owns:

- **The menu** — every option dispatches to a real controller in `bin/`.
  Nothing dangles. Root is `Mod+Alt+Space`; `Mod+K` searches all keybinds.
- **The theming** — one pick (`hexciri-theme set`) recolors 30+ apps in one
  hook. 22 Omarchy defaults ship; extras are one line each in a list.
- **Your wallpapers survive theme changes** — drop images into
  `~/.config/hexciri/wallpapers` (or point at your own folders) and they show
  up in the picker on every theme, forever.
- **One-time app swap, then hands off** — install adds what hexciri needs and
  removes what it replaces. After that, sync never touches packages: your
  manual changes stick.

## Install

1. **Install CachyOS** with Niri.
2. Bring the dots — curl or clone, same script:

```bash
curl -LO https://hexciri.dirty.pizza/install.sh
sh install.sh
```

or:

```bash
git clone https://github.com/Deoxizn/hexciri.git ~/.local/opt/hexciri
~/.local/opt/hexciri/install.sh [--yes]
```

One run does the whole bring-up: links every controller into `~/.local/bin`,
root sync pass (firewall/sshd/menu curation/alpm hook), one-time app swap,
Nautilus default, Brave Origin, image/PDF defaults, theme seeding, and the update
deploy (keybinds, kitty, themes, full system update it offers). Re-runs are
safe. Updating is a pull plus a re-run. Version is the git SHA
(`hexciri-version`).

## Highlights

- **A menu that does things** — 9 root entries, ~60 leaves, all working
  scripts: packages, sharing, hardware, themes, network, security,
  maintenance, gaming, web apps. See [Menu](#menu) below.
- **Themes that color everything** — one hook recolors terminals, shell,
  editors, browsers, Discord, GTK/Qt, Spotify, file manager, bar, lock, and
  more. See [Themes](#themes).
- **Apps in, cruft out** — curated [added and removed apps](#apps), installed
  once at bring-up and never forced on you again.
- **Defaults you can switch** — browser, editor, terminal, shell, files,
  images, agent: all switchable from `System > Default Apps`.
- **Keybinds, one source of truth** — rendered into Niri's config so they
  never drift. `hexciri-keybinds` lists them; `Mod+K` searches them live.
- **Self-healing updates** — every `hexciri-update` press pulls the framework,
  re-execs into the new code, re-applies links/menu/firewall/sshd, and only
  then updates the system.

## Menu

Root menu (`hexciri-menu`, `Mod+Alt+Space`). Esc always goes back a level.

```
► Hexciri
├── Learn                    docs for what's actually installed (gated on binaries present)
│   └── Hexciri · Noctalia · CachyOS wiki · CachyOS Niri setup · chwd · Btrfs snapshots
│       Niri wiki · kitty/Alacritty/foot · fish · Zed · OpenCode · Starship
├── Packages
│   ├── Install >            Package (pacman picker) · AUR (yay/paru picker)
│   │                        Web App (URL → desktop launcher) · Gaming >
│   │                          └── Steam · Heroic · Lutris · RetroArch · Minecraft
│   │                              Battle.net · GeForce NOW · Xbox Cloud · Xbox controllers
│   └── Remove >             Package · Web App (yours) · Theme (yours)
├── Share & Capture          LocalSend + screenshots, recording, OCR, QR, transcode
│   ├── Clipboard · File · Folder · Receive (localsend-cli / GUI fallback)
│   └── Screenshot region · Screenshot screen · Screen recording (gpu-screen-recorder)
│       OCR text from screen (tesseract → clipboard) · Decode QR from screen
│       Transcode media (ffmpeg presets)
├── Reminders                Set a reminder · Quick reminder · Clear all
├── Hardware                 (rows appear only when the hardware exists)
│   └── Touchpad toggle · Touchscreen toggle · Hybrid GPU switch (supergfxd)
│       Network download · Network upload (speed test) · Disk speed test
├── Themes                   Theme list (preview picker) · Palette source (Theme/Wallpaper)
│                            Backgrounds (your store) · Fonts
│                            Extra themes list · Wallpaper dirs list
├── System
│   ├── Config >             Niri > (per-fragment editors) · Noctalia config
│   │                        Search provider · Fastfetch config
│   │                        Hexciri lockscreen · Hooks
│   ├── Default Apps >       Browser · Editor · Terminal · Shell · Files · Images · Agent
│   ├── Maintenance >        Sync system clock · System Cleaner (cache + orphans)
│   │                        User password · Reset boot config
│   ├── Windows product key  (reads MSDM/OA3/SMBIOS firmware key)
│   ├── Reset defaults       (reinstall hexciri packages + reset owned configs)
│   ├── Network >            DNS > (DHCP · Cloudflare · Google · Custom)
│   │                        Wi-Fi QR Code (scan-to-join, terminal render)
│   └── Security >           Fingerprint (gated on reader) · Fido2 · SSHD toggle
│                            Passwordless Sudo
├── Restart                  Reload Niri · Restart Noctalia · Refresh theme
└── Update
    ├── Hexciri              system update: repo + AUR, keyring check, sync re-apply, reboot offer
    ├── Themes               pull Omarchy defaults + sync extras list
    ├── Wallpaper            re-merge your wallpapers into the active theme
    ├── Hardware >           restart Audio · Wi-Fi · Bluetooth · Trackpad stack
    ├── Firmware             (fwupdmgr update)
    └── Repo                 framework-only sync (pull + keybinds/kitty/fastfetch/noctalia/hooks)
```

Launchers alongside the menu: `Mod+Space` Noctalia app launcher,
`Mod+Alt+Space` root menu (fuzzel), `Mod+Shift+S` web search / `Mod+Shift+C`
calculator (fuzzel), `Mod+Return`
terminal, ``Mod+` `` AI agent (`opencode` by default), `Mod+Escape` power
menu, `Mod+Ctrl+V` clipboard history.

## Themes

One command recolors the whole desktop:

```bash
hexciri-theme set <name>     # e.g. hexciri-theme set sakurazuki
hexciri-theme list           # preview picker (▶ marks current)
hexciri-theme current
hexciri-theme install <github-url>   # one-off → tracked in your extras list
hexciri-theme remove <name>          # user themes only
```

How it works: the theme dir's `colors.toml` is the single source of truth.
`hexciri-theme-set` copies it live to `~/.local/state/hexciri/current/theme`,
expands the generated templates (`default/themed/`: kitty, fuzzel,
starship), then fires `hexciri-hook theme-set`, which
runs every drop-in in `hooks/theme-set.d/`. That covers 30+ targets: fish,
fzf, tmux, zellij, starship, kitty, foot, editors (zed, vscode, cursor,
windsurf, typora, obsidian-terminal), browsers (firefox, zen, qutebrowser,
hermes), Discord (+ ClearVision/system24 variants), GTK, Qt6ct, Spotify /
Spicetify, file managers (superfile), launchers (vicinae), bar and
notifications (swaync, Noctalia palette), cava, cliamp, Steam, Heroic,
branding (fastfetch logo, SDDM), cursor, nautilus. Your own
`~/.config/hexciri/hooks/theme-set.d/` drop-ins run too and are never
overwritten (manifest-tracked: edited files are kept as custom).

Palette source is your independent choice in `Themes > Palette source`:
**Theme** (the theme's custom palette) or **Wallpaper** (Material You from
the background). Theme swaps never flip it back.

### Shipped themes

Two hexciri originals live in `themes/`: **sakurazuki** (near-black plum,
muted rose, moonlit blue) and **various-arch** (deep navy sampled from its
wallpaper, sky-blue Arch accent). Everything else comes from the lists below
and lands in `~/.config/hexciri/themes/`.

**Omarchy defaults** — 22 themes, seeded on install from a sparse clone of
`omacom/omarchy` (`quattro` branch, `themes/` subtree) and kept current by
`Update > Themes` / the Repo sync. Source of truth:
`config/theme-sources/omarchy.list` (prune your copy to hide entries without
losing installability):

> catppuccin · catppuccin-latte · ethereal · everforest · flexoki-light ·
> gruvbox · hackerman · kanagawa · last-horizon · lumon · lupine ·
> matte-black · miasma · nord · osaka-jade · retro-82 · ristretto ·
> rose-pine · solitude · tokyo-night · vantablack · white

**Extra themes** — handpicked, one line per theme in
`config/theme-sources/extra.list` (any repo naming; bare `owner/repo` clones
literally, short names fall back to the `omarchy-<name>-theme` convention,
full URLs always work). Sync clones what's listed, pulls what's installed,
and removes what you deleted — the list is the source of truth:

> - `HANCORE-linux/omarchy-aamis-theme`
> - `HANCORE-linux/omarchy-sapphire-theme`
> - `OldJobobo/omarchy-everpuccin-theme`

Curate without touching the repo: keep overrides at
`~/.config/hexciri/theme-sources/{extra,omarchy}.list` — edited from
`Themes > Extra themes list` (seeded from the shipped copies on first open).
`hexciri-theme-install <url>` appends to your override automatically.

### Wallpapers

Your wallpapers are merged into the active theme as read-only `zz-user-*`
symlinks, so Noctalia's picker shows them beside the theme's shipped set.
Theme swaps only replace theme-owned files — your links survive every change.

- **Store:** `~/.config/hexciri/wallpapers` — drop images (or folders) here.
  Open it from `Themes > Backgrounds`.
- **Extra dirs:** `config/wallpaper-sources/extra.list` (override at
  `~/.config/hexciri/wallpaper-sources/extra.list`, edited from
  `Themes > Wallpaper dirs list`) — one directory per line (`~/…` expands),
  any mount incl. NFS. Files are never copied or deleted, only linked; dead
  mounts link now and resolve when they appear.
- **Refresh:** `Update > Wallpaper` (`hexciri-wallpaper-refresh`) re-merges
  after you add/remove sources. Every framework sync re-merges the store
  automatically.

## Apps

One-time swap at install (`install.sh` only — sync never touches packages
except the tiny layer-critical subset `polkit-gnome mupdf gnome-keyring adw-gtk-theme nautilus`,
so deliberate removals stick). Best-effort throughout: offline boxes finish,
missing bits print their manual fallback.

**Added** (`pacman -S --needed`):

| Package | Why |
|---|---|
| `kitty` | default terminal (transparent + blur, theme-generated config) |
| `zed` | default editor |
| `opencode` | default AI agent (``Mod+` ``) |
| `localsend` | Share menu sender (ships `localsend-cli` ≥ 1.18) |
| `fuzzel` | menu backbone (dmenu for root menu + all pickers) — the menu is dead without it |
| `gtksourceview5` | text-viewer libs (gedit-style viewers) |
| `gpu-screen-recorder` | Screen recording blade |
| `tesseract` | OCR-text-from-screen blade |
| `imv` | default image viewer (pinned over browser-stolen `image/*`) |
| `libqalculate` | fuzzel calculator provider |
| `polkit-gnome` | auth agent — without it pkexec apps (gparted, btrfs-assistant) silently never open |
| `mupdf` | default PDF reader (pinned over browser-stolen `application/pdf`) |
| `gnome-keyring` | Secret Service provider (calendar tokens, app secrets) + seahorse UI |
| `seahorse` | keyring manager UI |
| `adw-gtk-theme` | base GTK3 theme (`adw-gtk3-dark`) the theme hooks recolor — GTK apps look unthemed without it |

Plus: **yay** bootstrapped via makepkg (needs `base-devel`+`git`) when no
AUR helper exists; **Brave Origin** (`brave-origin-bin` via yay/paru — the
hexciri browser, not Brave) with the `brave-bin` stand-in dropped once
Origin is present; **Nautilus** stays the default file manager (its
`org.gnome.Nautilus.desktop` owns `inode/directory`, themed via GTK 3/4 css).

**Removed** (only if installed; kept when something still needs them):

| Package | Why it goes |
|---|---|
| `cachyos-niri-noctalia` | the stock meta — removed first so what it pins comes out clean |
| `xdg-desktop-portal-gnome` | pinned by the meta; hexciri doesn't use it |
| `alacritty` | replaced by kitty (+ `~/.config/alacritty` purged) |
| `firefox` | replaced by Brave Origin (+ `~/.mozilla` purged) |
| `meld` | not part of the workflow (+ config purged) |
| `cachyos-micro-settings`, `micro` | replaced by zed (+ config purged) |
| `vim` | force-removed (`-Rdd` breaks only `cachyos-zsh-config`'s declared dep; reinstalling vim undoes it; `~/.vim`/`~/.viminfo` purged) |

## More of what's inside

- **Default Apps** (`System > Default Apps`, `hexciri-defaults`) — Browser
  (brave-origin…), Editor (zed…), Terminal (kitty…), Shell (fish…), Files
  (nautilus…), Images (imv…), Agent (opencode…). Only installed candidates are
  offered; current is marked ✓. Shell switches kitty's shell without touching
  your login shell.
- **Keybinds** — `config/niri/cfg/keybinds.kdl` is the source; sync seeds it
  fresh, adapts a stock CachyOS file once (yours + kept stock-only combos),
  then only adds new repo binds additively — conflicts and your deletions are
  never overwritten. Core: `Mod+Space` apps (Noctalia) · `Mod+Return`
  terminal · `Mod+Alt+Space` root menu · `Mod+K` this list · `Mod+Q` close ·
  `Mod+F` maximize · `Mod+1…9,0` workspaces · `Mod+←/→` focus ·
  `Mod+Print`/`Ctrl+Print` screenshot · `Alt+Print` record · `Mod+Escape`
  power.
- **Gaming + web apps** — one-press Steam / Heroic / Lutris / RetroArch /
  Minecraft / Battle.net (umu + GE-Proton, no Steam needed) / GeForce NOW /
  Xbox Cloud / controller (xpadneo) setup; any URL becomes a desktop app with
  icon (`Install > Web App`), removable from `Remove > Web App`.
- **Network / Security / Maintenance** — DNS provider switch (DHCP /
  Cloudflare / Google / Custom, NM + resolved), Wi-Fi QR share, link status;
  fingerprint (gated on a detected reader), FIDO2, SSHD toggle, passwordless
  sudo; clock sync, cache/orphan cleaner, boot-config reset, firmware update.
- **Config editing** (`System > Config`) — Niri fragments (autostart,
  cursors, env, input, looknfeel, monitors, window-rules, keybinds), Noctalia,
  search provider, fastfetch, lockscreen panel-off timing, and your hooks dir.
- **Self-heal on every update** — alpm hook + `hexciri-sync` re-apply links,
  menu curation (`.desktop` hides), firewall, sshd hardening (key-only, no
  root password), MIME heals (browsers keep stealing image/PDF defaults), and
  the Noctalia updater plugin migration. Silent when there's nothing to do.

## Sources

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)
