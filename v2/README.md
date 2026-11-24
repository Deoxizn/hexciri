```
 ▄  █ ▄███▄      ▄  ▄█▄    ▄█ █▄▄▄▄ ▄█ 
█   █ █▀   ▀ ▀▄   █ █▀ ▀▄  ██ █  ▄▀ ██ 
██▀▀█ ██▄▄     █ ▀  █   ▀  ██ █▀▀▌  ██ 
█   █ █▄   ▄▀ ▄ █   █▄  ▄▀ ▐█ █  █  ▐█ 
   █  ▀███▀  █   ▀▄ ▀███▀   ▐   █    ▐ 
  ▀           ▀                ▀
```

Branch `nyx`, `Deoxizn/hexciri`. No merge to main. Root `README.md` is the overview, this file is the `v2/` notes.

Pinned Omarchy source: `omacom/omarchy`, branch `quattro`, commit `94a8c3c3321129fae87a329947711355897e69fd`.
Base: EndeavourOS, Calamares online install, No Desktop.
Shell: Omarchy shell, forked and renamed to Hexciri. Hyprland + Quickshell only, no Niri, no Noctalia. SDDM like Omarchy. systemd-boot + ext4, no snapshots.

## Files

- `bootstrap.sh`, thin wrapper, not a second installer. Download it first, then run it. It downloads the `nyx` branch as a public tarball, no git, no auth, verifies it contains `v2/install.sh`, then runs it. It extracts to a temp dir, not `~/.local/opt/hexciri`, which holds the v1 checkout.
- `install.sh`, the installer. Run as a normal user, not root, on a fresh EndeavourOS no-DE install. It does packages, GPU drivers, Quickshell, Hyprland, SDDM + uwsm, then forks Omarchy at the pinned commit, renames it inline, places the tree to `/usr/share/hexciri`, `~/.config/hexciri`, `~/.local/state/hexciri`, and `~/.config/hypr`, and verifies placement. Sudo only for `/usr/share` and `/etc` steps.
- `hexciri-base.packages`, minimal package list. No apps, no GUI preinstalls.
- `hexciri-tools.toml`, mise tools: node, uv, gh, lazy. No AI agent CLIs, no Herdr.
- `hexciri-update-hexciri`, Hexciri self-update. Git sync of `nyx` to `~/.local/opt/hexciri-nyx`, tarball fallback only.
- `hexciri-theme-ansi`, theme-matched green/red for update output, from the active theme, fallback dirty.pizza `#33ff99` / `#ff3333`.
- `hexciri-theme-hook-gtk.sh`, `hexciri-theme-hook-adapta.sh`, `hexciri-theme-hook-thpm.sh`, `hexciri-theme-hook.toml`, `hexciri-theme-env.sh`, theme-set.d hooks. GTK/signals, Adapta opt-in, THPM.
- `hexciri-theme-link`, trusted theme symlinks, restores theme Lua. `hexciri theme link <git-url>`.
- `hexciri-theme-sync`, bulk themes. `hexciri theme sync`, reads `~/.config/hexciri/themes.list`.
- `hexciri-web-search`, web search, `Mod+Shift+S`, QS prompt, Brave Origin.
- `hexciri-custom-binds.lua`, Hexciri-only binds. `hexciri-custom-apps.lua`, Hexciri-only window rules.
- `hexciri-font-maple-cn-present`, Maple Mono NF CN installed check, both AUR names.
- `hexciri-speedtest-client`, curl-based speed test, used by System > Network.
- `hexciri-settings-tabs`, `hexciri-launch-settings`, Settings plugin wiring.
- `install-2.0.sh`, `fork-shell.sh`, Phase 1 reference only. Do not run, their steps are in `install.sh`.

## Install

```bash
curl -LO https://hexciri.dirty.pizza/v2/bootstrap.sh
bash bootstrap.sh
```

Fallback, raw GitHub:

```bash
curl -LO https://raw.githubusercontent.com/Deoxizn/hexciri/nyx/v2/bootstrap.sh
bash bootstrap.sh
```

Then reboot, pick Hexciri at SDDM. Run from tty3 if you can, the installer replaces `/usr/share/hexciri` under the running shell.

## Update

```bash
hexciri update
```

System packages first (pacman, yay for AUR, mise), then Hexciri self-update. The installer re-runs only when its sha changed. Fingerprints decide how much: all match, light-sync; patch only, re-apply; provision only, re-apply-provision; anything else, full installer. First update after a system-range change is full by design, then it goes quiet again. User files (`shell.json`, Hyprland Lua, `kitty.conf`, current theme) are preserved on re-runs, upstream changes land as `.hexciri.new`.

## What is in the fork

- EndeavourOS no-DE base: Hyprland, uwsm, SDDM, portals, polkit, Qt6, fonts, CLI helpers.
- GPU branching: AMD Mesa/Vulkan, Nvidia Turing+ `nvidia-open`, Nvidia Pascal GTX 1080 Ti `nvidia-580xx-dkms` from AUR, never `nvidia-open` on Pascal.
- Dracut, not mkinitcpio. No Limine, no snap/btrfs, no Plymouth, no LUKS scripts.
- Forked Omarchy shell, verbatim then renamed: `shell/`, `default/hypr/` Lua, `config/` templates, `default/hexciri/hexciri-menu.jsonc`, `themes/` (23 themes), `default/bash/env-bootstrap`, and only the `bin/` scripts the shell actually calls.
- Theme format (`colors.toml` + `shell.toml`) and plugin format stay Omarchy compatible.
- Defaults: Kitty, Strata, Brave Origin, Zed, imv, zathura, bottom (`btm`), JetBrainsMono, Maple Mono NF.
- Menu: full Install/Remove restored, no Omarchy specifics (no preinstalls, no Windows), AI agent options in, Herdr out, Foot as a terminal option, Kitty default.
- Learn: Keybindings, Hexciri, Hyprland, Arch, Zed, Bash, Fish, Kitty, Quickshell, Tmux. No Neovim, no Community.
- Settings plugin, `pizza.dirty.settings`, `Mod+Ctrl+S`. Nyxiri and wallcraft optional, `nyx` branches only.

## What is NOT here

- No Noctalia, no Niri. Hyprland + Quickshell only.
- No apps beyond the defaults above, no Docker, no Herdr.
- No vendored copy of every Omarchy QML file in this repo. The installer is the vendoring mechanism: it downloads the pinned upstream commit as a tarball at install time, extracts the subsets, and renames them. Pinned SHA, subset list, and rename map are in `install.sh`.
- No `/patches` dir yet. Fork patches are still inline in `install.sh`, which is why it is 7,000+ lines. Moving them out is the next cleanup, see below.

## Test after install

1. Reboot, SDDM, pick Hexciri, log in.
2. Hyprland starts, no black screen, no immediate logout.
3. `Mod+Space` apps, `Mod+Alt+Space` menu, `Mod+Ctrl+S` Settings.
4. `hexciri-theme-set` a stock theme, check bar and menu recolor.
5. `hexciri update`, check it completes, then run it again, check the second run is short (re-apply or light-sync, not full).

If Hyprland fails: check version, 0.57 is Lua only, a stray `hyprland.conf` is ignored. Check GPU driver matches the card. Check `journalctl --user -u hyprland` and `uwsm check`.

## Next cleanup

Move the inline fork patches out of `install.sh` into a `/patches` dir, one file per patch, applied in order by the installer. That shrinks `install.sh`, makes a patch change just that file, and lets fingerprints hash the patches dir instead of a giant script range. Do it as a clean refactor on its own commit, not mixed with a bug fix.
