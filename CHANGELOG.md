# Changelog

## 2026-09-04

- hexciri v0.1.0: own Arch-based Niri + Noctalia distro.
-  curl bootstrap from the Arch ISO (9 typed prompts, full-disk or free-space dual-boot, ext4/btrfs, optional LUKS, systemd-boot, SDDM autologin) and `./install.sh` for existing vanilla Arch
- Channels: stable (pinned Arch snapshot) + bleeding (edge Arch), `--channel` only pre-fills the prompted default; kernel menu covers stock/lts/omarchy/bore/muqss with systemd-boot defaults
- Theme engine on colors.toml: `hexciri-theme-set` regenerates kitty/fuzzel/Strata/fish/Zed/Noctalia/Niri from one palette, hookable via `hooks/theme-set.d/`; maiden theme sakurazuki, various-arch seeded
- Suite of 16 vanilla commands (menu, terminal, defaults, update, gpu, power, lock, keybinds, agent, clipboard, screenrecord, gaming, webapps) with every KDL bind resolving; defaults are kitty/fish/brave-origin/strata/zed/opencode
- GPU autodetect: nvidia-open 6xx on Turing+, 580xx with hard LTS pin on Maxwell/Pascal/Volta, mesa/vulkan otherwise, Niri modeset plumbing included
- Branding surfaces: SDDM emblem greeter, plymouth two-step splash with graphical LUKS prompt, fastfetch seed, starship prompt, emblem + lockup art
- Privilege boundary: installer split into a root system phase and a sudoless user phase, so nothing depends on sudo prompting without a terminal; AUR builds as the user with root installing the finished package ([`be85d91`](https://github.com/Deoxizn/hexciri/commit/be85d91), [`af3b6b5`](https://github.com/Deoxizn/hexciri/commit/af3b6b5))
- Kernel policy: exactly one kernel on fresh installs — custom picks replace the staged base (entries generated per installed kernel); custom kernels refused unless in configured repos, hard LTS pin on GTX 1xxx or older ([`d7b2eb9`](https://github.com/Deoxizn/hexciri/commit/d7b2eb9), [`41200f6`](https://github.com/Deoxizn/hexciri/commit/41200f6))
- Prompts: `/dev/tty` reads for piped runs, password confirm, GeoIP timezone chain, disk questions last with a pre-wipe summary gate, archfi-style file-first flow (`sh hexciri`)
- GPU setup baked into the install (auto-detect, `--kernel` preselect); mesa stack in the base set
