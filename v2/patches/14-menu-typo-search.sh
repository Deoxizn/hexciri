#!/usr/bin/env bash
# Hexciri fork patch 14: typo-tolerant search in the fork's OWN shell menu.
# Forward-port of omarchy PR #19938 (commit e5ad7ac392f3ddab102e24fb5c5afc1a7156953e,
# "feat(menu): add typo-tolerant search") into shell/plugins/menu/.
#
# Why the fork menu and not the nyxiri-menu plugin: Super+Alt+Space summons
# the fork's shell menu, not pizza.dirty.nyxiri-menu. The same PR was already
# ported to nyxiri-menu (nyx e45140f, still live there), but Devi's test
# showed "batttle" finding nothing in the Super+Alt+Space menu: the fork
# menu had no typo code at all. This patch puts the same second pass in the
# menu that actually opens.
#
# What it does (PR behavior, unchanged): exact search runs first, untouched.
# Only when it finds 0 rows does the menu re-run the search forgiving typos
# in name words: NFD diacritic/Hangul-Jamo folding, a doubled-letter fast
# path ("ffiles" finds Files, "batttle" finds Battle.net), and
# Damerau-Levenshtein prefix matching (1 edit from 4+ codepoints, 2 from
# 8+, swapped pair counts as one; skipped for CJK terms). Exact matches
# never show typo rows.
#
# Scoring: the PR's typo-tier branch is ported verbatim (35 folded-exact /
# 45 doubled-letter / 70 one-edit / 80 two-edit, via queryTypoScore). The
# fork's scoring tiers and composite are untouched: the fork baseline is
# NEWER than the nyxiri plugin's (alt: variants, and the new composite
# score * 10000000 + depthFor * 100000 + (opensMenu ? 0 : 50000) + order),
# so the nyxiri port's searchScore was NOT copied wholesale, only the
# typos param + typo-tier else-if branch. The alt: variant code and every
# hexciri rename in both files are preserved; the typo edits are additive.
#
# Tests: upstream's test/shell.d/menu-test.sh is NOT in FORK_OUT
# (fork-shell.sh extracts only listed subsets; test/ is not one), and no
# existing patch touches tests, so this patch does not edit a test file.
# Verification is a node harness over the patched MenuModel.js (same
# assertions as the nyxiri port's tests: typo-only matching, doubled-letter
# ranking, multilingual folding, CJK exclusion, QML two-pass, long-paste
# DP guard) plus a "batttle" -> Battle.net / "ffiles" -> Files repro.
# See the README section in hexwork-push for the results.
#
# Standalone: bash v2/patches/14-menu-typo-search.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#
# Syntax check note: the edited files are JS/QML, not bash, so the
# end-of-patch check is node --check (MenuModel.js) and qmllint when
# present (Menu.qml, warning only: qmllint fails on missing Quickshell
# imports even for valid files). bash -n would fail on both files by
# construction and is deliberately not used here.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "14-menu-typo-search.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

# --- Typo-tolerant menu search, omarchy PR #19938 (2026-11-26) ---
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# The typo-search implementation, verbatim from the PR (and from the
# nyxiri-menu port, which carries the same code). Only searchScore's
# integration differs: the fork keeps its own scoring composite.
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

// A search that found nothing runs again forgiving typos: each term matches as
// typed, after diacritic/Hangul folding, after collapsing doubled letters, or
// within Damerau-Levenshtein budget of a name word prefix.
function matchesQueryWithTypos(entry, query, visible) {
  if (!entry || entry.id === "root" || !visible) return false
  var foldedName = foldSearchText(nameSearchText(entry))
  var foldedWords = foldedName.split(/\s+/)
  var foldedDesc = foldSearchText(entry.description || "")
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (matchesQuery(entry, terms[i], true)) continue
    if (termTypoDistance(terms[i], foldedName, foldedWords, foldedDesc) >= 0) continue
    return false
  }
  return true
}

function queryTypoScore(entry, query) {
  var foldedName = foldSearchText(nameSearchText(entry))
  var foldedWords = foldedName.split(/\s+/)
  var foldedDesc = foldSearchText(entry.description || "")
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  var worst = 0
  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (matchesQuery(entry, terms[i], true)) continue
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
  if (termInSearchWords(folded, foldedDesc)) return 0

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
    # MenuModel.js: searchScore gains the typos param.
    ("shell/plugins/menu/MenuModel.js",
     "function searchScore(items, entry, query) {",
     "function searchScore(items, entry, query, typos) {",
     "MenuModel searchScore: add typos param"),
    # MenuModel.js: typo-tier branch, ported verbatim from the PR. It sits
    # after the description branch and before the app -5 adjustment, so a
    # typo match keeps its tier (35/45/70/80) and app rows still sort after
    # menu rows inside that tier. Fork scoring tiers and composite untouched.
    ("shell/plugins/menu/MenuModel.js",
     "  else if (descriptionTextMatches(needle, descriptionText)) score = 60\n"
     "\n"
     "  // App rows sort after all menu items, so they lose the tiebreak below to an",
     "  else if (descriptionTextMatches(needle, descriptionText)) score = 60\n"
     "  else if (typos) {\n"
     "    var typoTier = queryTypoScore(entry, needle)\n"
     "    if (typoTier >= 0) score = typoTier\n"
     "  }\n"
     "\n"
     "  // App rows sort after all menu items, so they lose the tiebreak below to an",
     "MenuModel searchScore: typo-tier branch (PR #19938)"),
    # MenuModel.js: the typo-search functions, inserted between searchScore
    # and displayRow. Additive only; altVariant and everything else untouched.
    ("shell/plugins/menu/MenuModel.js",
     "  return score * 10000000 + depthFor(items, entry.id) * 100000 + (opensMenu ? 0 : 50000) + entry.order\n"
     "}\n"
     "\n"
     "function displayRow(items, itemOrder, checkedResults, disabledResults, entry, detail, score, section) {",
     "  return score * 10000000 + depthFor(items, entry.id) * 100000 + (opensMenu ? 0 : 50000) + entry.order\n"
     "}\n"
     "\n"
     "\n"
     + TYPO_FUNCTIONS +
     "\n"
     "\n"
     "function displayRow(items, itemOrder, checkedResults, disabledResults, entry, detail, score, section) {",
     "MenuModel: add typo-search functions (fold/squeeze/DP)"),
    # MenuModel.js: export the helpers the tests (and Menu.qml) use.
    ("shell/plugins/menu/MenuModel.js",
     "    matchesQuery: matchesQuery,\n"
     "    searchScore: searchScore,",
     "    matchesQuery: matchesQuery,\n"
     "    matchesQueryWithTypos: matchesQueryWithTypos,\n"
     "    foldSearchText: foldSearchText,\n"
     "    squeezeRepeats: squeezeRepeats,\n"
     "    searchScore: searchScore,",
     "MenuModel: export typo-search helpers"),
    # Menu.qml: matchesQuery gains the typos param and dispatches to the
    # typo matcher on the second pass.
    ("shell/plugins/menu/Menu.qml",
     "  function matchesQuery(entry, query) {\n"
     "    return MenuModel.matchesQuery(entry, query, root.isVisible(entry) && !root.isDisabled(entry))\n"
     "  }",
     "  function matchesQuery(entry, query, typos) {\n"
     "    var visible = root.isVisible(entry) && !root.isDisabled(entry)\n"
     "    return typos ? MenuModel.matchesQueryWithTypos(entry, query, visible) : MenuModel.matchesQuery(entry, query, visible)\n"
     "  }",
     "Menu.qml matchesQuery: add typos param, typo second-pass dispatch"),
    # Menu.qml: searchScore gains the typos param and passes it through.
    ("shell/plugins/menu/Menu.qml",
     "  function searchScore(entry, query) {\n"
     "    return MenuModel.searchScore(root.items, entry, query)\n"
     "  }",
     "  function searchScore(entry, query, typos) {\n"
     "    return MenuModel.searchScore(root.items, entry, query, typos)\n"
     "  }",
     "Menu.qml searchScore: add typos param"),
    # Menu.qml: rebuildDisplay gains the typos param.
    ("shell/plugins/menu/Menu.qml",
     "  function rebuildDisplay() {",
     "  function rebuildDisplay(typos) {",
     "Menu.qml rebuildDisplay: add typos param"),
    # Menu.qml: the search loop passes typos through to the matcher.
    ("shell/plugins/menu/Menu.qml",
     "        if (!root.matchesQuery(entry, query)) continue",
     "        if (!root.matchesQuery(entry, query, typos)) continue",
     "Menu.qml rebuildDisplay: pass typos to matchesQuery"),
    # Menu.qml: the search loop passes typos through to the scorer.
    ("shell/plugins/menu/Menu.qml",
     "        var row = root.displayRow(entry, detail, root.searchScore(entry, query))",
     "        var row = root.displayRow(entry, detail, root.searchScore(entry, query, typos))",
     "Menu.qml rebuildDisplay: pass typos to searchScore"),
    # Menu.qml: the second pass itself. Only when the exact search found
    # nothing, so correct spellings cost nothing and show no typo rows.
    ("shell/plugins/menu/Menu.qml",
     "      }\n"
     "\n"
     "      var searchSort = function(a, b) {",
     "      }\n"
     "\n"
     "      // Typos only fill a search that found nothing, so a correct spelling\n"
     "      // gets exactly the rows it always did at zero extra cost.\n"
     "      if (!typos && currentRows.length + drilldownRows.length === 0) return root.rebuildDisplay(true)\n"
     "\n"
     "      var searchSort = function(a, b) {",
     "Menu.qml rebuildDisplay: re-run with typos=true when first pass finds nothing"),
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
print("menu-typo-search patch: %d file edits applied" % len(changed))
PY

# Syntax-check the edited files. They are JS/QML, not bash, so bash -n
# would fail on both by construction and is deliberately not used here.
if command -v node >/dev/null 2>&1; then
  node --check "$FORK_OUT/shell/plugins/menu/MenuModel.js" || die "node --check failed on patched MenuModel.js"
else
  warn "node not found, skipping MenuModel.js syntax check"
fi
if command -v qmllint >/dev/null 2>&1; then
  qmllint "$FORK_OUT/shell/plugins/menu/Menu.qml" || warn "qmllint reported issues on patched Menu.qml (missing Quickshell imports also trip it; see output above)"
else
  warn "qmllint not found, skipping Menu.qml parse check"
fi
info "  menu-typo-search: fork shell menu now forgives typos on the second pass (PR #19938)"
