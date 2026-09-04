# Changelog

## 2026-09-04

- hexciri v0.1.0: own Arch-based Niri + Noctalia distro.
-  curl bootstrap from the Arch ISO (9 typed prompts, full-disk or free-space dual-boot, ext4/btrfs, optional LUKS, systemd-boot, SDDM autologin) and `./install.sh` for existing vanilla Arch
- Channels: stable (pinned Arch snapshot) + bleeding (edge Arch), `--channel` only pre-fills the prompted default; kernel menu covers stock/lts/omarchy/bore/muqss with systemd-boot defaults
- Theme engine on colors.toml: `hexciri-theme-set` regenerates kitty/fuzzel/Strata/fish/Zed/Noctalia/Niri from one palette, hookable via `hooks/theme-set.d/`; maiden theme sakurazuki, various-arch seeded
- Suite of 16 vanilla commands (menu, terminal, defaults, update, gpu, power, lock, keybinds, agent, clipboard, screenrecord, gaming, webapps) with every KDL bind resolving; defaults are kitty/fish/brave-origin/strata/zed/opencode
- GPU autodetect: nvidia-open 6xx on Turing+, 580xx with hard LTS pin on Maxwell/Pascal/Volta, mesa/vulkan otherwise, Niri modeset plumbing included
- Branding surfaces: SDDM emblem greeter, plymouth two-step splash with graphical LUKS prompt, fastfetch seed, starship prompt, emblem + lockup art
