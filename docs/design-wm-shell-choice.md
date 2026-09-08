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

## 4. Install flavor AND in-place switch

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
- **shell startup**: any spawn-at-startup/autostart that launches noctalia/quickshell is WM-config-dependent —
  the per-WM config carries `spawn-at-startup "noctalia"` only when `shell != none`, and the Caelestia
  variant spawns quickshell instead.
- **theme hook**: becomes `hexciri-sync.sh` (§5) — shell render (unchanged) plus a per-WM borders +
  keybind block for each installed WM; nothing renders WM config for `shell=none`.

The switch is **not install-only**. A new `bin/hexciri-session-set` (mirror of the existing
`hexciri-session`-adjacent channel/menu scripts) performs the same steps on a live machine:

```
$ hexciri-session-set wm=hyprland shell=noctalia   # or from System > Session in the menu
```

and the **System menu** (which already hosts Config > / Kernel > / Reset defaults) gains a
`Session >` entry dispatching it. The flow on an existing install:

1. resolve the target combo from args or the menu picker
2. **pull fresh** (same re-exec guard as the updater funnel — it must not run stale bytes)
3. install the target WM package(s) (sudo) and generate the `${wm}.desktop` session file
4. carry-over the *installed* config — read the current WM's live `~/.config/<wm>/…` (not the repo:
   that's where monitor scale, dual-monitor layout, and personal keybinds actually live) and
   re-render it into the target WM's config (§7)
5. write `~/.config/hexciri/wm` + `~/.config/hexciri/shell` (the selector)
6. regenerate: bin re-links, `hexciri-sync.sh` re-render, keybinds render, `--png` nothing
7. print "log out and pick <wm> in the session picker" — the current session is left untouched

**Install vs swap are two different moments.** A fresh `install.sh` deploys the pristine *repo
default* for the chosen combo — full defaults, no carry-over, nothing to migrate. Carry-over exists
*only* in the swap path (`hexciri-session-set` / System > Session): it reads what the user actually
runs today (their installed `~/.config`, which legitimately diverges from the repo — see the live
`output "DP-4" { mode "3840x2160@144" }` vs the repo's commented `eDP-1` template) and transfers it
into the new WM. The repo file stays the shippable default; the installed file is the machine's
reality.

Because it shares the funnel's pull-and-re-exec guard and the hook's convergence, **running an
update already pulls the latest scripts; switching is a deliberate second action the user presses.**
Existing machines (this DEV machine, the laptop) are never *forced* to a WM — the default stays
`niri` until someone presses System > Session. A fresh install deploys that WM's pristine defaults;
a swap re-renders the *installed* config into the new WM. Same command line either way,
install-time `--wm` is just the non-interactive shortcut (defaults, no carry-over).

**Non-goal: preinstalling every WM.** The switch installs only the target WM (and only the packages
it needs). Shipping all of niri/hyprland/sway/labwc/mango resident is rejected for the same reason
the remuxes (stellarchy/noctarchy) are rejected — it's multi-gigabyte bloat that permanently weighs
on the system and needs a reboot to flip. The selector and the theme hook render only what's actually
installed; a WM is present on disk only while it's the current (or an actively-chosen) session.

**The Remove path completes that loop** (`bin/hexciri-session-remove`, System > Session > Remove):
the switch installs the new WM but never removed the old one, so niri→hyprland→sway stacked all
three resident. The drop script lists installed (non-current, non-running) WMs and, per choice:
back-ups `~/.config/<wm>` into `.config/hexciri-backup/<ts>-<wm>`, removes the WM's packages
(`pacman -Rns`, WM-specific set only — shared deps like xwayland-satellite are pruned as orphans,
never yanked from under another WM), and deletes `/usr/share/wayland-sessions/<wm>.desktop`. It
refuses the active selector WM and the currently-running compositor. The menu gained a Session
submenu (`hexciri-session-menu`): `Install >` (the existing picker) and `Remove >` (installed list).

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

**Look-nfeel ownership note (GROUNDED on this machine)**: Noctalia v5 ships its own
`/usr/share/noctalia/assets/templates/niri/` → `apply.sh` writes
`~/.config/niri/noctalia.kdl` (a fragment with `layout { focus-ring/border/tab-indicator/
insert-hint }` + `recent-windows` colors from the active palette) and injects
`include "noctalia.kdl"` into `config.kdl`. That fragment is exactly our `looknfeel.kdl`
surface. The current hook *regex-patches* the monolithic `config.kdl` instead (the old path);
once we split, the clean design is: hexciri writes `looknfeel.kdl` (its borders/theme) and
either defers the layout-color fragment to Noctalia's own `noctalia.kdl` include or owns it
itself — but NOT both patch the same file. Decision: hexciri keeps a `binds { }`-free
`looknfeel.kdl`, and the hook's step-2 writes that file (per ± theme); Noctalia's own
`noctalia.kdl` include coexists since niri merges `layout` sections (border/`focus-ring`
presence in an include needs no `on` quirk because we always write explicit `on`/`off`).

## 6. Keybinds intent schema (the "one set, every WM" guarantee)

The distro promise: **muscle memory survives a WM switch.** So keybinds are not maintained per-WM —
there is one intent schema, and each WM is a tiny renderer from intents to that WM's syntax.

Current `config/niri/config.kdl` has 70 bind lines: 32× `spawn`/`spawn-sh` (launcher, menu,
terminal, browser, editor, webapps, lock, power, clipboard, notifications, screenrecord), 4× `wtype`
emulated copy/paste/cut (explicitly WM-agnostic), and ~34 layout/window/workspace binds (the
WM-specific ones). The spawn/wtype binds are already 100% portable — they execute commands, nothing
else. Only the layout binds need mapping.

New layout (implemented):

```
config/keybinds/
    intents.toml            # single source of truth:
                            #   [keys]   combo → intent name (79 binds, incl. 9 personal XF86)
                            #   [intents] per-intent: spawn command, or per-WM action columns
                            #               for the ~34 layout binds
bin/hexciri-keybinds        # searchable reference (fuzzel) — reads intents.toml, shows the
                            # active WM's resolved action per combo
bin/hexciri-keybinds-render # [wm] → renders that WM's keybind block to stdout; used by the
                            # theme hook / session-set to write the live config. Multi-word spawns
                            # go through shlex so `sh -c 'grim -g "$(slurp)"…'` stays intact.
```

Combo→intent is fixed once in `intents.toml`; each renderer is a tiny sshlex-aware emitter in
`hexciri-keybinds-render` (niri KDL, hyprland `bind =`, sway `bindsym`, mango `bind=`). Mapping
table per intent (stored as per-WM columns on each `[intents]` row):

| intent | niri | hyprland | sway | mango |
|--------|------|----------|------|-------|
| close-window | `close-window` | `closeactive` | `kill` | `close` |
| focus-left | `focus-column-left` | `movefocus l` | `focus left` | `focus left` |
| move-left | `move-column-left` | `movewindow l` | `move left` | `move left` |
| ws-1 | `focus-workspace 1` | `workspace 1` | `workspace 1` | `tag 1` |
| move-to-ws-1 | `move-column-to-workspace 1` | `movetoworkspace 1` | `move container to workspace 1` | `move-to-tag 1` |
| screenshot | `screenshot` | (via hexciri-compositor) | (via hexciri-compositor) | (via hexciri-compositor) |
| overview | `toggle-overview` | `overview:toggle` | (See NOTE) | (See NOTE) |

True semantic gaps exist (niri's column consume/expel, tabbed columns, preset column width map to
sibling actions in hyprland, a loaded question in sway/mango). Policy: map to a best-effort sibling
where the WM has one, otherwise the row carries a `(See NOTE)` marker and is documented per row — not
silently missing. The spawned/intent rows are uniform everywhere.

The rendered block is validated: `niri validate` passes on the spliced output (chain: strip the
live `binds {}` block, splice the render, validate — clean).

#### Output shape: one file vs per-concern split

Every WM gets hexciri's homegrown split (`include` / `source=` / `conf.d` glob) — no one-size big-file.
Each concern maps 1:1 to a hexciri responsibility so the theme hook and carry-over touch exactly one
fragment, never a whole-config splice:

| concern | source of truth | niri | hyprland | sway |
|---|---|---|---|---|
| monitors/scale/layout | carried over from installed config (verbatim replace) | `niri/monitors.kdl` | `hypr/conf/monitors.conf` | `sway/conf.d/monitors.conf` |
| keybinds | `intents.toml` renderer | `niri/keybinds.kdl` (`bind {}` block) | `hypr/conf/keybinds.lua` | `sway/conf.d/keybinds.conf` |
| look & feel (borders, blur, shadow) | theme hook `hexciri-sync.sh` | `niri/looknfeel.kdl` | `hypr/conf/looknfeel.conf` | `sway/conf.d/looknfeel.conf` |
| window rules / float | §5 intents + carry-over | `niri/window-rules.kdl` | `hypr/conf/window-rules.conf` | `sway/conf.d/window-rules.conf` |
| environment vars | `config-render` (from niri `env.kdl`) | `niri/env.kdl` | `hypr/conf/env.lua` (`hl.env`) | `sway → ~/.config/environment.d/10-hexciri.conf` |
| autostart / noctalia | `config-render` (from niri `autostart.kdl`) | `niri/autostart.kdl` | `hypr/conf/autostart.lua` (`hl.on`) | `sway/conf.d/autostart.conf` (`exec`), mango `autostart.conf` (`exec-once`) |

- **niri**: `include "file.kdl"` (top-level only, since 25.11 — we ship 26.04). Sections merge from
  includes; `window-rule`/`output`/`workspace` are multipart and insert *as-is*. Two niri quirks:
  (1) `layout { border {} }` written in an *included* file does nothing without an explicit `on`
  (historical: presence enabled the border only in the main file) — our `looknfeel.kdl` always writes
  `on`/`off` explicitly; (2) multipart sections never merge, so carry-over for `monitors.kdl` is a
  **whole-file replace**, never an append. All fragments are watched → theme changes hot-reload.
- **hyprland**: **Lua** (0.56+; hyprlang `.conf` deprecated → dropped ~0.57). `require("hypr.conf.<concern>")` from `hyprland.lua`; each concern is a `.lua` fragment (`hl.env`/`hl.config`/`hl.on`). Split for real; carry-over is a renderer drop (`hexciri-config-render`).
- **sway**: `include ~/.config/sway/conf.d/*` (glob). Same split; carry-over is a renderer drop. Env has NO sway directive — lands in `~/.config/environment.d/10-hexciri.conf`.
- **mango**: single `config.conf` supports `source=`/`source-optional=` (docs: sub-configuration) — same concern-split as the rest; `env.conf`/`input.conf`/`autostart.conf` sourced from the entry file.

The WM config deploy (section 4) and the theme hook (section 5) both source the rendered keybind
block, so install, theme-set, and `hexciri-sync` all regenerate the same single-source-of-truth
binds into every installed WM.

## 7. Carry-over on switch (bindings, monitors, notifications)

The recurring question on a WM switch is "do I lose my customizations?" — answered per surface,
not hand-waved. **The source is always the installed `~/.config/<current-wm>/…`, never the repo
template** — that's where the machine's real choices live (metrics, second monitors, personal binds).

- **Keybindings**: the intent schema (§6) *is* the carry-over. The 32 spawn + 4 wtype binds are
  already WM-agnostic (`spawn "…"` executes a command); only the ~34 layout binds need mapping, and
  the mapping table renders the same intent into each WM. A personal bind (*only I use this*) is
  just another row in `intents.toml` — if its *action* has a sibling in the target WM it transfers;
  if the bind is a `spawn "…"` of a custom command it transfers verbatim; only a genuinely
  niri-specific semantic (column consume/expel) survives as a best-effort sibling or a visible
  `# NOTE:`. Never silently dropped.
- **Monitor settings**: *exactly the case you raised*. The live `output` blocks in the installed
  `config.kdl` — your `scale` on the laptop panel, your `output "DP-4" { mode "3840x2160@144" }`
  second monitor, dual-monitor positions, VRR, rotation — are parsed into a **monitor intent** and
  rendered into the target WM's syntax: `output` blocks under niri/sway, `monitor = NAME,res@rate,pos,scale`
  lines under hyprland. Per-output scale and mode transfer directly; multi-monitor *positions* map
  to the closest sibling or land as a `# NOTE:` in the rendered config.
- **Notifications**: **shell-owned, not WM-owned** — the notification center, OSD placement, panel,
  and "which notifications appear where" live in Noctalia's config (`noctalia msg panel-toggle
  notifications`; `config.toml`), *not* in the WM. A WM swap that keeps `shell=noctalia` carries
  your notification setup across with literally zero work — only the *binds* that open/clear the
  panel sit in the WM config, and those are spawn binds, already portable. That includes
  per-window/per-output notification placement: it's a shell choice, so it survives untouched.
  (Under `shell=none` there's no notification center by design, so nothing carries.)

The global policy matches §6's: **copy where the WM has a sibling, otherwise emit a visible `# NOTE:`
in the rendered config — never silently drop.** Personal edits transfer; only the semantics the new
WM simply cannot express are surfaced as notes for the user, never quietly lost.

## 8. What changes where (concrete)

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

## 9. Open questions

1. Single `session` value vs separate `wm`+`shell` files — separate is more flexible (any WM ×
   any shell later), single is simpler to render in the menu/fastfetch.
2. Does the menu show a "Session/WM" item (like Channel/Themes), or is it strictly an install-time
   choice? (The updater's `update_cmd` plugin concern lives in the Noctalia shell layer only.)
3. Caelestia: port as a whole second shell surface (its own state/IPC/theme paths) — likely its
   own `hooks/theme-set.d/caelestia-*.sh` set, driven by the same `shell=caelestia` value. Is that
   a v2 spike or a "hyprland-only postscript"?

## 10. v1.4 scope proposal

**DECIDED — approved, in build.** The supported matrix is:

| WM | status | carry-over |
|----|--------|------------|
| niri      | **solid (today)** | — |
| hyprland  | **solid** | monitor + keybind + shell-native |
| sway      | **solid** | monitor + keybind + shell-native |
| mango     | **experimental** | generic-fallback IPC, documented as unstable — a real alternative if you like niri |
| (shell=none) | first-class minimal corner | theme hook skips shell targets |

- **v1.4 (this doc)**: `hexciri-compositor` shim + `hexciri-session` (wm/shell resolution) +
  `hexciri-session-set` (System > Session) + install `--wm`/`--shell` flavoring +
  `hexciri-sync.sh` rename with per-WM theme render + keybinds **and monitor** intent schema.
- **Mango instability is not hexciri's risk**: the fallback row absorbs it. The *real* single
  point of failure is the omarchy kernel (`linux-omarchy-bore` = the only kernel). Hedge it (install
  stock as a boot fallback) rather than abandon it — install.sh already supports `--kernel=stock|lts`.

Approved build order: shim → session resolution → migrate niri callers → keybinds/monitor intent
schema → `hexciri-session-set` + System > Session → `hexciri-sync.sh` rename → install flavoring →
validate on niri + converge both machines.