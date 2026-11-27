#!/usr/bin/env bash

# Hexciri fork patch 77: per-monitor screensaver animations.
#
# Symptom (Devi, 2026-11-27 15:04 MST): the Hexciri screensaver mirrors
# the SAME animation on both monitors. On stock Omarchy (the old terminal
# screensaver) each monitor got its own random animation.
#
# Root cause (upstream behavior, NOT a fork regression): omarchy-screensaver
# 1.3.1 (latest tag; main HEAD is the same commit b3026b6) keeps ONE shared
# Animation for all outputs (src/wayland.rs: App.animation). ensure_animation()
# sizes it to the largest output's grid, tick() advances it once, and
# present_dirty() commits the same cells to every layer surface. Each
# Animation picks one random effect (Rng::from_entropy in build_effect), so
# with one instance every monitor shows the same effect. There is no
# per-output option (options.rs has only one global --seed), and one
# process per output is blocked by the single-instance lock
# (launch::acquire_lock + already_running). Patch 73's renames touch
# nothing in this path (namespace, branding path, toggles, lock file, help
# text, fallback art), so the fork faithfully reproduces upstream. Devi's
# memory of per-monitor effects is from the pre-Oct-27 terminal
# screensaver: one terminal per monitor, each its own ttfx process with its
# own entropy seed. The native Wayland rewrite (upstream fdbe182d39)
# consolidated that to one process and one animation.
#
# Fix (fork-side, minimal; the screensaver is NOT rewritten): one Animation
# per OutputSurface. Each is built with its own entropy RNG (independent
# random effect per output) and sized to its own output's grid (which also
# stops the portrait monitor inheriting the landscape monitor's grid).
# Plus a deterministic unit test in engine.rs proving two Animation
# instances pick independently (disjoint --include-effects lists, so the
# assertion is exact, not 1-in-37 luck). The headless path, the
# single-instance lock, and --seed behavior are untouched: --seed still pins
# the same effect on all outputs, which is what deterministic mode means.
#
# Stamp design: patch 73's .hexciri-built stamp ("1.3.1 0.5.1") makes
# re-runs a no-op, so this patch cannot rely on it. It keeps its own stamp
# $SRC_DIR/.hexciri-per-monitor holding the sha256 of the installed binary
# it built. Gate: stamp hash == installed binary hash AND the diff is
# already applied in the source tree -> no-op. If patch 73 ever rebuilds
# the binary (re-extract, version bump, HEXCIRI_SCREENSAVER_REBUILD=1),
# the hash differs and this patch re-applies the diff (if needed) and
# rebuilds. If patch 73 has not built yet (no source dir), this patch
# warns and exits 0; the next update runs 73 first, then this one.
#
# Offline behavior: a cargo fetch failure (no network) warns and skips the
# rebuild this run (exit 0, next update retries). A diff that does not
# apply, a compile/test failure, or a post-install verification failure
# dies loudly: those are real breakage, not offline.
#
# Standalone: bash v2/patches/77-screensaver-per-monitor.sh [FORK_OUT]
#   FORK_OUT is accepted but unused (no menu or install.sh edits).
#   Env overrides (sims/tests): HEXCIRI_SCREENSAVER_SRC_DIR,
#   HEXCIRI_SCREENSAVER_LIB_DIR, HEXCIRI_SCREENSAVER_REBUILD=1 to force a
#   rebuild. Idempotent: re-running with the stamp + the patched binary
#   prints "already current" and changes nothing.
#
# Syntax check note: the end of the patch verifies the installed binary
# (screensaver --help names Hexciri, headless render produces frames) and
# dies if any check fails. bash -n applies to this script itself.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FORK_LOG="${FORK_LOG:-/tmp/hexciri-install-fork.log}"
_patch_log="${_patch_log:-/dev/stdout}"
INSTALL_DETAIL_LOG="${INSTALL_DETAIL_LOG:-/tmp/hexciri-install.log}"
step() { printf '\n==> %s\n' "$1"; }
info() {
  if [ "${IS_RERUN:-0}" = "1" ]; then
    case "$1" in
      Kept*|*already\ present*|*already\ correct*|*already\ current*|Theme\ already\ applied:*|*already\ enabled*)
        printf '[hexciri] %s\n' "$1" >> "$INSTALL_DETAIL_LOG" 2>/dev/null || true
        return 0
        ;;
    esac
  fi
  printf '[hexciri] %s\n' "$1"
}
warn() { printf 'WARN: %s\n' "$1"; }
die() { printf 'ERROR: %s\n' "77-screensaver-per-monitor.sh: $1" >&2; exit 1; }
CHANGED=0

SS_VER="1.3.1"
SRC_DIR="${HEXCIRI_SCREENSAVER_SRC_DIR:-${HOME:?HOME is not set, cannot build the screensaver}/.cache/hexciri/screensaver-src}"
LIB_DIR="${HEXCIRI_SCREENSAVER_LIB_DIR:-/usr/lib/hexciri-screensaver}"
SS_BIN="$LIB_DIR/hexciri-screensaver"
SS_SRC="$SRC_DIR/omarchy-screensaver-$SS_VER"
PM_STAMP="$SRC_DIR/.hexciri-per-monitor"
PM_DIFF="$SRC_DIR/.hexciri-per-monitor.diff"

step "Fixing the Hexciri screensaver so each monitor gets its own animation (patch 77)"

# --- 0. Nothing to patch yet: patch 73 has not built. ---
if [ ! -f "$SS_SRC/src/wayland.rs" ] || [ ! -f "$SS_SRC/src/engine.rs" ]; then
  warn "screensaver source not present (patch 73 has not built yet), skipping the per-monitor fix this run"
  printf 'screensaver per-monitor: %d edits applied (no source yet)\n' "$CHANGED" >>"$_patch_log"
  info "  patch 77: no screensaver source yet, per-monitor fix skipped"
  exit 0
fi

# --- 1. patch(1) must exist to apply the source diff. ---
if ! command -v patch >/dev/null 2>&1; then
  info "  patch 77: patch(1) missing, installing it"
  if sudo pacman -S --needed --noconfirm patch >/tmp/hexciri-per-monitor-pacman.log 2>&1; then
    command -v patch >/dev/null 2>&1 || die "pacman installed patch but it is still missing"
  else
    warn "could not install patch(1) (no network or no pacman), skipping the per-monitor fix this run"
    exit 0
  fi
fi

# --- 2. Write the embedded source diff (same bytes every run). ---
cat > "$PM_DIFF" <<'HEXCIRI_PER_MONITOR_DIFF'
--- a/src/wayland.rs
+++ b/src/wayland.rs
@@ -72,6 +72,7 @@
     configured: bool,
     dirty: bool,
     frame_ready: bool,
+    animation: Option<Animation>,
     buffer: Option<Buffer>,
     buffer_size: (i32, i32),
     rendered_cells: Vec<Cell>,
@@ -98,7 +99,6 @@
     pointer: Option<wl_pointer::WlPointer>,
     last_pointer: Option<(f64, f64)>,
     rasterizer: Rasterizer,
-    animation: Option<Animation>,
     input: String,
     options: Options,
     next_engine_tick: Instant,
@@ -145,7 +145,6 @@
         pointer: None,
         last_pointer: None,
         rasterizer: Rasterizer::load()?,
-        animation: None,
         input,
         options,
         next_engine_tick: now,
@@ -199,6 +198,7 @@
             configured: false,
             dirty: true,
             frame_ready: true,
+            animation: None,
             buffer: None,
             buffer_size: (0, 0),
             rendered_cells: Vec::new(),
@@ -223,7 +223,7 @@
             self.request_dismiss();
             return;
         }
-        if let Err(error) = self.ensure_animation() {
+        if let Err(error) = self.ensure_animations() {
             self.failure = Some(error);
             self.exit = true;
             return;
@@ -231,12 +231,14 @@
         let frame_duration = Duration::from_secs_f64(1.0 / FRAME_RATE as f64);
         let mut catchup = 0;
         while now >= self.next_engine_tick && catchup < 8 {
-            if let Some(animation) = &mut self.animation
-                && let Err(error) = animation.advance_deferred()
-            {
-                self.failure = Some(error);
-                self.exit = true;
-                return;
+            for surface in &mut self.surfaces {
+                if let Some(animation) = &mut surface.animation
+                    && let Err(error) = animation.advance_deferred()
+                {
+                    self.failure = Some(error);
+                    self.exit = true;
+                    return;
+                }
             }
             self.next_engine_tick += frame_duration;
             catchup += 1;
@@ -249,65 +251,62 @@
                 .surfaces
                 .iter()
                 .any(|surface| surface.configured && surface.frame_ready);
-        let changed = if presentation_ready {
-            match self
-                .animation
-                .as_mut()
-                .expect("animation exists")
-                .rasterize_pending()
-            {
-                Ok(changed) => changed,
-                Err(error) => {
-                    self.failure = Some(error);
-                    self.exit = true;
-                    return;
+        if presentation_ready {
+            let mut failure: Option<anyhow::Error> = None;
+            for surface in &mut self.surfaces {
+                let Some(animation) = &mut surface.animation else {
+                    continue;
+                };
+                match animation.rasterize_pending() {
+                    Ok(changed) => {
+                        if changed {
+                            surface.dirty = true;
+                        }
+                    }
+                    Err(error) => {
+                        failure = Some(error);
+                        break;
+                    }
                 }
             }
-        } else {
-            false
-        };
-        if changed {
-            for surface in &mut self.surfaces {
-                surface.dirty = true;
+            if let Some(error) = failure {
+                self.failure = Some(error);
+                self.exit = true;
+                return;
             }
         }
         self.present_dirty(qh, false);
     }
 
-    fn ensure_animation(&mut self) -> Result<()> {
-        let Some((cols, rows)) = self
-            .surfaces
-            .iter()
-            .filter(|surface| surface.configured)
-            .map(|surface| {
-                let (width, height) = (
-                    surface.width * surface.scale,
-                    surface.height * surface.scale,
-                );
-                self.rasterizer.grid_size(width, height, surface.scale)
-            })
-            .max_by_key(|(cols, rows)| i64::from(*cols) * i64::from(*rows))
-        else {
-            return Ok(());
-        };
-        let cols = if self.options.cols > 0 {
-            self.options.cols
-        } else {
-            cols
-        };
-        let rows = if self.options.rows > 0 {
-            self.options.rows
-        } else {
-            rows
-        };
-        match &mut self.animation {
-            Some(animation) => animation.resize(cols, rows)?,
-            None => {
-                let mut animation =
-                    Animation::new(self.input.clone(), self.options.clone(), cols, rows)?;
-                // The overlay is opaque from its first commit, so that commit needs the first frame on it.
-                animation.advance()?;
-                self.animation = Some(animation);
+    // One animation per output: each picks its own random effect (and
+    // its own grid), so two monitors never mirror each other. Upstream
+    // keeps a single shared animation sized to the largest output,
+    // which is exactly the mirroring this fork fixes.
+    fn ensure_animations(&mut self) -> Result<()> {
+        for surface in &mut self.surfaces {
+            if !surface.configured {
+                continue;
+            }
+            let (width, height) = (
+                surface.width * surface.scale,
+                surface.height * surface.scale,
+            );
+            let (mut cols, mut rows) = self.rasterizer.grid_size(width, height, surface.scale);
+            if self.options.cols > 0 {
+                cols = self.options.cols;
+            }
+            if self.options.rows > 0 {
+                rows = self.options.rows;
+            }
+            match &mut surface.animation {
+                Some(animation) => animation.resize(cols, rows)?,
+                None => {
+                    let mut animation =
+                        Animation::new(self.input.clone(), self.options.clone(), cols, rows)?;
+                    // The overlay is opaque from its first commit, so that commit needs the first frame on it.
+                    animation.advance()?;
+                    surface.animation = Some(animation);
+                }
             }
         }
         Ok(())
@@ -318,16 +317,19 @@
         if !force && now < self.next_present {
             return;
         }
-        let Some(animation) = &self.animation else {
-            return;
-        };
-        let (cells, cols, rows) = (animation.cells(), animation.cols(), animation.rows());
         let mut committed = false;
         for surface in &mut self.surfaces {
             if !surface.configured || !surface.dirty || !surface.frame_ready {
                 continue;
             }
-            match present_surface(
+            // Take the animation out while presenting: its cells are
+            // borrowed for the rasterizer while the surface itself is
+            // borrowed mutably by present_surface.
+            let Some(mut animation) = surface.animation.take() else {
+                continue;
+            };
+            let (cells, cols, rows) = (animation.cells(), animation.cols(), animation.rows());
+            let presented = present_surface(
                 &self.compositor,
                 &mut self.pool,
                 &mut self.rasterizer,
@@ -336,7 +338,9 @@
                 cells,
                 cols,
                 rows,
-            ) {
+            );
+            surface.animation = Some(animation);
+            match presented {
                 Ok(did_commit) => committed |= did_commit,
                 Err(error) => {
                     self.failure = Some(error);
@@ -504,7 +508,7 @@
             output.rendered_cells.clear();
             output.dirty = true;
         }
-        if let Err(error) = self.ensure_animation() {
+        if let Err(error) = self.ensure_animations() {
             self.failure = Some(error);
             self.exit = true;
         } else {
@@ -604,7 +608,7 @@
         surface.configured = true;
         surface.dirty = true;
         surface.frame_ready = true;
-        if let Err(error) = self.ensure_animation() {
+        if let Err(error) = self.ensure_animations() {
             self.failure = Some(error);
             self.exit = true;
         } else {
--- a/src/engine.rs
+++ b/src/engine.rs
@@ -222,3 +222,40 @@
         ..TerminalConfig::default()
     }
 }
+
+#[cfg(test)]
+mod tests {
+    use super::*;
+
+    #[test]
+    fn two_animations_pick_independently() {
+        // Two Animation instances built with disjoint --include-effects
+        // lists must resolve to different effects: effect selection is
+        // per-instance state, not global. This is the mechanism the
+        // per-output animations rely on (one Animation per surface,
+        // each with its own entropy RNG). Disjoint include lists make
+        // the assertion deterministic instead of 1-in-37 luck.
+        let input = "HEXCIRI".to_owned();
+        let matrix = Animation::new(
+            input.clone(),
+            Options {
+                include_effects: vec!["matrix".to_owned()],
+                ..Options::default()
+            },
+            40,
+            12,
+        )
+        .expect("matrix animation builds");
+        let beams = Animation::new(
+            input,
+            Options {
+                include_effects: vec!["beams".to_owned()],
+                ..Options::default()
+            },
+            40,
+            12,
+        )
+        .expect("beams animation builds");
+        assert_ne!(matrix.effect_name(), beams.effect_name());
+    }
+}
HEXCIRI_PER_MONITOR_DIFF

# --- 3. Gate: diff already applied AND installed binary matches the stamp.
# The diff is detected by its markers, not by a reverse dry-run: with
# --batch, patch answers its own "Ignore -R?" prompt by applying forward,
# so a reverse dry-run "succeeds" on pristine files too (caught in sim).
DIFF_APPLIED=0
if grep -q "fn ensure_animations" "$SS_SRC/src/wayland.rs" 2>/dev/null \
  && grep -q "two_animations_pick_independently" "$SS_SRC/src/engine.rs" 2>/dev/null; then
  DIFF_APPLIED=1
fi
NEED_BUILD=1
if [ "${HEXCIRI_SCREENSAVER_REBUILD:-0}" != "1" ] \
  && [ "$DIFF_APPLIED" = "1" ] \
  && [ -f "$PM_STAMP" ] && [ -x "$SS_BIN" ] \
  && [ "$(cat "$PM_STAMP" 2>/dev/null)" = "$(sha256sum "$SS_BIN" | cut -d' ' -f1)" ]; then
  NEED_BUILD=0
  printf 'screensaver per-monitor: already current, skipping build\n' >>"$_patch_log"
  info "  patch 77: per-monitor screensaver already current, build skipped"
fi

if [ "$NEED_BUILD" = "1" ]; then
  # --- 4. Apply the diff if needed (--forward skips hunks that are
  # already applied, so a partial earlier apply heals instead of dying).
  if [ "$DIFF_APPLIED" = "0" ]; then
    if (cd "$SS_SRC" && patch -p1 --forward --dry-run --batch --silent < "$PM_DIFF" 2>/tmp/hexciri-per-monitor-patch.log); then
      (cd "$SS_SRC" && patch -p1 --forward --batch --silent < "$PM_DIFF") >>/tmp/hexciri-per-monitor-patch.log 2>&1 \
        || die "per-monitor diff failed to apply (see /tmp/hexciri-per-monitor-patch.log)"
      grep -q "fn ensure_animations" "$SS_SRC/src/wayland.rs" \
        && grep -q "two_animations_pick_independently" "$SS_SRC/src/engine.rs" \
        || die "per-monitor diff applied but the markers are missing (partial apply?)"
      info "  patch 77: per-monitor diff applied to $SS_SRC/src/wayland.rs + src/engine.rs"
    else
      tail -20 /tmp/hexciri-per-monitor-patch.log >&2
      die "per-monitor diff does not apply (anchor mismatch -- upstream moved the code)"
    fi
  else
    info "  patch 77: per-monitor diff already applied, rebuilding only"
  fi

  # --- 5. Rebuild the screensaver binary only (ttfx is untouched). ---
  if ! command -v cargo >/dev/null 2>&1; then
    warn "cargo missing (patch 73 installs it when it builds), skipping the per-monitor rebuild this run"
    printf 'screensaver per-monitor: %d edits applied (no cargo)\n' "$CHANGED" >>"$_patch_log"
    exit 0
  fi
  # Fetch first: a fetch failure is offline (transient), not breakage.
  if ! (cd "$SS_SRC" && cargo fetch --locked --target "$(uname -m)-unknown-linux-gnu" > /tmp/hexciri-per-monitor-fetch.log 2>&1); then
    warn "could not fetch the screensaver build deps (no network), skipping the per-monitor rebuild this run"
    exit 0
  fi
  info "  patch 77: rebuilding screensaver $SS_VER with per-monitor animations"
  (cd "$SS_SRC" && CARGO_TARGET_DIR="$SRC_DIR/target-ss" cargo build --frozen --release) \
    > /tmp/hexciri-screensaver-build.log 2>&1 \
    || { tail -20 /tmp/hexciri-screensaver-build.log >&2; die "screensaver rebuild failed (see /tmp/hexciri-screensaver-build.log)"; }
  (cd "$SS_SRC" && CARGO_TARGET_DIR="$SRC_DIR/target-ss" cargo test --frozen) \
    > /tmp/hexciri-screensaver-test.log 2>&1 \
    || { tail -20 /tmp/hexciri-screensaver-test.log >&2; die "screensaver test suite failed (see /tmp/hexciri-screensaver-test.log)"; }

  SS_BUILD="$SRC_DIR/target-ss/release/omarchy-launch-screensaver"
  [ -x "$SS_BUILD" ] || die "screensaver rebuild produced no binary at $SS_BUILD"
  sudo install -Dm755 "$SS_BUILD" "$SS_BIN" || die "could not install $SS_BIN"

  # Post-install verification (same checks as patch 73).
  "$SS_BIN" --help 2>&1 | grep -q "Hexciri screensaver" \
    || die "installed screensaver --help does not name Hexciri"
  "$SS_BIN" --headless --frames 5 --effect print --cols 40 --rows 12 --seed 1 2>/dev/null \
    | grep -q "frames=5" \
    || die "installed screensaver headless render produced no frames"
  sha256sum "$SS_BIN" | cut -d' ' -f1 > "$PM_STAMP"
  printf 'screensaver per-monitor: rebuilt + installed %s\n' "$SS_BIN" >>"$_patch_log"
  info "  patch 77: screensaver rebuilt with per-monitor animations ($SS_BIN)"
  CHANGED=1
fi

printf 'screensaver per-monitor patch: %d edits applied\n' "$CHANGED" >>"$_patch_log"
info "  patch 77: per-monitor screensaver animations installed (each monitor gets its own random effect)"
