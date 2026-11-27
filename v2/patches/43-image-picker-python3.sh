#!/usr/bin/env bash
# Hexciri fork patch 43: image-picker list.sh python3 rewrite + emoji grid
# filtering.
# Forward-port of omarchy PR #19971 (commit 317a7e2f6, "image-picker list.sh
# python3 rewrite + emoji grid filtering").
#
# What it does (PR behavior, unchanged):
#  - shell/plugins/image-picker/list.sh: signatures, index.tsv lookups and
#    thumbnail hashes resolve in one python3 pass instead of forking
#    stat/awk/md5sum per file; legacy content-hash thumbnails are only
#    computed when the cache dir actually holds unmatched .jpg files;
#    index.tsv paths containing backslashes match again (the old awk
#    lookup mangled them). Video thumbnail generation and draining are
#    untouched.
#  - shell/plugins/emojis/Emojis.qml: the grid binds straight to
#    filteredEmojis instead of copying rows into a ListModel on every
#    keystroke (columns floors at 1, so a narrow card cannot divide by
#    zero); selection math reads the array length.
#
# Fork notes: no renames in the ported code except the fork's existing
# cache path: list.sh already reads
# ${XDG_CACHE_HOME:-$HOME/.cache}/hexciri/image-selector in the fork,
# and the new python block takes it as an argument, so no path literal
# changes. The `# omarchy:` metadata prefix rule does not apply here
# (neither file carries router metadata). Upstream test files are NOT
# in FORK_OUT (test/ is not one of the copied subsets), so no test
# file is edited; the upstream video-background-test additions are
# covered here by the sim functional checks instead (see README).
#
# Standalone: bash v2/patches/43-image-picker-python3.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: list.sh is bash (bash -n applies); the embedded
# python block is syntax-checked by extracting it and running
# python3 -m py_compile on it. Emojis.qml is QML: qmllint when present,
# warning only (it fails on missing Quickshell imports even for valid
# files). bash -n does not apply to the QML file.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "43-image-picker-python3.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
HEXCIRI_PATH="${HEXCIRI_PATH:-/usr/share/hexciri}"
_PATCHES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEXCIRI_REPO_ROOT="${HEXCIRI_REPO_ROOT:-$(cd "$_PATCHES_DIR/../.." && pwd)}"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$_PATCHES_DIR/.." && pwd)}"
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
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
fork_detail() {
  : >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  printf '[hexciri] %s\n' "$1" >> "${FORK_LOG:-/tmp/hexciri-install-fork.log}" 2>/dev/null || true
  if [[ "${HEXCIRI_INSTALL_VERBOSE:-0}" == "1" || "${HEXCIRI_UPDATE_VERBOSE:-0}" == "1" ]]; then
    printf '[hexciri] %s\n' "$1"
  fi
}

# --- Image-picker python3 rewrite + emoji grid, omarchy PR #19971 ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# The new list.sh main flow (python3 block), verbatim from the PR. It is
# kept as one string so the replacement below stays a single anchor.
NEW_FLOW = r"""# Resolve signatures, index lookups, and thumbnail hashes in one pass instead
# of forking stat/awk/md5sum per file, and only compute legacy content hashes
# when cache_dir actually holds unmatched .jpg thumbnails.
{
  while IFS= read -r dir; do
    [[ -n $dir && -d $dir ]] || continue
    find -L "$dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \
         -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \) \
      -print0 2>/dev/null
  done <<<"$image_dirs" | sort -z
} | python3 -c '
import hashlib
import os
import sys

cache_dir, index_file, pending_path, resolved_path = sys.argv[1:5]
VIDEO_EXTS = (".mp4", ".m4v", ".mov", ".webm", ".mkv", ".avi")

indexed = {}

try:
  with open(index_file, "r", encoding="utf-8", errors="surrogateescape") as f:
    for line in f:
      parts = line.rstrip("\n").split("\t")
      if len(parts) >= 3 and parts[2]:
        indexed.setdefault((parts[0], parts[1]), parts[2])
except OSError:
  pass

cached_jpgs = set()
failed_markers = set()

try:
  with os.scandir(cache_dir) as it:
    for entry in it:
      if not entry.is_file():
        continue
      name = entry.name
      if name.endswith(".jpg"):
        cached_jpgs.add(name)
      elif name.endswith(".jpg.failed"):
        failed_markers.add(name)
except OSError:
  pass

raw_paths = sys.stdin.buffer.read().split(b"\0")
entries = []
matched_jpgs = set()

for raw in raw_paths:
  if not raw:
    continue
  image = os.fsdecode(raw)
  try:
    st = os.stat(image)
  except OSError:
    continue
  sig = f"{st.st_size}:{int(st.st_mtime)}"
  h = indexed.get((image, sig))
  if not h:
    h = hashlib.md5(f"{image}\t{sig}".encode("utf-8", "surrogateescape")).hexdigest()
  jpg_name = f"{h}.jpg"
  if jpg_name in cached_jpgs:
    matched_jpgs.add(jpg_name)
  is_video = image.lower().endswith(VIDEO_EXTS)
  entries.append((image, is_video, os.path.join(cache_dir, jpg_name), jpg_name))

has_legacy_candidates = bool(cached_jpgs - matched_jpgs)
pending = []
resolved = []

for image, is_video, thumbnail, jpg_name in entries:
  if is_video:
    if jpg_name in cached_jpgs:
      resolved.append((image, True, thumbnail))
    elif f"{jpg_name}.failed" not in failed_markers:
      pending.append((image, thumbnail))
      resolved.append((image, True, thumbnail))
  else:
    if jpg_name in cached_jpgs:
      resolved.append((image, False, thumbnail))
    else:
      chosen = image
      if has_legacy_candidates:
        try:
          with open(image, "rb") as f:
            legacy_name = hashlib.file_digest(f, "md5").hexdigest() + ".jpg"
          if legacy_name in cached_jpgs:
            chosen = os.path.join(cache_dir, legacy_name)
        except OSError:
          pass
      resolved.append((image, False, chosen))

if pending:
  with open(pending_path, "wb") as pf:
    for image, thumbnail in pending:
      pf.write(os.fsencode(image) + b"\0" + os.fsencode(thumbnail) + b"\0")
  with open(resolved_path, "wb") as rf:
    for image, is_video, thumbnail in resolved:
      rf.write(
        os.fsencode(image) + b"\0"
        + (b"1" if is_video else b"0") + b"\0"
        + os.fsencode(thumbnail) + b"\0"
      )
else:
  out = sys.stdout.buffer
  for image, _, thumbnail in resolved:
    out.write(os.fsencode(image) + b"\t" + os.fsencode(thumbnail) + b"\n")
' "$cache_dir" "$index_file" "$pending_video_file" "$resolved_file"

if [[ -s $pending_video_file ]]; then
  drain_pending_video_thumbnails
  while IFS= read -r -d '' image && IFS= read -r -d '' is_video && IFS= read -r -d '' thumbnail; do
    if [[ $is_video == "0" || -f $thumbnail ]]; then
      printf '%s\t%s\n' "$image" "$thumbnail"
    fi
  done <"$resolved_file"
fi"""

# (file, old, new, label, done_marker). done_marker defaults to new.
REPLACEMENTS = [
    # list.sh header: track the resolved list alongside pending videos.
    ("shell/plugins/image-picker/list.sh",
     "pending_video_file=$(mktemp)\n"
     "\n"
     "mkdir -p \"$cache_dir\"\n"
     "trap 'rm -f \"$pending_video_file\"' EXIT",
     "pending_video_file=$(mktemp)\n"
     "\n"
     "resolved_file=$(mktemp)\n"
     "\n"
     "mkdir -p \"$cache_dir\"\n"
     "trap 'rm -f \"$pending_video_file\" \"$resolved_file\"' EXIT",
     "list.sh: track resolved_file next to pending_video_file",
     None),
    # list.sh: the per-file stat/awk/md5sum helpers go away; the python
    # block below does signatures, index lookups and hashing in one pass.
    ("shell/plugins/image-picker/list.sh",
     "is_video_path() {\n"
     "  [[ ${1,,} =~ \\.(mp4|m4v|mov|webm|mkv|avi)$ ]]\n"
     "}\n"
     "\n"
     "thumbnail_path_for() {\n"
     "  local image=\"$1\"\n"
     "  local signature hash\n"
     "\n"
     "  signature=$(stat -Lc '%s:%Y' \"$image\") || return\n"
     "  hash=$(awk -F '\\t' -v path=\"$image\" -v sig=\"$signature\" '$1 == path && $2 == sig { print $3; exit }' \"$index_file\" 2>/dev/null)\n"
     "\n"
     "  if [[ -z $hash ]]; then\n"
     "    hash=$(printf '%s\\t%s' \"$image\" \"$signature\" | md5sum | cut -d ' ' -f 1)\n"
     "  fi\n"
     "\n"
     "  printf '%s/%s.jpg' \"$cache_dir\" \"$hash\"\n"
     "}\n"
     "\n",
     "",
     "list.sh: drop is_video_path + thumbnail_path_for (python does it)",
     "} | python3 -c '"),
    # list.sh: thumbnail_for goes away with them.
    ("shell/plugins/image-picker/list.sh",
     "thumbnail_for() {\n"
     "  local image=\"$1\"\n"
     "  local thumbnail legacy_hash\n"
     "\n"
     "  thumbnail=$(thumbnail_path_for \"$image\") || return\n"
     "\n"
     "  if [[ ! -f $thumbnail ]] && ! is_video_path \"$image\"; then\n"
     "    # Older on-demand picker code keyed fallback thumbnails by file content.\n"
     "    # Keep finding those if a user still has them cached.\n"
     "    legacy_hash=$(md5sum \"$image\" 2>/dev/null | cut -d ' ' -f 1)\n"
     "    [[ -n $legacy_hash && -f $cache_dir/$legacy_hash.jpg ]] && thumbnail=\"$cache_dir/$legacy_hash.jpg\"\n"
     "  fi\n"
     "\n"
     "  if [[ -f $thumbnail ]]; then\n"
     "    printf '%s' \"$thumbnail\"\n"
     "  elif ! is_video_path \"$image\"; then\n"
     "    printf '%s' \"$image\"\n"
     "  fi\n"
     "}\n"
     "\n",
     "",
     "list.sh: drop thumbnail_for (python does it)",
     "} | python3 -c '"),
    # list.sh main flow: mapfile + two bash loops become the python pass.
    ("shell/plugins/image-picker/list.sh",
     "mapfile -d '' -t images < <(\n"
     "  while IFS= read -r dir; do\n"
     "    [[ -n $dir && -d $dir ]] || continue\n"
     "    find -L \"$dir\" -maxdepth 1 -type f \\\n"
     "      \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \\\n"
     "         -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \\) \\\n"
     "      -print0 2>/dev/null\n"
     "  done <<<\"$image_dirs\" | sort -z\n"
     ")\n"
     "\n"
     "for image in \"${images[@]}\"; do\n"
     "  if is_video_path \"$image\"; then\n"
     "    thumbnail=$(thumbnail_path_for \"$image\") || continue\n"
     "    [[ -f $thumbnail || -f $thumbnail.failed ]] || printf '%s\\0%s\\0' \"$image\" \"$thumbnail\" >>\"$pending_video_file\"\n"
     "  fi\n"
     "done\n"
     "\n"
     "drain_pending_video_thumbnails\n"
     "\n"
     "for image in \"${images[@]}\"; do\n"
     "  thumbnail=$(thumbnail_for \"$image\")\n"
     "  [[ -n $thumbnail ]] || continue\n"
     "  printf '%s\\t%s\\n' \"$image\" \"$thumbnail\"\n"
     "done",
     NEW_FLOW,
     "list.sh: main flow becomes the one-pass python3 resolver",
     None),
    # --- Emojis.qml: bind the grid to filteredEmojis, drop displayModel ---
    ("shell/plugins/emojis/Emojis.qml",
     "  property int columns: Math.floor((cardWidth - contentMargin * 2) / cellWidth)",
     "  property int columns: Math.max(1, Math.floor((cardWidth - contentMargin * 2) / cellWidth))",
     "Emojis.qml: columns floors at 1 (narrow card cannot divide by zero)",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "    displayModel.clear()\n"
     "    for (var j = 0; j < out.length; j++) {\n"
     "      displayModel.append({ emoji: out[j].e, index: j })\n"
     "    }\n"
     "\n"
     "    if (displayModel.count === 0) selectedIndex = 0\n"
     "    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1\n"
     "    else if (selectedIndex < 0) selectedIndex = 0\n"
     "    cursorActive = displayModel.count > 0\n"
     "\n"
     "    Qt.callLater(function() {\n"
     "      if (displayModel.count > 0) resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)\n"
     "    })",
     "    if (out.length === 0) selectedIndex = 0\n"
     "    else if (selectedIndex >= out.length) selectedIndex = out.length - 1\n"
     "    else if (selectedIndex < 0) selectedIndex = 0\n"
     "    cursorActive = out.length > 0\n"
     "\n"
     "    Qt.callLater(function() {\n"
     "      if (root.filteredEmojis.length > 0) resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)\n"
     "    })",
     "Emojis.qml: rebuildDisplay stops copying rows into displayModel",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "  function select(delta) {\n"
     "    if (displayModel.count === 0) return\n"
     "    if (!cursorActive) {\n"
     "      cursorActive = true\n"
     "      selectedIndex = delta < 0 ? displayModel.count - 1 : 0\n"
     "    } else {\n"
     "      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count\n"
     "    }\n"
     "    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "  }",
     "  function select(delta) {\n"
     "    var count = root.filteredEmojis.length\n"
     "    if (count === 0) return\n"
     "    if (!cursorActive) {\n"
     "      cursorActive = true\n"
     "      selectedIndex = delta < 0 ? count - 1 : 0\n"
     "    } else {\n"
     "      selectedIndex = (selectedIndex + delta + count) % count\n"
     "    }\n"
     "    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "  }",
     "Emojis.qml: select reads filteredEmojis length",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "  function selectRow(delta) {\n"
     "    if (displayModel.count === 0) return\n"
     "    if (!cursorActive) {\n"
     "      cursorActive = true\n"
     "      selectedIndex = delta < 0 ? displayModel.count - 1 : 0\n"
     "      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "      return\n"
     "    }\n"
     "    var newIndex = selectedIndex + delta * columns\n"
     "    if (newIndex < 0) newIndex = 0\n"
     "    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1\n"
     "    selectedIndex = newIndex\n"
     "    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "  }",
     "  function selectRow(delta) {\n"
     "    var count = root.filteredEmojis.length\n"
     "    if (count === 0) return\n"
     "    if (!cursorActive) {\n"
     "      cursorActive = true\n"
     "      selectedIndex = delta < 0 ? count - 1 : 0\n"
     "      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "      return\n"
     "    }\n"
     "    var newIndex = selectedIndex + delta * columns\n"
     "    if (newIndex < 0) newIndex = 0\n"
     "    if (newIndex >= count) newIndex = count - 1\n"
     "    selectedIndex = newIndex\n"
     "    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "  }",
     "Emojis.qml: selectRow reads filteredEmojis length",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "  function selectPage(delta) {\n"
     "    if (displayModel.count === 0) return\n"
     "    if (!cursorActive) {\n"
     "      cursorActive = true\n"
     "      selectedIndex = delta < 0 ? displayModel.count - 1 : 0\n"
     "      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "      return\n"
     "    }\n"
     "    var visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight))\n"
     "    var newIndex = selectedIndex + delta * columns * visibleRows\n"
     "    if (newIndex < 0) newIndex = 0\n"
     "    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1\n"
     "    selectedIndex = newIndex\n"
     "    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "  }",
     "  function selectPage(delta) {\n"
     "    var count = root.filteredEmojis.length\n"
     "    if (count === 0) return\n"
     "    if (!cursorActive) {\n"
     "      cursorActive = true\n"
     "      selectedIndex = delta < 0 ? count - 1 : 0\n"
     "      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "      return\n"
     "    }\n"
     "    var visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight))\n"
     "    var newIndex = selectedIndex + delta * columns * visibleRows\n"
     "    if (newIndex < 0) newIndex = 0\n"
     "    if (newIndex >= count) newIndex = count - 1\n"
     "    selectedIndex = newIndex\n"
     "    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)\n"
     "  }",
     "Emojis.qml: selectPage reads filteredEmojis length",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "  function activateIndex(index) {\n"
     "    if (index < 0 || index >= displayModel.count) return\n"
     "    var row = displayModel.get(index)\n"
     "    root.applySelected(row.emoji)\n"
     "  }",
     "  function activateIndex(index) {\n"
     "    if (index < 0 || index >= root.filteredEmojis.length) return\n"
     "    root.applySelected(root.filteredEmojis[index].e)\n"
     "  }",
     "Emojis.qml: activateIndex reads filteredEmojis directly",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "  ListModel { id: displayModel }\n"
     "\n",
     "",
     "Emojis.qml: drop the displayModel ListModel",
     "model: root.filteredEmojis"),
    ("shell/plugins/emojis/Emojis.qml",
     "            else if (displayModel.count > 0) root.cursorActive = true",
     "            else if (root.filteredEmojis.length > 0) root.cursorActive = true",
     "Emojis.qml: Return key guard reads filteredEmojis length",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "            model: displayModel",
     "            model: root.filteredEmojis",
     "Emojis.qml: GridView model is filteredEmojis",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "              required property string emoji",
     "              required property var modelData",
     "Emojis.qml: grid delegate takes modelData",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "                text: parent.emoji",
     "                text: parent.modelData.e",
     "Emojis.qml: grid delegate renders modelData.e",
     None),
    ("shell/plugins/emojis/Emojis.qml",
     "            visible: displayModel.count === 0",
     "            visible: root.filteredEmojis.length === 0",
     "Emojis.qml: empty state reads filteredEmojis length",
     None),
]

for rel, old, new, label, *rest in REPLACEMENTS:
    done_marker = rest[0] if rest else None
    if done_marker is None:
        done_marker = new
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if done_marker and done_marker in s:
        print("%s: already present, skipping" % label)
        continue
    if s.count(old) != 1:
        print("ERROR: anchor not found exactly once in %s (count %d): %s" % (rel, s.count(old), label), file=sys.stderr)
        sys.exit(1)
    s = s.replace(old, new, 1)
    with open(fp, "w") as f:
        f.write(s)
    changed.append(label)

for label in changed:
    print("patched: %s" % label)
print("image-picker-python3 patch: %d file edits applied" % len(changed))
PY

# Syntax checks: list.sh is bash; the embedded python block compiles;
# Emojis.qml is QML (qmllint warning-only when present).
if [ -f "$FORK_OUT/shell/plugins/image-picker/list.sh" ]; then
  bash -n "$FORK_OUT/shell/plugins/image-picker/list.sh" || die "bash -n failed on patched list.sh"
  python3 - "$FORK_OUT/shell/plugins/image-picker/list.sh" <<'PYEOF' || die "embedded python block in list.sh does not compile"
import re
import sys
src = open(sys.argv[1]).read()
m = re.search(r"python3 -c '(.*?)' \"\$cache_dir\"", src, re.S)
if not m:
    print("embedded python block not found", file=sys.stderr)
    sys.exit(1)
compile(m.group(1), "list.sh python block", "exec")
PYEOF
fi
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/emojis/Emojis.qml" || warn "qmllint reported issues on patched Emojis.qml (missing Quickshell imports also trip it; see output above)"
else
  warn "qmllint not found, skipping Emojis.qml parse check"
fi
info "  image-picker-python3: list.sh resolves in one python3 pass, emoji grid binds to filteredEmojis (PR #19971)"
