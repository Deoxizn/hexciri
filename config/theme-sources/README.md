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

Everything is list-driven — **Sync extra themes** (Themes menu) is the whole
job and runs from **Update ▸ Extra themes** too:

- clones every line into `~/.config/hexciri/themes/` that isn't there yet,
- `git pull`s every line that's already installed,
- removes any locally-cloned extra whose line was deleted from the list (the
  list is the source of truth). A name already in the Omarchy defaults is never
  touched.

## Per-theme-repo convention

An extra theme is cloned from `https://github.com/<owner>/omarchy-<name>-theme.git`
(the same naming the shipped Omarchy set uses). Adding a new creator is just
adding their `owner/name` lines — no new config files.

`hexciri-theme-install <git-url>` also adds a theme: it validates the URL,
sanitizes the name, appends `owner/name` to your override list, and clones it —
so a one-off install becomes part of the same list-managed set.

## Curation on your own machine

The list ships read-only at `/usr/share/hexciri/theme-sources/extra.list`. To
handpick without touching the repo, keep your own copy under
`~/.config/hexciri/theme-sources/extra.list` — it overrides the shipped one.
**Config ▸ Extra themes list** opens that override for editing (seeding it from
the shipped copy the first time).

## Omarchy defaults catalog

`omarchy.conf`/`omarchy.list` describe the shipped set (monorepo sparse clone of
`omacom/omarchy`, `themes/` subtree). They are bookkeeping only — the **Hexciri
updater** / **Repo sync** seeds them if missing and keeps them current.
