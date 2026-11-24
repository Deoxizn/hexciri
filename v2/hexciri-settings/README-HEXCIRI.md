# Hexciri Settings — fork notes

Fork of [ipkalid/omarchy-settings](https://github.com/ipkalid/omarchy-settings),
master commit `ad54288477ad778ae054ee584348c1879a167721`, version 1.6.5.
MIT, original author Khalid Alhazmi. Devi 2026-11-24: fork it, do not
build settings from ground zero; convert from a shell plugin to an app.

## What changed in the fork

- **Rename, file/path/CLI level:** `omasettings` -> `hexciri-settings`,
  `omarchy` -> `hexciri` everywhere (paths `~/.config/hexciri`,
  `~/.local/state/hexciri`, `$HEXCIRI_PATH=/usr/share/hexciri`,
  CLI calls `hexciri theme set`, `hexciri bar`, `hexciri plugin`, …).
  Plugin support stays: the Plugins pane drives `hexciri plugin …`,
  which is why the Omarchy plugin format/API had to stay compatible.
- **App, not a plugin:** the upstream `plugin/` wrapper (Service.qml
  auto-build on shell enable) is gone. This source is built by
  `./install` (adapted from the plugin install script) into
  `~/.local/bin/hexciri-settings`, desktop entry
  `~/.local/share/applications/hexciri-settings.desktop`, icon
  `~/.local/share/icons/hicolor/scalable/apps/hexciri-settings.svg`.
  The Hexciri installer runs `./install --quiet` on install/update;
  the build needs `gcc make qt6-base qt6-declarative qt6-wayland
  qt6-imageformats squashfs-tools` (all in Hexciri CORE_PKGS except
  squashfs-tools, which the installer adds).
- **No update channel:** Hexciri has no channel. The channel selector
  in General > Update and the channel row in General > About are gone;
  updates follow the nyx branch via `hexciri update`.
- **No Herdr:** the herdr theme-sync toggle is removed (Herdr is out
  of Hexciri v2 scope). The Herdr editor row in Appearance hides itself
  when the `herdr` binary is absent.
- **`hexciri-launch-config-editor` does not exist** in the fork; the
  app calls `hexciri-launch-editor` instead (same path argument).
- **Nyxiri tab hook:** `Store::list("extraPanes")` reads
  `~/.config/hexciri/settings-panes/*.json`
  (`{id, title, glyph, group, keywords, qml}`) and Main.qml appends
  them to the sidebar, loading the pane QML from the given file path.
  Nyxiri adds its tab with one call, no Settings rebuild:
  `hexciri-settings-tabs add nyxiri "Nyxiri" <path to NyxiriPane.qml>`.
  See `../hexciri-settings-tabs` (repo root `v2/`).

## Icon — placeholder, Devi supplies the exact one later

`pkgbuild/hexciri-settings.svg` is the upstream gear, kept as a
placeholder. To swap it, replace that ONE file in this repo; the
installer / `./install` copies it to
`~/.local/share/icons/hicolor/scalable/apps/hexciri-settings.svg`.
No code change, no rebuild of the binary needed (the icon is a file,
not compiled in).

## Rebuild by hand

```bash
~/.local/opt/hexciri-settings/install   # rebuild + reinstall, user only
hexciri-settings open appearance        # open a pane: hexciri-settings open <pane>
```

## Menu lean

Settings now covers what used to be 26 buried Super+Alt+Space leaf
rows (bar position/background, dock position/autohide, window
corners/transparency, DNS choices). The installer removes those rows
from `hexciri-menu.jsonc` and adds a top-level Settings row that opens
this app. Install/Remove/Update/Learn/System rows stay in the menu;
they are actions, not settings.
