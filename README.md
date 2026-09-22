<div align="center">

<img src="branding/hexciri-nb.png" alt="Hexciri" width="650">

**CachyOS dotfiles for Niri and Hyprland: a real menu and a theme engine.**

Install CachyOS with Niri or Hyprland, clone the dots, run one script —
hexciri detects the WM and tailors what it installs.

</div>

## What this is

Three names you'll see everywhere in this file:

- **CachyOS** — the operating system underneath (Arch Linux, tuned for speed).
  It owns the installer, kernel, drivers, and package updates.
- **Niri / Hyprland** — the window manager. Niri tiles windows into
  scrollable columns; Hyprland uses classic tiled/floating layouts. Every
  hexciri menu entry that talks to a WM works on both — hexciri detects which
  one is running and only installs WM-specific pieces for it.
- **Noctalia** — the bar, launcher, notifications, lock screen, and widgets.
  The visible stuff across the top of your screen.

hexciri is the layer on top: dots + scripts. Think of CachyOS as the house
and hexciri as the furniture — it never touches the foundation. What it owns:

- **The menu** — every option dispatches to a real controller in `bin/`.
  Nothing dangles. Root is `Mod+Alt+Space`; `Mod+K` searches all keybinds.
  (Like a TV remote where every button actually does something.)
- **The theming** — one pick (`hexciri-theme set`) recolors 30+ apps in one
  hook. 22 Omarchy defaults ship; extras are one line each in a list.
  (Like changing your shirt and your shoes, watch, and hat all match instantly.)
- **Your wallpapers survive theme changes** — drop images into
  `~/.config/hexciri/wallpapers` (or point at your own folders) and they show
  up in the picker on every theme, forever.
  (Your photos stay on the fridge no matter how often you repaint the kitchen.)
- **One-time app swap, then hands off** — install adds what hexciri needs and
  removes what it replaces. After that, sync never touches packages: your
  manual changes stick.
  (We help you move in once, then never rearrange your stuff again.)

## Niri vs Hyprland

hexciri runs on both. Nearly everything is shared — menu, theme engine, apps,
sync — and the few WM-specific pieces are installed only for the WM hexciri
detects. Detection order: explicit pin (`~/.config/hexciri/wm`) → live session
→ desktop markers → installed compositor → default niri. `bin/hexciri-session
wm` reports it; ssh/headless bring-up resolves from the installed binary.

| Piece | Niri | Hyprland |
|---|---|---|
| Config location | `~/.config/niri/config.kdl` + `cfg/*.kdl` | `~/.config/hypr/hyprland.lua` + `config/*.lua` |
| Hexciri keybinds | `config/niri/cfg/keybinds.kdl` (adapted once, then additive) | `config/hypr/config/hexciri-binds.lua` (required after `config.binds`, so hexciri wins conflicts) |
| Hexciri autostart | `config/niri/cfg/autostart.kdl` | `config/hypr/config/hexciri-autostart.lua` (required after `config.autostart`) |
| Theme window borders | baked in the Niri theme fragment | `decorations.lua` border/group colors patched by the theme hook, then `hyprctl reload` |
| Screen-recording webcam | always-on-top rule | window floated on the fly by the recorder |
| Touchpad / touchscreen toggles | yes | hidden (rows not shown on Hyprland) |

Everything else — menu, themes, apps, file-manager defaults, screenshots,
clipboard, sync, updates — is one shared code path for both WMs. `System >
Config` edits whichever WM is active; `Restart > Reload WM` runs Hyprland's
`reload` or Niri's `msg action reload-config` as appropriate.

## Install

In plain words: install CachyOS, grab this repo, run one script, answer two
questions (run the system update? reboot at the end?). Done.

1. **Install CachyOS** with Niri or Hyprland (normal installer — pick either
   as the desktop). hexciri detects which one at first sync.
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
deploy (keybinds for whichever WM is active, kitty, themes, full system
update it offers).

Safe to re-run any time — it re-applies instead of duplicating, so a second
run changes nothing that already matches. Staying current later is either
`Update > Hexciri` from the menu or `git pull` + re-run. Version is the git SHA
(`hexciri-version`).

## Highlights

- **A menu that does things** — 9 root entries, ~60 leaves. Press
  `Mod+Alt+Space` and you get buckets for packages, sharing, hardware,
  themes, network, security, maintenance, gaming, web apps. Every row runs a
  script in `bin/` — there are no dead buttons. Details in [Menu](#menu).
- **Themes that color everything** — run `hexciri-theme set <name>` once and
  your terminal, editor, browser, bar, lock screen and 25+ other apps all
  match. No per-app theming, ever. Details in [Themes](#themes).
- **Apps in, cruft out** — the installer swaps in hexciri's apps (kitty, Zed,
  Brave Origin…) and removes what they replace, exactly once. After that your
  installs and removals are yours. Full list in [Apps](#apps).
- **Defaults you can switch** — browser, editor, terminal, shell, files,
  images, agent: all switchable from `System > Default Apps`. Only apps you
  actually have installed are offered; your current pick is marked ✓.
- **Keybinds, one source of truth** — repo keybinds land in your Niri config
  or as a Hyprland Lua overlay loaded right after the stock binds (hexciri
  wins any conflict). Same combo set on both WMs, so docs and behavior can't
  drift apart. `Mod+K` searches every bind live.
- **Self-healing updates** — every `hexciri-update` press first pulls the
  newest framework code, then re-applies links, menu entries, firewall and
  sshd settings, and only then updates your system packages. So fixes we ship
  (like missing helper apps) land on your box by themselves.

## Menu

Root menu (`hexciri-menu`, `Mod+Alt+Space`). Esc always goes back a level.

In plain words: `Mod+Alt+Space` opens the big list of everything. Nine
buckets — Learn (manuals for what's installed), Packages (get/remove
software), Share & Capture (send files, screenshots), Reminders, Hardware
(laptop toggles), Themes (the look), System (settings), Restart (reload
things), Update (updates). Pick a row and it does the thing.

> The website shows the short version. This is the complete map — it mirrors
> the actual scripts in `bin/`, so if a row is here it works.

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
│   ├── Config >               (only the ACTIVE WM's entry shows)
│   │   ├── Niri >             (per-fragment editors: config.kdl + cfg/*.kdl)   — on niri
│   │   ├── Hyprland >         (live editor for hyprland.lua + config/*.lua)    — on hyprland
│   │   ├── Noctalia config
│   │   ├── Fastfetch config
│   │   ├── Hexciri lockscreen
│   │   ├── State files >      (Keybinds list · Search provider)
│   │   └── Hooks
│   ├── Default Apps >       Browser · Editor · Terminal · Shell · Files · Images · Agent
│   ├── Maintenance >        Sync system clock · System Cleaner (cache + orphans)
│   │                        User password · Reset boot config
│   ├── Windows product key  (reads MSDM/OA3/SMBIOS firmware key)
│   ├── Reset defaults       (reinstall hexciri packages + reset owned configs)
│   ├── Network >            DNS > (DHCP · Cloudflare · Google · Custom)
│   │                        Wi-Fi QR Code (scan-to-join, terminal render)
│   └── Security >           Fingerprint (gated on reader) · Fido2 · SSHD toggle
│                            Passwordless Sudo
├── Restart                  Reload WM (Niri / Hyprland) · Restart Noctalia · Refresh theme
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

One command recolors the whole desktop. In plain words: pick a color theme
once, and your terminal, browser, bar, lock screen and 25+ other apps all
match — you never theme apps one by one.

```bash
hexciri-theme set <name>     # e.g. hexciri-theme set sakurazuki
hexciri-theme list           # preview picker (▶ marks current)
hexciri-theme current
hexciri-theme install <github-url>   # one-off → tracked in your extras list
hexciri-theme remove <name>          # user themes only
hexciri-aether-apply [--name <name>] # import Aether's live palette+wallpaper, then set it (bar included)
```

Web `aether://` Apply buttons are claimed automatically (install + every
sync): one click applies in Aether and follows through to the hexciri theme,
bar included — no manual import step.

How it works, in plain words: every theme is just a list of colors
(`colors.toml`). Picking a theme copies that list into place and then runs a
hook — a folder of small scripts, one per app — and each script repaints its
app from the same list. That's how 30+ apps match with one command. Your own
scripts dropped in `~/.config/hexciri/hooks/theme-set.d/` run too, and if you
edit a shipped script it is kept as yours forever (never overwritten).

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
**Theme** (use the colors the theme author picked) or **Wallpaper** (make
colors from your current background, Material-You style). Theme swaps never
flip it back — the two choices don't interfere with each other.

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

In plain words: your pictures and the theme's pictures are kept in separate
piles. Switching themes only replaces the theme's pile — yours is linked in
beside them and survives every change.

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

In plain words: on day one we install the apps hexciri expects and remove
the ones they replace. From day two on, your installs and removals are
yours — updates never undo them (except 7 layer-critical packages that
would break keys, logins, or themes if missing).

One-time swap at install, hands off after that. The framework sync
(`hexciri-sync` / `hexciri-update self`) never touches packages except the
tiny layer-critical subset `polkit-gnome gnome-keyring adw-gtk-theme nautilus brightnessctl playerctl fwupd`
it self-heals — your later manual changes stick.
Best-effort throughout: offline boxes finish, missing bits print their manual
fallback.

Install adds what hexciri needs and removes what it replaces, once, at
bring-up (`install.sh`, re-runnable). After that there is no list to curate
and no reconcile: add or remove packages yourself with pacman/yay and they
stay as you left them.

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
| `mpv` | default video player (replaces the vlc plugin stack) |
| `libqalculate` | fuzzel calculator provider |
| `polkit-gnome` | auth agent — without it pkexec apps (gparted, btrfs-assistant) silently never open |
| `zathura zathura-pdf-mupdf zathura-ps zathura-djvu zathura-cb` | default document reader — PDF/ePub/XPS via the MuPDF backend plus PostScript, DjVu and comics (pinned over browser-stolen doc MIME) — swappable, delete its line and add yours |
| `gnome-keyring` | Secret Service provider (calendar tokens, app secrets) + seahorse UI |
| `seahorse` | keyring manager UI |
| `adw-gtk-theme` | base GTK3 theme (`adw-gtk3-dark`) the theme hooks recolor — GTK apps look unthemed without it |
| `brightnessctl` | backlight control — niri `XF86MonBrightness*` binds + Noctalia brightness widget/OSD are dead without it |
| `playerctl` | MPRIS media control — niri `XF86AudioPlay/Next/Prev` binds are dead without it |
| `fwupd` | firmware updates — Update > Firmware runs `fwupdmgr update`, fails with "command not found" without it |
| `jq` | JSON parsing for the WM bridges — focused-output/window lookups, reminder timers, and screen-record geometry all go through it |
| `cliphist` | clipboard history — `Mod+Ctrl+V` picker (`hexciri-clipboard`) and the autostart history watchers on both WMs |

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

Plain version first: your day-to-day settings (which browser, which keys do
what) live in the menu under System — you should never need to hunt through
config files by hand. The notes below are what's happening behind those rows.

- **Default Apps** (`System > Default Apps`, `hexciri-defaults`) — Browser
  (brave-origin…), Editor (zed…), Terminal (kitty…), Shell (fish…), Files
  (nautilus…), Images (imv…), PDF (zathura…), Agent (opencode…). Only installed candidates are
  offered; current is marked ✓. Shell switches kitty's shell without touching
  your login shell.
- **Keybinds** — one combo set, two homes. On Niri the repo file
  `config/niri/cfg/keybinds.kdl` is the master: first sync adapts a stock
  CachyOS file once (keeping your combos plus stock-only keepers), then
  updates only *add* brand-new binds. On Hyprland the same binds ship as
  `config/hypr/config/hexciri-binds.lua` (+ `hexciri-autostart.lua`),
  deployed by sync and required into `hyprland.lua` right after the stock
  `config.binds` / `config.autostart` — so when a combo collides, hexciri's
  action wins. Either way your edits are yours: modified overlays/configs
  are kept as custom and never overwritten.
  `hexciri-keybinds` lists them; on Hyprland it merges the live stock file
  with the overlay and de-duplicates by combo (first file wins), skipping
  loop-generated binds. `Mod+K` searches them live.
  Binds without a friendly name show just their command
  (Niri `spawn "vesktop" "vesktop"` → `vesktop`; Hyprland
  `exec_cmd("noctalia msg panel-toggle launcher")` → the command), and you
  can set your own labels in `System > Config > State files > Keybinds list`,
  one `Combo = Label` per line.
  Core: `Mod+Space` apps (Noctalia) · `Mod+Return` terminal · `Mod+Alt+Space` root menu · `Mod+K` this list · `Mod+Q` close ·
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
- **Config editing** (`System > Config`) — your live WM config: Niri
  fragments (autostart, cursors, env, input, looknfeel, monitors,
  window-rules, keybinds) or Hyprland (`hyprland.lua` + every `config/*.lua`
  fragment), plus Noctalia, fastfetch, lockscreen panel-off timing, State
  files (your keybind labels + search provider), and your hooks dir.
- **Self-heal on every update** — alpm hook + `hexciri-sync` re-apply links,
  menu curation (`.desktop` hides), firewall, sshd hardening (key-only, no
  root password), MIME heals (browsers keep stealing image/PDF defaults), and
  the Noctalia updater plugin migration. Silent when there's nothing to do.

## When something looks off

Three steps, in order — most problems end at step 1:

1. Press `Update > Hexciri` from the menu. Every press re-applies links,
   keybinds, firewall and sshd settings, and installs any missing
   layer-critical packages. It tells you what it changed.
2. Still off? Re-run `install.sh` — it only fills in what's missing, so it's
   safe to run on a working box too.
3. Forgot a key? `Mod+K` searches every keybind. Need a doc? `Learn` in the
   root menu only shows guides for apps you actually have installed.

## Sources

[Omarchy](https://github.com/omacom/omarchy) × [Niri](https://github.com/YaLTeR/niri) × [Hyprland](https://hyprland.org) × [Noctalia](https://github.com/) × [Quickshell](https://github.com/outfoxxed/quickshell) × [theme-hook-plugin-manager](https://github.com/OldJobobo/theme-hook-plugin-manager) × [base16-Discord](https://github.com/imbypass/base16-discord) × [ClearVision-v7](https://github.com/ClearVision/ClearVision-v7) × [system24](https://github.com/refact0r/system24) × [omarchy-nautilus-theme](https://github.com/ilJapo/omarchy-nautilus-theme) × [omarchy-sakurazuki-theme](https://github.com/ahmed-z0/omarchy-sakurazuki-theme) × [Adwaita-for-Steam](https://github.com/tkashkin/Adwaita-for-Steam)
