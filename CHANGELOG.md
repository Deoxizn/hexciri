# Changelog

## 2026-09-05 — hexciri post-0.1.2 hardening

- **Web-app keybinds actually work**: Messenger/Gemini/Photopea binds (Mod+Ctrl+M, XF86Launch5/6) are back as a `hexciri-launch-or-focus-webapp` port of Omarchy's script — they reuse the default Chromium browser and focus an already-open web app instead of stacking a second window. Also fixed `hexciri-launch-webapp`, whose desktop-file Exec lookup died (`set -e`) whenever the browser's `.desktop` file only existed in `/usr/share/applications` — the exact case on fresh installs.
- **opencode/hexciri TUI helpers tile now**: the `TUI.float` window rule dropped `open-floating` + fixed 1000x720 (kept the `background-effect` blur) so the kitty-hosted TUIs behave like normal terminals under niri's scrollable tiling.
- **yay ships by default**: fresh installs build `yay-bin` (prebuilt AUR binary, as the managed user) so the AUR menu entry (`hexciri-packages` → Install → AUR), the arch-updater AUR pass, and `hexciri-gaming`'s on-demand AUR pulls all just work out of the box instead of printing "install yay first".

- **Plain-root, LUKS/plymouth gone**: dropped the LUKS + plymouth splash entirely — plain-root boots fastest, the SDDM password/fingerprint greeter is the login gate. plymouth theme, initramfs encrypt plumbing, and `hexciri-splash` removed with them.
- **mkinitcpio is deterministic now**: install seeds a pristine `mkinitcpio.conf` before pacstrap (so kernel hook builds can't abort it), enables only hooks whose initcpio hook file actually exists, and guarantees an initramfs rebuild — self-healing HOOKS management instead of hand-editing.
- **Bootstrap revs 20–29**: `$_u` escaped in stage2 (set -u crash); persistent pacman cache + gpg keyring seed so wipe retries skip re-download/keygen; `CacheDir` emitted inside `[options]` (rev 26) then the package cache staged in `/tmp` not `/root` (archiso pacman hits EPERM on 0700 `/root`, rev 28); pacman conf regenerated per run with the cache dropped wholesale (rev 29); loud failure on pacstrap errors.
- **Site**: full hexciriv2 emblem in the hero, unbranded variant, logo served as `brand.png` (busts the stale-logo edge cache), spacing/cache polish.
- **Menus & file editing**: `hexciri-config` gains a Fastfetch entry; `hexciri-edit-file` opens directories via xdg-open (fixes empty Config>Hooks/Scripts/Palettes); `hexciri-themes` adds a Backgrounds entry opening the noctalia wallpaper dir.
- **Install/update split**: first-install-only seeds (theme, browser/file-manager defaults, GTK dark theming) gated by `theme.name` + a `ui-defaults-applied` marker — updates only deploy artifacts and never reset user state. `hexciri-update` repo sync runs the full self-update so git commits actually land; `hexciri-update-run` runs the framework self-update before pacman. `hexciri-theme-ensure` stopped forcing `source=custom` (palette source is a user choice, preserved at login) and noctalia-sync only patches to the custom palette when unset/already custom.

## 2026-09-05 — hexciri v0.1.2

- **hexciriv2 brand refresh**: new emblem (2000×1828) now ships on the SDDM theme, README, and the docs/website logo — and the old banner emblems are gone. A clean unbranded variant is the fastfetch logo.
- **Greeter, finally right**: the panel's DPI no longer scales the greeter layout (was ~4× on the 2880×1920 Framework), so the emblem renders at true size (716px) with a slim 150px entry; the logo PNG is right-sized (800px) so the greeter paints instantly instead of a long black wait; the fingerprint flow is a single friendly prompt — no retry timers, no phantom red "authentication failed".
- **fastfetch**: unbranded logo installed to `~/.config/fastfetch/hexciri-nb.png`, box 70×31 with 3px top padding; the installer drops the asset + config in place.
- **Keyring, quiesced**: fingerprint-first now lives in `system-auth` (supersedes the SDDM-local copy — one place covers sddm/sudo/su/login, no double prompt at the greeter), while SDDM's PAM keeps the gnome-keyring unlock lines so fingerprint logins never hit "Unlock Login Keyring"; gnome-keyring is pinned at 48.0 via `IgnorePkg` in both pacman channels (50.0 crashes — SIGABRT on concurrent Secret Service OpenSession/PKCS11), with a hexciri-menu shortcut to downgrade if it ever slips in.
- **hexciri-security**: the Fingerprint menu entry appears only when a reader is actually present.
- **hexciri-update-run**: the post-update reboot offer follows the pinned boot default (hexciri-kernel pin, else loader default) instead of the newest module dir, so a second staged kernel no longer spoofs a reboot.
- **hexciri-sync**: PAM restoration rebalanced around `system-auth` + the keyring pin; SDDM theme deploy expanded to the full greeter asset set.
- **opencode / TUI floats follow the terminal theme**: the `TUI.float` niri window rule (used by `hexciri-agent` → `xdg-terminal-exec --app-id=TUI.float -e opencode`, plus kernel/defaults menus) now carries `background-effect { blur true }` — the same treatment the `app-id="kitty"` rule gets. OpenCode previously rendered in a TUI.float kitty with no blur, so its reduced `background_opacity` read as flat color instead of soft translucency; theme colors (via the kitty include + SIGUSR1 poke) were already flowing.
- **Wallpaper directory actually holds on fresh installs**: hexciri could only point Noctalia's wallpaper picker at the active theme via `config.toml` `[wallpaper] directory`, but Noctalia's GUI overrides (`settings.toml`) win over user config — so a fresh box picked its builtin folder. install.sh now seeds `directory = ~/.local/state/hexciri/current/theme/backgrounds` into `settings.toml` (first-seed-only, never re-asserted; the path is stable across theme switches since `current/theme` is re-copied in place).

## 2026-09-05 — hexciri v0.1.1

- **Transparent terminals**: kitty `background_opacity 0.35` plus a niri `background-effect { blur true }` window rule (niri 26.04 window effects) so reduced opacity reads as soft translucency. Focus ring and border are now off — niri paints both as a solid rectangle *behind* windows (per its FAQ), which covers semitransparent windows and hides the blur; that was the real reason focused terminals rendered opaque.
- **Noctalia bar rework**: launcher, wallpaper, workspaces, spacer, media, active_window, 12-hour clock, notifications, clipboard, tray, network, bluetooth, volume, brightness, battery, arch-updater, control-center; 12-hour time throughout (`{:%I:%M %p}`); wallpaper picker + rotation point at the active theme's backgrounds; rotation off by default.
- **sakurazuki default theme**: kitty background follows the theme's `Background`; the theme-set hook now also drives Qt theming via qt6ct (Fusion + a QPalette color scheme generated from theme tokens, roles live-verified).
- **Never-clobber config deploy**: install.sh `deploy` is sha-tracked — untouched configs update in place, user-modified ones are kept with the repo default shipped alongside as `<file>.hexciri` (backup-first either way).
- **Monitor auto-detect**: install.sh reads connected outputs (niri msg outputs preferred mode, sysfs/EDID fallback), derives scale from physical size (PPI in 0.25 steps, 1–2) and appends `output` blocks with VRR when none are configured.
- **Bluetooth**: bluez + bluez-utils staged and `bluetooth.service` enabled — bar widget and pairing work on a fresh install.
- **Gaming growth**: Minecraft, Battle.net (umu-launcher + GE-Proton installer with partial-prefix wipe, `hexciri-launch-battlenet` + desktop entry), GeForce NOW, Xbox Cloud; `hexciri-packages` gains a Gaming entry.
- **Share pickers**: Qt-first kdialog file/folder dialogs (in-process under Niri, no desktop-portal dependency), zenity fallback.
- **fastfetch**: logo 66x36, `user @ host` title, new `hexciri-fastfetch` command + `ff` alias; documented that fastfetch 2.68 has no true logo centering.
- **Install URL**: bootstrap published at `https://hexciri.dirty.pizza/install` (rev 7; the old `/hexciri` path still works). One-liner is `curl -L -o hexciri https://hexciri.dirty.pizza/install && sh hexciri`.
- **Bash login shell**: login shell stays `bash` (scripting-safe everywhere); `fish` is interactive-only via kitty `shell fish`. `hexciri-defaults` → Shell writes the kitty config rather than `chsh`; no more fish-only login shell to fight quoting in.
- **Greeter password-only**: when the installer stamps `Username=` (always the case), the SDDM greeter shows only the password field — no username box to trip over — with the row layout kept for unknown-user fallback. PasswordOTS/asterisks draw correctly.
- **Choose your app menus**: install.sh hides utility-only launcher entries (`avahi-discover`, `bssh`, `bvnc`, `lstopo`, `qv4l2`, `qvidcap`, `qt6ct`) by appending `NoDisplay=true`, so the game list and first-party apps are what the menu surfaces.
- **Monitors ship preconfigured**: the niri config carries the laptop panel default (`output "eDP-1"` scale 2, mode/VRR commented) instead of runtime autodetect — no more chroot blind spot, no login-time appends, and no transient "config error" notifications from niri's watcher catching a mid-append config. Desktops rename the one block after `niri msg outputs`.
- **Therapy from the first boot**: theme seed in the chroot is non-fatal, and `hexciri-theme-ensure` re-applies the active theme on each login if the tree or noctalia palette is missing — no more themeless first boot.
- **Fingerprint login**: `fprintd` is in the base set and sddm's PAM chain gains `pam_fprintd.so` (sufficient), so enroled Goodix/Synaptics readers unlock at the greeter.
- **Fuzzel colors schema fix**: fuzzel 1.15 `[colors]` wants RGBA 8-hex and the modern `text`/`selection-text`/`match` keys — the theme template generated the pre-1.15 names, so fuzzel silently fell back to defaults; regenerated with valid values on both boxes.

## 2026-09-04 — hexciri v0.1.0

- hexciri v0.1.0: own Arch-based Niri + Noctalia distro.
-  curl bootstrap from the Arch ISO (9 typed prompts, full-disk or free-space dual-boot, ext4/btrfs, systemd-boot, SDDM autologin) and `./install.sh` for existing vanilla Arch
- Channels: stable (pinned Arch snapshot) + bleeding (edge Arch), `--channel` only pre-fills the prompted default; kernel menu covers stock/lts/omarchy/bore/muqss with systemd-boot defaults
- Theme engine on colors.toml: `hexciri-theme-set` regenerates kitty/fuzzel/Strata/fish/Zed/Noctalia/Niri from one palette, hookable via `hooks/theme-set.d/`; maiden theme sakurazuki, various-arch seeded
- Suite of 16 vanilla commands (menu, terminal, defaults, update, gpu, power, lock, keybinds, agent, clipboard, screenrecord, gaming, webapps) with every KDL bind resolving; defaults are kitty/fish/brave-origin/strata/zed/opencode
- GPU autodetect: nvidia-open 6xx on Turing+, 580xx with hard LTS pin on Maxwell/Pascal/Volta, mesa/vulkan otherwise, Niri modeset plumbing included
- Branding surfaces: SDDM emblem greeter, plymouth two-step splash, fastfetch seed, starship prompt, emblem + lockup art
- Privilege boundary: installer split into a root system phase and a sudoless user phase, so nothing depends on sudo prompting without a terminal; AUR builds as the user with root installing the finished package ([`be85d91`](https://github.com/Deoxizn/hexciri/commit/be85d91), [`af3b6b5`](https://github.com/Deoxizn/hexciri/commit/af3b6b5))
- Kernel policy: exactly one kernel on fresh installs — custom picks replace the staged base (entries generated per installed kernel); custom kernels refused unless in configured repos, hard LTS pin on GTX 1xxx or older ([`d7b2eb9`](https://github.com/Deoxizn/hexciri/commit/d7b2eb9), [`41200f6`](https://github.com/Deoxizn/hexciri/commit/41200f6))
- Prompts: `/dev/tty` reads for piped runs, password confirm, GeoIP timezone chain, disk questions last with a pre-wipe summary gate, archfi-style file-first flow (`sh hexciri`)
- GPU setup baked into the install (auto-detect, `--kernel` preselect); mesa stack in the base set
