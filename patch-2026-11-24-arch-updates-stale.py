#!/usr/bin/env python3
"""Patch Arch-Updates nyx (2026-11-24, Devi 13:38 MST).

Bugs:
1. Stale count after an update. check_updates.py plugin_behind() (and
   update_plugins_themes.py plugin_behind_count()) fetched "origin HEAD"
   and counted HEAD..FETCH_HEAD. For nyx plugins origin HEAD is main:
   once main moves ahead of nyx, a nyx plugin counts as behind main
   forever, while `hexciri plugin update` (patched 53b6d68) pulls the
   checked-out branch (nyx), so the update changes nothing and the
   badge never drops. Fix: fetch the checked-out branch (detached HEAD
   falls back to origin HEAD), exactly like hexciri-plugin-update.
2. Slow scan starves the fast poll. main() ran sources sequentially:
   checkupdates sync + yay -Qua + flatpak remote-ls + mise outdated
   (120s timeout) + git fetch per plugin/theme. A full scan is minutes,
   while BarWidget's fast-poll timer ticked every 10s/30s and counted
   each tick even when runCheck() no-opped because a scan was already
   running, so the 30-poll budget could expire before any fresh result
   landed, and no new scan was scheduled until the 1800s timer. Fix:
   run the sources in parallel (ThreadPoolExecutor, output shape
   unchanged) and only count fast-poll ticks where a scan actually
   started.
3. AUR check timeout. yay -Qua had a 60s timeout; on a slow AUR it
   timed out and reported 0 (false "up to date"). Raise to 120s; with
   the parallel scan it no longer blocks the other sources.

Files (in /tmp/arch-updates-nyx, pushed to Deoxizn/Arch-Updates nyx):
  scripts/check_updates.py, scripts/update_plugins_themes.py,
  BarWidget.qml
"""
import sys

BASE = "/tmp/arch-updates-nyx"

# --- check_updates.py ---
p = BASE + "/scripts/check_updates.py"
s = open(p).read()
orig = s

# 1. branch-aware plugin_behind
old = '''def plugin_behind(dir_path):
    """A package entry for a plugin behind origin, else None.

    Mirrors `hexciri-plugin-update`: fetch origin HEAD, then count the
    commits FETCH_HEAD has that HEAD lacks. Offline plugins, and checkouts
    only ahead of origin (local work, a feature branch), are skipped: the
    updater has nothing to pull for them.
    """
    fetch = run_git(["fetch", "--quiet", "origin", "HEAD"], dir_path)
'''
new = '''def checked_out_branch(dir_path):
    """The checked-out branch name, or None when detached/unknown.

    A plugin on nyx must be compared against nyx, not origin HEAD
    (main): main moving ahead would otherwise count a fully up-to-date
    nyx plugin as behind forever, and the updater (which pulls the
    checked-out branch) would never clear it.
    """
    head = run_git(["rev-parse", "--abbrev-ref", "HEAD"], dir_path, timeout=15)
    if head is None or head.returncode != 0:
        return None
    branch = (head.stdout or "").strip()
    if not branch or branch == "HEAD" or not is_safe_git_ref(branch):
        return None
    return branch


def plugin_behind(dir_path):
    """A package entry for a plugin behind its checked-out branch, else None.

    Mirrors `hexciri-plugin-update` (patched 2026-11-24): fetch the
    checked-out branch, then count the commits FETCH_HEAD has that HEAD
    lacks; detached HEAD falls back to origin HEAD. Offline plugins, and
    checkouts only ahead of their branch (local work), are skipped: the
    updater has nothing to pull for them.
    """
    branch = checked_out_branch(dir_path)
    if branch is not None:
        fetch = run_git(["fetch", "--quiet", "origin", branch], dir_path)
    else:
        fetch = run_git(["fetch", "--quiet", "origin", "HEAD"], dir_path)
'''
assert s.count(old) == 1, "plugin_behind anchor not found exactly once"
s = s.replace(old, new, 1)

# 2. AUR timeout 60 -> 120
old = '''    lines = command_lines([helper, "-Qua"], timeout=60, require_ok=False)'''
new = '''    lines = command_lines([helper, "-Qua"], timeout=120, require_ok=False)'''
assert s.count(old) == 1, "check_aur timeout anchor not found"
s = s.replace(old, new, 1)

# 3. parallel scan in main()
old = '''    repo_updates = check_repo()
    aur_updates = [] if args.no_aur else check_aur(helper)
    flatpak_updates = [] if args.no_flatpak else check_flatpak()
    mise_updates = [] if args.no_mise else check_mise(mise)
    checkout = hexciri_checkout_behind()
    if args.no_plugins:
        plugin_updates = []
        theme_updates = []
    else:
        plugin_updates = check_plugins(plugin_dirs)
        theme_updates = check_themes(themes)
'''
new = '''    # Sources are independent subprocesses (repo DB sync, AUR RPC,
    # Flatpak remote, mise, git fetches). Run them in parallel: the
    # sequential scan summed to minutes, and the widget's fast poll
    # (10s ticks, 30-poll budget) could expire before any fresh result
    # landed, leaving the badge stale until the 1800s timer. Output
    # shape is unchanged; each source keeps its own timeout.
    with ThreadPoolExecutor(max_workers=7) as pool:
        f_repo = pool.submit(check_repo)
        f_aur = pool.submit(check_aur, helper) if not args.no_aur else None
        f_flatpak = pool.submit(check_flatpak) if not args.no_flatpak else None
        f_mise = pool.submit(check_mise, mise) if not args.no_mise else None
        f_checkout = pool.submit(hexciri_checkout_behind)
        f_plugins = pool.submit(check_plugins, plugin_dirs) if not args.no_plugins else None
        f_themes = pool.submit(check_themes, themes) if not args.no_plugins else None
        repo_updates = f_repo.result()
        aur_updates = [] if f_aur is None else f_aur.result()
        flatpak_updates = [] if f_flatpak is None else f_flatpak.result()
        mise_updates = [] if f_mise is None else f_mise.result()
        checkout = f_checkout.result()
        plugin_updates = [] if f_plugins is None else f_plugins.result()
        theme_updates = [] if f_themes is None else f_themes.result()
'''
assert s.count(old) == 1, "main() sequential scan anchor not found"
s = s.replace(old, new, 1)
assert s != orig
open(p, "w").write(s)
print("check_updates.py patched")

# --- update_plugins_themes.py ---
p = BASE + "/scripts/update_plugins_themes.py"
s = open(p).read()
orig = s
old = '''def plugin_behind_count(dir_path):
    """Commits dir_path is behind origin HEAD, or None if unknown.

    Mirrors the scanner's plugin_behind and `hexciri-plugin-update`:
    fetch origin HEAD, then count the commits FETCH_HEAD has that HEAD
    lacks. A checkout only ahead of origin (local work, a feature
    branch) counts as 0: the updater has nothing to pull for it.
    """
    fetch = run_git(["fetch", "--quiet", "origin", "HEAD"], dir_path)
'''
new = '''def checked_out_branch(dir_path):
    """The checked-out branch name, or None when detached/unknown."""
    head = run_git(["rev-parse", "--abbrev-ref", "HEAD"], dir_path, timeout=15)
    if head is None or head.returncode != 0:
        return None
    branch = (head.stdout or "").strip()
    if not branch or branch == "HEAD":
        return None
    return branch


def plugin_behind_count(dir_path):
    """Commits dir_path is behind its checked-out branch, or None if unknown.

    Mirrors the scanner's plugin_behind and `hexciri-plugin-update`
    (patched 2026-11-24): fetch the checked-out branch, not origin
    HEAD (main), or a nyx plugin counts as behind main forever while
    the updater pulls nyx and never clears it. A checkout only ahead
    of its branch (local work, a feature branch) counts as 0: the
    updater has nothing to pull for it.
    """
    branch = checked_out_branch(dir_path)
    if branch is not None:
        fetch = run_git(["fetch", "--quiet", "origin", branch], dir_path)
    else:
        fetch = run_git(["fetch", "--quiet", "origin", "HEAD"], dir_path)
'''
assert s.count(old) == 1, "plugin_behind_count anchor not found exactly once"
s = s.replace(old, new, 1)
assert s != orig
open(p, "w").write(s)
print("update_plugins_themes.py patched")

# --- BarWidget.qml: fast poll only counts ticks where a scan started ---
p = BASE + "/BarWidget.qml"
s = open(p).read()
orig = s
old = '''    onTriggered: {
      root.runCheck()
      root.fastPollCount++
      // Back off while the updater terminal stays open: early polls catch
      // a quick update, later ones just keep the numbers from going stale.
      if (root.fastPollCount >= 5) fastPollTimer.interval = 30000
      if (root.fastPollCount >= root.maxFastPolls) root.stopFastPoll()
    }'''
new = '''    onTriggered: {
      // Only count ticks where a scan actually started. runCheck() is a
      // no-op while a scan is already running, and a full scan is minutes
      // (repo sync + AUR RPC + mise + git fetches): counting no-op ticks
      // spent the 30-poll budget before any fresh result landed, and
      // stopFastPoll()'s own runCheck() also no-opped mid-scan, so no
      // new scan was scheduled until the 1800s timer and the badge
      // stayed stale. A tick with a scan in flight costs nothing.
      var started = !checkProc.running
      root.runCheck()
      if (started) root.fastPollCount++
      // Back off while the updater terminal stays open: early polls catch
      // a quick update, later ones just keep the numbers from going stale.
      if (root.fastPollCount >= 5) fastPollTimer.interval = 30000
      if (root.fastPollCount >= root.maxFastPolls) root.stopFastPoll()
    }'''
assert s.count(old) == 1, "fastPollTimer anchor not found exactly once"
s = s.replace(old, new, 1)
assert s != orig
open(p, "w").write(s)
print("BarWidget.qml patched")
print("OK")
