# Design: WM + Shell choice

Status: draft — scoping, not implemented. Aimed at **v1.4**.

The idea: the framework stays minimal and fast (a repo-runtime scripts/theme/updater stack), but
the *session* it drives becomes a choice — **which window manager** and (for WMs that want one)
**which shell**. Same install, same theme, same menu, same one-press updater; the compositor/IPC
layer and the shell startup differ per combo.

## 1. The core insight

Noctalia already supports many compositors without per-compositor porting
(Niri, Hyprland, Sway, Scroll, Mango, Labwc, Triad, dwl from its own docs). That means
**the shell side is not the per-WM surface**. The only WM-specific surfaces are:

1. **IPC dispatch** — screenshot, reload, lock, power-off, quit, focus/spawn, keybind apply.
   Right now that is `niri msg …`/`config.kdl` hardcoded in ~10 scripts + the theme hook.
2. **Install flavoring** — which compositor/session/`config/<wm>/` to deploy.
3. **A per-WM "borders/behavior" theme snippet** — the only WM-specific part of theme rendering
   (covered in §5).

A generic tool-only fallback (`grim`/`slurp`, shell-driven lock, `loginctl`) is a first-class
backend, so WM's without proper IPC (dwm, dwl) are not extra work — they're the default.

## 2. The matrix

Two independent choices. Not all combos are valid.

```
shell  ∈ { noctalia, caelestia, none }
wm     ∈ { niri, hyprland, sway, labwc, mango, dwl, scroll, … }
```

| WM | shell=noctalia | shell=caelestia | shell=none |
|----|----------------|-----------------|------------|
| niri      | **today** ✓ | ✗ (Caelestia is Hyprland-tied) | ✓ bare tiling |
| hyprland  | ✓ (shim needed) | ✓ (the "omartia" remux) | ✓ |
| sway      | ✓ | ✗ | ✓ |
| labwc/mango/dwl/scroll | ✓ (noctalia-supported) | ✗ | ✓ minimal |

`shell=none` is *not* a downgrade of noctalia — it's the honest minimal corner (dwm/dwl mindset):
WM + kitty + fuzzel + grim. Menu/keybinds/theme/update still work; bar/OSD/launcher shell does not
exist by choice, and the theme hook simply skips the shell render targets.

The selector = one file, e.g. `~/.config/hexciri/wm` (contains `niri`, `hyprland`, …) and
`~/.config/hexciri/shell` (`noctalia`, `caelestia`, `none`), or a single `session` value
(`niri-noctalia`, `hyprland-caelestia`, `dwl-none`). install.sh writes it at install; a
`hexciri-session-set` command changes it deliberately (like channel-set).

## 3. Compositor shim

New `bin/hexciri-compositor` — one entry point, one dispatch table. Every tool currently
calling `niri msg …` instead calls `hexciri-compositor <op> [args]`.

### Ops (the full current surface)

| op | niri | hyprland | generic fallback |
|----|------|----------|------------------|
| `wm` | `niri` | `hyprland` | XDG_CURRENT_DESKTOP |
| `screenshot [region\|screen]` | `niri msg action screenshot` | `hyprctl` + `grim` | `grim` (+`slurp` for region) |
| `focused-output` | `niri msg focused-output` | `hyprctl activeworkspace` | `grim`-independent (n/a → "" ) |
| `outputs-json` | `niri msg --json outputs` | `hyprctl -j monitors` | sysfs/EDID via `hexciri-hw-*` |
| `window-id-for` `<pattern>` | `niri msg --json windows` | `hyprctl -j clients` | n/a (use tool-only launch) |
| `focus-window` `<id>` | `niri msg action focus-window --id` | `hyprctl dispatch focuswindow` | n/a |
| `load-config` | `niri msg action load-config-file` | `hyprctl reload` | SIGHUP WM pid (dwm/dwl) |
| `spawn` cmd | `niri msg action spawn --` | `hyprctl dispatch exec` | `setsid` / `nohup` |
| `lock` | noctalia msg session lock | hyprlock | `swaylock` / noctalia msg |
| `power-off` | `niri msg action power-off-monitors` | `hyprctl dispatch dpms off` | `loginctl` /
| `quit` | `niri msg action quit` | `hyprctl dispatch exit` | `loginctl terminate-session` |

Dispatch rule per op: try native WM row → on failure/empty, fall to generic → generic itself may
delegate to the shell (`noctalia msg session lock`) when a shell exists. Every tool keeps its
existing `|| note "…"` style; no tool learns about WMs.

Implementation: tiny `case` on `$WM` inside one script, `$WM` resolved from
`~/.config/hexciri/wm` (authoritative) with `XDG_CURRENT_DESKTOP` fallback. Config & shell files
derive from the same values, so nothing else needs to detect anything.

## 4. Install flavor

`install.sh` takes the combo (via flags or `hexciri-session-set`-style config) instead of
hardcoding niri:

```
--wm=niri|hyprland|sway|…
--shell=noctalia|caelestia|none
```

then:

- **packages**: `niri` ↔ `hyprland` ↔ `sway` etc.; `caelestia`/quickshell pulled only for that shell.
- **session file**: `${wm}.desktop` under `/usr/share/wayland-sessions` (already generated like the current `niri.desktop`).
- **config deploy**: `config/<wm>/{…}` instead of `config/niri/config.kdl` only.
- **shell startup**: noctalia spawn-at-startup (already in niri config.kdl) is WM-config-dependent —
  the per-WM config carries `spawn-at-startup "noctalia"` only when `shell != none`, and the Caelestia
  variant spawns quickshell instead.
- **theme hook**: becomes `hexciri-sync.sh` (§5) — shell render (unchanged) plus a per-WM borders +
  keybind block for each installed WM; nothing renders WM config for `shell=none`.

## 5. Theme hook generalization (`noctalia-sync.sh` → `hexciri-sync.sh`)

Today `hooks/theme-set.d/noctalia-sync.sh` does: (1) write the Noctalia palette JSON, (2) patch
Noctalia `config.toml`, (3) write the qt6ct Qt color scheme, (4) sync wallpaper via
`noctalia msg wallpaper-set`, and (5) **patch `config.kdl` borders** — line (5) is the only
WM-specific one. The rename makes the split explicit:

1. **WM-independent render (always runs, unchanged)**: Noctalia palette, `config.toml`, qt6ct,
   wallpaper. These touch only the shell/app layer and are identical under every WM.
2. **Per-WM render (new, small, idempotent)**: for **each installed** WM config under
   `config/<wm>/`, write the tiny theme surface — border colors, and (v1.4's job) the keybind
   block. Under `hyprland` that's border color settings; under `sway` that's `client.focused`;
   under `mango` it's KDL like niri. `shell=none` simply means "no step 1".

Rename is cosmetic-plus: `noctalia-sync.sh` gains the per-WM loop and the new `bin/hexciri-keybinds`
renderer call. The theme hook stops being "the shell sync" and becomes the session-wide theme
sync. There are no other theme hooks that touch WM configs today.

Result: a theme switch re-skins whatever WMs are installed, so booting Sway after configuring Niri
still shows correct borders/colors; nothing is niri-only in the theme layer anymore.

## 6. Keybinds intent schema (the "one set, every WM" guarantee)

The distro promise: **muscle memory survives a WM switch.** So keybinds are not maintained per-WM —
there is one intent schema, and each WM is a tiny renderer from intents to that WM's syntax.

Current `config/niri/config.kdl` has 70 bind lines: 32× `spawn`/`spawn-sh` (launcher, menu,
terminal, browser, editor, webapps, lock, power, clipboard, notifications, screenrecord), 4× `wtype`
emulated copy/paste/cut (explicitly WM-agnostic), and ~34 layout/window/workspace binds (the
WM-specific ones). The spawn/wtype binds are already 100% portable — they execute commands, nothing
else. Only the layout binds need mapping.

New layout:

```
config/keybinds/
    intents.toml        # THE schema — one row per intent (key combo → intent name)
    niri.kdl            # renderer: intent → niri action
    hyprland.conf       # renderer: intent → hyprland action
    sway.conf           # renderer: intent → sway action
    mango.kdl           # renderer: intent → mango action
```

`intents.toml` is the single source of truth (keys fixed once):

```toml
mod = "Mod"
Mod+Return      = "terminal"
Mod+Space       = "launcher"
Mod+Alt+Space   = "root-menu"
Mod+Q           = "close-window"
Mod+Left        = "focus-left"
Mod+Ctrl+Left   = "move-left"
Mod+1           = "ws-1"
Mod+Shift+1     = "move-to-ws-1"
Mod+Print       = "screenshot"
Mod+Ctrl+Print  = "screenshot-clipboard"
Mod+Escape      = "power-menu"
Mod+Ctrl+L      = "lock"
# …rest of the 34 layout binds
```

Renders via `bin/hexciri-keybinds` (today: parses `config.kdl`; after: renders the active WM's
block from intents + bind spawns, and is also the readable reference). Mapping table per intent:

| intent | niri | hyprland | sway | mango |
|--------|------|----------|------|-------|
| close-window | `close-window` | `closeactive` | `kill` | `close` |
| focus-left | `focus-column-left` | `movefocus l` | `focus left` | like niri |
| move-left | `move-column-left` | `movewindow l` | `move left` | like niri |
| ws-1 | `focus-workspace 1` | `workspace 1` | `workspace 1` | like niri |
| move-to-ws-1 | `move-column-to-workspace 1` | `movetoworkspace 1` | `move workspace 1` | like niri |
| screenshot | `screenshot` | `grim` + `wl-copy` | `grim` + `wl-copy` | `grim` |
| overview | `toggle-overview` | `overview:toggle` | (n/a) | (n/a) |

True semantic gaps exist (niri's column consume/expel, tabbed columns, preset column width map to
sibling actions in hyprland, a loaded question in sway/mango). Policy: map to a best-effort sibling
where the WM has one, otherwise drop the intent with a note visible in `hexciri-keybinds`. The
intents that exist are uniform everywhere; the WM-only ones are explicitly documented per row — not
silently missing.

The WM config deploy (section 4) and the theme hook (section 5) both source the rendered keybind
block, so install, theme-set, and `hexciri-sync` all regenerate the same single-source-of-truth
binds into every installed WM.

## 7. What changes where (concrete)

| file | today | after |
|------|-------|-------|
| `bin/hexciri-capture` | `niri msg …` ×4 | `hexciri-compositor screenshot` |
| `bin/hexciri-screenrecord` | `niri msg outputs/windows` ×3 | shim `outputs-json`/`window-id-for` |
| `bin/hexciri-launch-or-focus-webapp` | `niri msg --json windows` ×2 | shim |
| `bin/hexciri-restart` | `niri msg load-config-file` ×2 | shim `load-config` |
| `bin/hexciri-toggle-input-device` | `niri msg load-config-file` ×2 | shim `load-config` |
| `bin/hexciri-power` | `niri msg action quit` | shim `quit` |
| `bin/hexciri-keybinds` | reads `config.kdl` | renders active WM block from `intents.toml` |
| `bin/hexciri-lock` | noctalia/niri | shim `lock` |
| hooks/theme-set.d/noctalia-sync.sh | writes `config.kdl` | `hexciri-sync.sh`: shell render (unchanged) + per-WM borders + keybinds |
| install.sh | `niri` pkg/session/config hardcoded | `--wm`/`--shell` flavoring |
| fastfetch | niri badge | `$WM` + `$SHELL` names |

Migration: `hexciri-migrate-niri-path` already exists; generalize to "add `~/.local/bin` to the
WM config PATH" guarding on whichever WM config exists. No data migration otherwise — the runtime
stays repo-based regardless of flavor.

## 8. Open questions

1. Single `session` value vs separate `wm`+`shell` files — separate is more flexible (any WM ×
   any shell later), single is simpler to render in the menu/fastfetch.
2. Does the menu show a "Session/WM" item (like Channel/Themes), or is it strictly an install-time
   choice? (The updater's `update_cmd` plugin concern lives in the Noctalia shell layer only.)
3. Caelestia: port as a whole second shell surface (its own state/IPC/theme paths) — likely its
   own `hooks/theme-set.d/caelestia-*.sh` set, driven by the same `shell=caelestia` value. Is that
   a v2 spike or a "hyprland-only postscript"?

## 9. v1.4 scope proposal

- **v1: niri + hyprland + sway** (all `extra`, rich native IPC, hot reload) — the validated rows.
- **v1.4 (this doc)**: `hexciri-compositor` shim + install `--wm`/`--shell` flavoring +
  `hexciri-sync.sh` rename with per-WM theme render + keybinds intent schema. `mango` ships as an
  **experimental row** (generic-fallback IPC, documented as unstable).
- **Mango instability is not hexciri's risk**: the fallback row absorbs it. The *real* single
  point of failure is the omarchy kernel (`linux-omarchy-bore` = the only kernel). Hedge it (install
  stock as a boot fallback) rather than abandon it — install.sh already supports `--kernel=stock|lts`.