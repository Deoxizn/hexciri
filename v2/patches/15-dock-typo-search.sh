#!/bin/bash
# Hexciri fork patch 15: typo-tolerant search in the dock AppGrid (Super+Space).
# Forward-port of omarchy PR #19938 (commit e5ad7ac392f3ddab102e24fb5c5afc1a7156953e,
# "feat(menu): add typo-tolerant search") into shell/services/AppSearch.js.
#
# Why the AppGrid and not the menu: patch 14 put the same second pass in the
# fork's shell menu (Super+Alt+Space) and it works there. Devi uses the dock
# launcher (Super+Space, hexciri-shell hexciri.dock apps) more than the menu,
# and it had no typo forgiveness at all: "batttle" showed "No apps match".
#
# Where the filtering lives: AppGrid.qml does NOT filter. Its rebuild() calls
# root.appLibrary.sortedEntries(root.filterText), and the shared AppLibrary
# (shell/services/AppLibrary.qml) forwards to AppSearch.sortedEntries in
# shell/services/AppSearch.js. That is the single insertion point: the menu's
# app rows call sortedEntries("") (no filter) and filter in MenuModel, so a
# change to sortedEntries' query path must not change the menu's behavior.
# AppLibrary.qml, PluginAppLibraryApi.qml, AppGrid.qml and Menu.qml are all
# untouched by this patch. The only in-tree caller with a real query is the
# AppGrid; the plugin facade forwards sortedEntries but no in-tree caller
# uses it with a query, and exact-query behavior is byte-identical anyway.
#
# What it does (PR behavior, unchanged): exact search runs first, untouched.
# Only when it finds 0 rows does sortedEntries run a second pass forgiving
# typos in entry words: NFD diacritic/Hangul-Jamo folding, a doubled-letter
# fast path ("ffiles" finds Files, "batttle" finds Battle.net), and
# Damerau-Levenshtein prefix matching (1 edit from 4+ codepoints, 2 from
# 8+, swapped pair counts as one; skipped for CJK terms). Exact matches
# never show typo rows. Typo rows score in a band below every exact row
# (3000 - tier; exact scores bottom out around 4000 - name.length), so they
# can never outrank an exact row; they only exist when the exact pass found
# nothing anyway. Inside the typo set, rows order by tier (folded-exact,
# doubled-letter, one-edit, two-edit) then alphabetically, via the existing
# sort. The "" query path is untouched: q empty means the exact pass returns
# every row at score 0 and the second pass is skipped, exactly as before.
#
# Adaptation notes (vs the MenuModel port in patch 14): AppSearch entries
# have no description/id-root/visible concept, so the PR's per-term exact
# check uses AppSearch's own termMatches (substring in name/id/haystack,
# acronym for terms of 5 or fewer chars) and the folded "description" is
# genericName + comment + keywords. Scoring subsumes matching here, so
# there is no separate boolean matcher: entryTypoScore returns the worst
# tier (35/45/70/80) or -1, and sortedEntries uses that one call for both
# filter and rank. The DP prefilters and CJK skip are verbatim from the PR.
#
# Tests: upstream's test/shell.d/app-search-test.sh is NOT in FORK_OUT
# (fork-shell.sh extracts only listed subsets; test/ is not one), and no
# existing patch touches tests, so this patch does not edit a test file.
# Verification is a node harness over the patched AppSearch.js (AppSearch.js
# already has a module.exports block, so it loads directly in node): exact
# queries return exactly the unpatched rows in the same order, "batttle" ->
# Battle.net, "ffiles" -> Files, "braev" -> Brave Origin, "calcualtor" ->
# Calculator, "spotfiy" -> Spotify, folded-exact ("cafe" -> Café), CJK
# exclusion, long-paste DP guard, and the "" menu path identical to
# unpatched. The upstream app-search-test.sh assertions were also run
# against the patched file. See the README section in hexwork-push.
#
# Standalone: bash v2/patches/15-dock-typo-search.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited file is JS, not bash, so the end-of-patch
# check is node --check (AppSearch.js). bash -n would fail on it by
# construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "15-dock-typo-search.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Typo-tolerant dock search, omarchy PR #19938 (2026-11-26) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# The typo-search implementation, verbatim from the PR (and from the
# MenuModel port in patch 14, which carries the same code), adapted to
# AppSearch entries: per-term exact matching uses termMatches, the folded
# "description" is genericName + comment + keywords, and scoring subsumes
# matching (entryTypoScore returns the worst tier or -1), so there is no
# separate boolean matcher.
TYPO_FUNCTIONS = r"""// Folds case, strips optional combining diacritics (Latin/Greek/Cyrillic/
// Arabic/Hebrew) via NFD, and maps non-decomposing Latin letters so unaccented
// queries match localized labels without spending typo budget. NFD also
// decomposes Korean Hangul syllables into Jamo so single-jamo typos stay within
// one edit. Indic/Thai vowel signs are left intact because they are core vowels.
function foldSearchText(value) {
  var folded = String(value || "").toLowerCase()
  if (!/[^\x00-\x7f]/.test(folded)) return folded
  if (typeof folded.normalize === "function") folded = folded.normalize("NFD")
  return folded
    .replace(/[\u0300-\u036f\u0591-\u05bd\u05bf\u05c1\u05c2\u05c4\u05c5\u05c7\u0610-\u061a\u064b-\u065f\u0670]/g, "")
    .replace(/\u0131/g, "i")
    .replace(/\u0142/g, "l")
    .replace(/\u0111/g, "d")
    .replace(/\u00f8/g, "o")
    .replace(/\u00df/g, "ss")
    .replace(/\u00e6/g, "ae")
    .replace(/\u0153/g, "oe")
}

function toCodePoints(value) {
  var str = String(value || "")
  return /[\ud800-\udfff]/.test(str) ? Array.from(str) : str
}

// Collapses consecutive duplicate codepoints ("ffiles" -> "files").
function squeezeRepeats(value) {
  var chars = toCodePoints(value)
  if (chars.length <= 1) return String(value || "")
  var out = chars[0]
  for (var i = 1; i < chars.length; i++) {
    if (chars[i] !== chars[i - 1]) out += chars[i]
  }
  return out
}

// Skip edit distance for CJK ideograph/kana terms: 2-3 character words collide
// too easily at distance 1, while folded/squeezed matching still applies.
function hasCjkChars(value) {
  return /[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]/.test(String(value || ""))
}

function wordInText(term, text) {
  var words = String(text || "").split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i] === term) return true
  }
  return false
}

// Worst typo tier for the entry over every query term (35 folded-exact /
// 45 doubled-letter / 70 one-edit / 80 two-edit), or -1 when any term is
// out of budget. A term matches exactly first (termMatches), then folded,
// then squeezed, then within Damerau-Levenshtein budget of a search-text
// word prefix.
function entryTypoScore(entry, query) {
  if (!entry) return -1
  var foldedName = foldSearchText(entrySearchText(entry))
  var foldedWords = foldedName.split(/\s+/)
  var foldedDesc = foldSearchText([entry.genericName, entry.comment, keywordText(entry)].join(" "))
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  var worst = 0
  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (termMatches(entry, terms[i])) continue
    var dist = termTypoDistance(terms[i], foldedName, foldedWords, foldedDesc)
    if (dist < 0) return -1
    if (dist > worst) worst = dist
  }
  if (worst === 0) return 35
  if (worst === 0.5) return 45
  if (worst === 1) return 70
  return 80
}

// Returns 0 for diacritic-folded exact match, 0.5 for doubled-letter prefix
// match ("ffiles" -> "files"), 1..2 for Damerau-Levenshtein prefix distance,
// or -1 when out of budget. Uses length and character-overlap prefilters before
// running DP so worst-case queries stay fast on older CPUs.
function termTypoDistance(term, foldedName, foldedWords, foldedDesc) {
  var folded = foldSearchText(term)
  if (!folded) return -1
  if (foldedName.indexOf(folded) >= 0) return 0
  if (wordInText(folded, foldedDesc)) return 0

  var squeezed = squeezeRepeats(folded)
  if (squeezed.length >= 3) {
    for (var s = 0; s < foldedWords.length; s++) {
      if (!foldedWords[s]) continue
      if (squeezeRepeats(foldedWords[s]).indexOf(squeezed) === 0) return 0.5
    }
  }

  if (hasCjkChars(folded)) return -1

  var termChars = toCodePoints(folded)
  var limit = termChars.length >= 8 ? 2 : termChars.length >= 4 ? 1 : 0
  if (!limit) return -1

  var best = limit + 1
  for (var i = 0; i < foldedWords.length; i++) {
    var word = foldedWords[i]
    if (word.length < termChars.length - limit) continue
    var wordChars = toCodePoints(word)
    if (wordChars.length < termChars.length - limit) continue
    var start = wordChars.slice(0, termChars.length + limit)
    var missing = 0
    for (var c = 0; c < termChars.length && missing <= limit; c++) {
      if (start.indexOf(termChars[c]) < 0) missing++
    }
    if (missing > limit) continue
    var distances = prefixDistances(termChars, start)
    for (var n = termChars.length - limit; n < distances.length; n++) {
      if (distances[n] < best) best = distances[n]
    }
    if (best <= 1) break
  }

  return best <= limit ? best : -1
}

// Damerau-Levenshtein distances (optimal string alignment, so a swapped pair
// counts as one typo) from codepoint array a to each prefix of b, using three
// rolling rows to minimize allocations.
function prefixDistances(a, b) {
  var prevPrev = null
  var prev = []
  for (var j = 0; j <= b.length; j++) prev[j] = j

  for (var i = 1; i <= a.length; i++) {
    var curr = [i]
    for (var k = 1; k <= b.length; k++) {
      var cost = a[i - 1] === b[k - 1] ? 0 : 1
      var val = Math.min(prev[k] + 1, curr[k - 1] + 1, prev[k - 1] + cost)
      if (i > 1 && k > 1 && a[i - 1] === b[k - 2] && a[i - 2] === b[k - 1]) {
        val = Math.min(val, prevPrev[k - 2] + 1)
      }
      curr[k] = val
    }
    prevPrev = prev
    prev = curr
  }
  return prev
}"""

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    # AppSearch.js: the typo-search functions, inserted between fuzzyScore
    # and sortedEntries. Additive only; every existing function untouched.
    ("shell/services/AppSearch.js",
     "  return 4000 - name.length\n"
     "}\n"
     "\n"
     "function sortedEntries(values, query, hiddenCallback) {",
     "  return 4000 - name.length\n"
     "}\n"
     "\n"
     "\n"
     + TYPO_FUNCTIONS +
     "\n"
     "\n"
     "function sortedEntries(values, query, hiddenCallback) {",
     "AppSearch: add typo-search functions (fold/squeeze/DP)"),
    # AppSearch.js: the second pass itself. Only when the query is
    # non-empty and the exact pass found nothing, so correct spellings
    # cost nothing, show no typo rows, and the menu's sortedEntries("")
    # path is untouched (q empty skips this branch entirely).
    ("shell/services/AppSearch.js",
     "    rows.push({ entry: entry, score: score, key: entrySortKey(entry), name: name.toLowerCase() })\n"
     "  }\n"
     "\n"
     "  rows.sort(function(a, b) {",
     "    rows.push({ entry: entry, score: score, key: entrySortKey(entry), name: name.toLowerCase() })\n"
     "  }\n"
     "\n"
     "  // Typo-tolerant second pass (PR #19938, dock AppGrid): only\n"
     "  // when the query is non-empty and the exact pass found nothing, so\n"
     "  // a correct spelling costs nothing and shows no typo rows. Typo\n"
     "  // rows score below every exact row (exact scores bottom out around\n"
     "  // 4000 - name.length), so they can never outrank one.\n"
     "  if (q && rows.length === 0) {\n"
     "    for (var j = 0; j < values.length; j++) {\n"
     "      var typoEntry = values[j]\n"
     "      if (!typoEntry || typoEntry.noDisplay) continue\n"
     "      if (hiddenCallback && hiddenCallback(typoEntry)) continue\n"
     "      var typoName = entryName(typoEntry)\n"
     "      if (!typoName) continue\n"
     "      var tier = entryTypoScore(typoEntry, q)\n"
     "      if (tier < 0) continue\n"
     "      rows.push({ entry: typoEntry, score: 3000 - tier, key: entrySortKey(typoEntry), name: typoName.toLowerCase() })\n"
     "    }\n"
     "  }\n"
     "\n"
     "  rows.sort(function(a, b) {",
     "AppSearch sortedEntries: re-run with typos when first pass finds nothing"),
]

for rel, old, new, label in REPLACEMENTS:
    fp = root + "/" + rel
    try:
        with open(fp) as f:
            s = f.read()
    except FileNotFoundError:
        print("WARN: %s not in fork output, skipping (%s)" % (rel, label))
        continue
    if new in s:
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
print("dock-typo-search patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited file. It is JS, not bash, so bash -n would fail
# on it by construction and is deliberately not used here.
if command -v node >/dev/null 2>&1; then
  node --check "$FORK_OUT/shell/services/AppSearch.js" || die "node --check failed on patched AppSearch.js"
else
  warn "node not found, skipping AppSearch.js syntax check"
fi
info "  dock-typo-search: dock AppGrid now forgives typos on the second pass (PR #19938)"
