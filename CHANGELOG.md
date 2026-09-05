# Changelog

## 2026-09-05 — hexciri v0.1.2

- **hexciriv2 brand refresh**: new emblem (2000×1828) now ships on the SDDM theme, README, and the docs/website logo — and the old banner emblems are gone. A clean unbranded variant is the fastfetch logo.
- **Greeter, finally right**: the panel's DPI no longer scales the greeter layout (was ~4× on the 2880×1920 Framework), so the emblem renders at true size (716px) with a slim 150px entry; the logo PNG is right-sized (800px) so the greeter paints instantly instead of a long black wait; the fingerprint flow is a single friendly prompt — no retry timers, no phantom red "authentication failed".
- **fastfetch**: unbranded logo installed to `~/.config/fastfetch/hexciri-nb.png`, box 70×31 with 3px top padding; the installer drops the asset + config in place.
- **Keyring, quiesced**: fingerprint-first now lives in `system-auth` (supersedes the SDDM-local copy — one place covers sddm/sudo/su/login, no double prompt at the greeter), while SDDM's PAM keeps the gnome-keyring unlock lines so fingerprint logins never hit "Unlock Login Keyring"; gnome-keyring is pinned at 48.0 via `IgnorePkg` in both pacman channels (50.0 crashes — SIGABRT on concurrent Secret Service OpenSession/PKCS11), with a hexciri-menu shortcut to downgrade if it ever slips in.
- **hexciri-security**: the Fingerprint menu entry appears only when a reader is actually present.
- **hexciri-update-run**: the post-update reboot offer follows the pinned boot default (hexciri-kernel pin, else loader default) instead of the newest module dir, so a second staged kernel no longer spoofs a reboot.
- **hexciri-sync**: PAM restoration rebalanced around `system-auth` + the keyring pin; SDDM theme deploy expanded to the full greeter asset set.

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
- **Monitors survive install**: output blocks can't be detected inside the chroot, so `hexciri-niri-monitors` runs at first login (spawn-at-startup) and appends `output` blocks with the PPI-derived scale + VRR when none exist; install-time detection is only a fallback.
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
