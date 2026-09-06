# Theme sources

Two kinds of theme set exist in hexciri:

- **Omarchy defaults** — the 22 themes that ship with `omarchy`. They are seeded
  on a fresh install and kept up to date by the **Hexciri updater** (Repo sync).
  You don't curate these; they just ride along.
- **Extra themes** — everything else. One flat list, `extra.list`, of
  `<owner>/<name>` lines. This is the bit you handpick.

## The extras list

`config/theme-sources/extra.list` is the source of truth for the "Extra themes"
feature. One theme per line, owner/name form, `#`-commented lines ignored:

```
HANCORE-linux/aamis
HANCORE-linux/sapphire
OldJobobo/dracula
```

Everything is list-driven:

- **Sync extra themes** clones every line into `~/.config/hexciri/themes/`.
- **Removing a line** uninstalls that theme on the next sync (the list is the
  truth, so anything locally present but not listed gets dropped) — subject to
  the exception that a name already in the Omarchy defaults is never touched.
- **Update ▸ Extra themes** `git pull`s every listed theme.
- **Install theme** (Themes menu) appends `owner/name` to your override list, so
  a one-off install becomes part of the same list-managed set.
- Any theme whose name is also in the Omarchy defaults is skipped and never
  installed or removed from this list.

## Per-theme-repo convention

An extra theme is cloned from `https://github.com/<owner>/omarchy-<name>-theme.git`
(the same naming the shipped Omarchy set uses). Adding a new creator is just
adding their `owner/name` lines — no new config files.

## Curation on your own machine

The list ships read-only at `/usr/share/hexciri/theme-sources/extra.list`. To
handpick without touching the repo, keep your own copy under
`~/.config/hexciri/theme-sources/extra.list` — it overrides the shipped one.
`hexciri-theme-install` seeds that override for you automatically.

## Omarchy defaults catalog

`omarchy.conf`/`omarchy.list` describe the shipped set (monorepo sparse clone of
`omacom/omarchy`, `themes/` subtree). They are bookkeeping only — use the
**Hexciri updater** to update those themes, and the **Remove Omarchy defaults**
entry under Extra themes to drop them.
