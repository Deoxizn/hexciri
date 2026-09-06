# Theme sources

Two kinds of theme set exist in hexciri:

- **Omarchy defaults** — the 22 themes that ship with `omarchy`. They are seeded
  on a fresh install and kept up to date by the **Hexciri updater** (Repo sync).
  You don't curate these; they just ride along.
- **Extra themes** — everything else. One flat list, `extra.list`, of
  `<owner>/<name>` lines. This is the bit you handpick.

## The lists

Two lists, both edited from **Config**:

- `config/theme-sources/extra.list` — handpicked **Extra themes**. One line per
  theme, `<owner>/<name>` form, `#`-commented lines ignored:

  ```
  HANCORE-linux/aamis
  HANCORE-linux/sapphire
  OldJobobo/dracula
  ```

  A line can also be a full `https://github.com/<owner>/<repo>` URL when the
  repo doesn't follow the `omarchy-<name>-theme` convention.
- `config/theme-sources/omarchy.list` — the shipped **Omarchy defaults**. Editing
  your copy lets you prune or add to the default set.

Everything is list-driven. **Sync themes** (Themes menu) — the same action as
**Update ▸ Update themes** — does the whole job for both lists:

- **Omarchy defaults**: pulls the sparse source clone, links anything new,
  unlinks any symlink whose name you removed from the omarchy list.
- **Extra themes**: clones every listed line that isn't installed, `git pull`s
  every installed one, and removes any locally-cloned extra whose line was
  deleted from the list.

**Remove extra themes** (Themes menu) tears down all installed extras in one go.

## Per-theme-repo convention

An extra theme is cloned from `https://github.com/<owner>/omarchy-<name>-theme.git`
(the same naming the shipped Omarchy set uses). Adding a new creator is just
adding their `owner/name` lines — no new config files.

`hexciri-theme-install <git-url>` also adds a theme: it validates the URL,
sanitizes the name, appends `owner/name` to your override list, and clones it —
so a one-off install becomes part of the same list-managed set.

## Curation on your own machine

The lists ship read-only at `/usr/share/hexciri/theme-sources/`. To handpick
without touching the repo, keep your own copies under
`~/.config/hexciri/theme-sources/` (`extra.list`, `omarchy.list`) — they
override the shipped ones. **Config ▸ Extra themes list** and **Config ▸
Omarchy themes list** open those overrides for editing, seeding them from the
shipped copies the first time.

## Omarchy defaults catalog

`omarchy.conf`/`omarchy.list` describe the shipped set (monorepo sparse clone of
`omacom/omarchy`, `themes/` subtree). The **Hexciri updater** / **Repo sync**
seeds them if missing and keeps the sparse clone current; editing your own
`omarchy.list` override prunes/adjusts what actually gets symlinked.
