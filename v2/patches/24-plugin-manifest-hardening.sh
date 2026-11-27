#!/usr/bin/env bash
# Hexciri fork patch 24: harden plugin manifest scan framing and fix
# plugin lifecycle races (upstream omacom/omarchy #19961, commit 0810fdb90).
# Line-count framing stops a third-party manifest injecting a synthetic
# first-party header (===firstparty::...===) or truncating the parse;
# first-party manifests outside firstPartyDir are rejected; plugin ids
# "__proto__"/"constructor"/"prototype"/"." and backslash/control-char
# entry points are rejected; shell.qml drops stale async service/widget
# loads via _pendingServices tokens and refreshes panel entry shell/
# manifest/service on reconcile. Security-relevant: Nyxiri third-party
# plugins (pizza.dirty.*) load through this registry. Port BEFORE #20129
# (patch 28), which extends PluginRegistry.qml.
#
# Fork notes: no rename impact in the ported hunks except the rescan-script
# comment, which reads ~/.config/hexciri/plugins after the rename map.
# Test-only upstream files (test/shell.d/plugin-manifest-scan-test.sh and
# the plugin-registry fixture) are NOT ported: test/ is not in FORK_OUT.
#
# Standalone: bash v2/patches/24-plugin-manifest-hardening.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "24-plugin-manifest-hardening.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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

python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import sys

root = sys.argv[1]
changed = []

# (file, old, new, label). old must occur exactly once; new already
# present means this edit is done (idempotent re-run).
REPLACEMENTS = [
    ('shell/services/PluginRegistry.qml',
     r'''    if (value.charAt(0) === "/") return false
    if (value.indexOf("..") !== -1) return false
    return true
''',
     r'''    if (value.charAt(0) === "/") return false
    if (value.indexOf("..") !== -1 || value.indexOf("\\") !== -1) return false
    if (/[\x00-\x1f]/.test(value)) return false
    return true
''',
     'isSafeEntryPoint: reject backslash + control chars'),
    ('shell/services/PluginRegistry.qml',
     r'''    var id = String(manifest.id)
    if (!id || id.indexOf("/") !== -1 || id.indexOf("..") !== -1 || id.charAt(0) === "/") {
      console.warn("PluginRegistry: invalid plugin id '" + id + "' at " + sourcePath)
''',
     r'''    var id = String(manifest.id)
    if (!id || id === "." || id === "__proto__" || id === "constructor" || id === "prototype"
        || id.indexOf("/") !== -1 || id.indexOf("..") !== -1 || /[\x00-\x1f]/.test(id)) {
      console.warn("PluginRegistry: invalid plugin id '" + id + "' at " + sourcePath)
''',
     'validateManifest: reject __proto__/constructor/prototype/. + control chars'),
    ('shell/services/PluginRegistry.qml',
     r'''  // Output format produced by the rescan script:
  //   ===<kind>::<absolute-source-dir>===
  //   ... raw manifest.json content ...
  //   === EOM ===
  // (repeating for every manifest found)
  function parseScanOutput(text) {
    var lines = String(text || "").split("\n")
    var firstParty = {}
    var thirdParty = {}
    var currentSource = null
    var currentKind = null
    var currentJson = []

    function flush() {
      if (!currentSource) return
      var raw = currentJson.join("\n").trim()
      try {
        var manifest = JSON.parse(raw)
        manifest.__sourceDir = currentSource
        manifest.__isFirstParty = (currentKind === "firstparty")
        var validated = validateManifest(manifest, currentSource + "/manifest.json")
        if (validated) {
          if (currentKind === "firstparty") firstParty[validated.id] = validated
          else thirdParty[validated.id] = validated
        }
      } catch (e) {
        console.warn("PluginRegistry: bad manifest at " + currentSource + ": " + e)
      }
      currentSource = null
      currentKind = null
      currentJson = []
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var startMatch = line.match(/^===([a-z]+)::(.+)===$/)
      if (startMatch) {
        flush()
        currentKind = startMatch[1]
        currentSource = startMatch[2].replace(/\/$/, "")
        currentJson = []
        continue
      }
      if (line === "=== EOM ===") {
        flush()
        continue
      }
      if (currentSource) currentJson.push(line)
    }
    flush()

    stampHostCapabilities(firstParty, thirdParty)
''',
     r'''  // Output format produced by the rescan script:
  //   ===<kind>::<line-count>::<absolute-source-dir>===
  //   ... exact <line-count> raw manifest.json lines ...
  //   === EOM ===
  // (repeating for every manifest found)
  function isWithinDir(path, rootDir) {
    var base = String(rootDir || "").replace(/\/+$/, "")
    if (!base) return false
    var candidate = String(path || "").replace(/\/+$/, "")
    if (candidate.split("/").indexOf("..") !== -1) return false
    return candidate.indexOf(base + "/") === 0
  }

  function parseScanOutput(text) {
    var lines = String(text || "").split("\n")
    var firstParty = {}
    var thirdParty = {}

    for (var i = 0; i < lines.length; i++) {
      var startMatch = lines[i].match(/^===(firstparty|thirdparty)::(\d+)::(.+)===$/)
      if (!startMatch) continue
      var kind = startMatch[1]
      var lineCount = parseInt(startMatch[2], 10)
      var source = startMatch[3].replace(/\/+$/, "")
      if (i + lineCount >= lines.length) {
        console.warn("PluginRegistry: truncated manifest stream at " + source)
        break
      }
      var raw = lines.slice(i + 1, i + 1 + lineCount).join("\n").trim()
      i += lineCount
      if (lines[i + 1] === "=== EOM ===") i++
      if (kind === "firstparty" && !isWithinDir(source, registry.firstPartyDir)) {
        console.warn("PluginRegistry: rejecting first-party manifest outside firstPartyDir: " + source)
        continue
      }
      try {
        var manifest = JSON.parse(raw)
        if (!Util.isPlainObject(manifest)) {
          console.warn("PluginRegistry: manifest is not an object at " + source + "/manifest.json")
          continue
        }
        manifest.__sourceDir = source
        manifest.__isFirstParty = (kind === "firstparty")
        var validated = validateManifest(manifest, source + "/manifest.json")
        if (validated) {
          if (kind === "firstparty") firstParty[validated.id] = validated
          else thirdParty[validated.id] = validated
        }
      } catch (e) {
        console.warn("PluginRegistry: bad manifest at " + source + ": " + e)
      }
    }

    stampHostCapabilities(firstParty, thirdParty)
''',
     'parseScanOutput: line-count framing + isWithinDir + plain-object check'),
    ('shell/services/PluginRegistry.qml',
     r'''    // Third-party plugins stay at the top level of ~/.config/hexciri/plugins.
    var script = ""
      + "emit_manifest() { local kind=\"$1\"; local manifest=\"$2\"; local sub; "
      + "  if [[ ${manifest##*/} == \"manifest.json\" ]]; then sub=\"${manifest%/manifest.json}\"; else sub=\"${manifest%/*}\"; fi; "
      + "  printf '===%s::%s===\\n' \"$kind\" \"$sub\"; "
      + "  printf '%s\\n' \"$(<\"$manifest\")\"; "
      + "  printf '\\n=== EOM ===\\n'; "
      + "}; "
      + "scan_firstparty() { local dir=\"$1\"; "
      + "  [[ -d \"$dir\" ]] || return 0; "
      + "  while IFS= read -r manifest; do emit_manifest firstparty \"$manifest\"; done < <(find \"$dir\" -mindepth 2 -maxdepth 3 -type f \\( -name manifest.json -o -name '*.manifest.json' \\) | sort); "
      + "}; "
      + "scan_thirdparty() { local dir=\"$1\"; "
      + "  [[ -d \"$dir\" ]] || return 0; "
      + "  for sub in \"$dir\"/*/; do "
      + "    [[ -f \"$sub/manifest.json\" ]] || continue; "
      + "    emit_manifest thirdparty \"$sub/manifest.json\"; "
      + "  done; "
      + "}; "
      + "scan_firstparty \"$0\"; "
      + "scan_thirdparty \"$1\""
    scanProcess.command = ["bash", "-c", script, registry.firstPartyDir, registry.pluginsDir]
''',
     r'''    // Third-party plugins stay at the top level of ~/.config/hexciri/plugins.
    // Each manifest is framed by its exact line count so untrusted third-party
    // manifest contents can never inject a synthetic header (such as
    // `===firstparty::...===`) or truncate parsing early.
    var script = ""
      + "emit_manifest() { local kind=\"$1\"; local manifest=\"$2\"; local sub; local -a lines=(); "
      + "  [[ -r $manifest ]] || return 0; "
      + "  if [[ ${manifest##*/} == \"manifest.json\" ]]; then sub=\"${manifest%/manifest.json}\"; else sub=\"${manifest%/*}\"; fi; "
      + "  sub=\"${sub%/}\"; "
      + "  [[ $sub == *$'\\n'* ]] && return 0; "
      + "  mapfile -t lines < \"$manifest\"; "
      + "  printf '===%s::%d::%s===\\n' \"$kind\" \"${#lines[@]}\" \"$sub\"; "
      + "  if (( ${#lines[@]} > 0 )); then printf '%s\\n' \"${lines[@]}\"; fi; "
      + "  printf '=== EOM ===\\n'; "
      + "}; "
      + "scan_firstparty() { local dir=\"$1\"; "
      + "  [[ -d $dir ]] || return 0; "
      + "  while IFS= read -r -d '' manifest; do emit_manifest firstparty \"$manifest\"; done < <(find \"$dir\" -mindepth 2 -maxdepth 3 -type f \\( -name manifest.json -o -name '*.manifest.json' \\) -print0 | sort -z); "
      + "}; "
      + "scan_thirdparty() { local dir=\"$1\"; "
      + "  [[ -d $dir ]] || return 0; "
      + "  for sub in \"$dir\"/*/; do "
      + "    [[ -f ${sub}manifest.json ]] || continue; "
      + "    emit_manifest thirdparty \"${sub}manifest.json\"; "
      + "  done; "
      + "}; "
      + "scan_firstparty \"$0\"; "
      + "scan_thirdparty \"$1\""
    scanProcess.command = ["bash", "-c", script, registry.firstPartyDir, registry.pluginsDir]
''',
     'rescan script: emit_manifest frames each manifest by line count, NUL-safe find'),
    ('shell/shell.qml',
     r'''  property var _services: ({})
  property var _pluginShellApis: ({})
''',
     r'''  property var _services: ({})
  property var _pendingServices: ({})
  property var _pluginShellApis: ({})
''',
     'shell.qml: _pendingServices token map'),
    ('shell/shell.qml',
     r'''  function ensureService(pluginId) {
    var key = String(pluginId)
    if (_services[key]) return _services[key]
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("service") === -1) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    var url = pluginRegistry.entryPointUrl(manifest, "service")
    if (!url) return null
    var authenticationService = shell.isAuthenticationService(manifest, key)
    if (authenticationService && AuthServiceStore.has(key)) return null

    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status !== Component.Ready) {
        console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        return
      }
      // Authentication services and third-party services have no visual
      // parent. Parenting either to serviceHost would let a plugin's object
      // traversal walk between the host and credential-bearing QML.
      var inst = comp.createObject(manifest.__isFirstParty && !authenticationService ? serviceHost : null)
      if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        return
      }
      if ("omarchyPath" in inst) inst.omarchyPath = shell.omarchyPath
      if ("shell" in inst) inst.shell = shell.pluginShellFor(manifest)
      if ("manifest" in inst) inst.manifest = shell.publicPluginManifest(manifest)
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.pluginBarWidgetRegistryFor(manifest)
      if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistryFor(manifest)
      if (authenticationService) {
        // Never publish lock/polkit through ShellRoot._services. The private JS
        // import retains their lifetime without adding a traversable property
        // or QObject parent back to the host shell.
        AuthServiceStore.put(key, inst)
      } else {
        var snext = ({})
        for (var sk in _services) snext[sk] = _services[sk]
        snext[key] = inst
        _services = snext
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return authenticationService ? null : (_services[key] || null)
  }

  function _syncServices() {
''',
     r'''  function ensureService(pluginId) {
    var key = String(pluginId)
    if (_services[key]) return _services[key]
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("service") === -1) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    var url = pluginRegistry.entryPointUrl(manifest, "service")
    if (!url) return null
    if (_pendingServices[key] && _pendingServices[key].url === url) return null
    var authenticationService = shell.isAuthenticationService(manifest, key)
    if (authenticationService && AuthServiceStore.has(key)) return null

    var token = ({ url: url })
    _pendingServices[key] = token
    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status === Component.Loading) return
      var stale = _pendingServices[key] !== token
      if (!stale) delete _pendingServices[key]
      if (stale || comp.status !== Component.Ready) {
        if (!stale) console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        comp.destroy()
        return
      }
      var currentManifest = pluginRegistry && pluginRegistry.installedPlugins
        ? pluginRegistry.installedPlugins[key] : null
      var stillService = currentManifest
        && Array.isArray(currentManifest.kinds)
        && currentManifest.kinds.indexOf("service") !== -1
        && currentManifest.entryPoints
        && currentManifest.entryPoints.service
        && pluginRegistry.entryPointUrl(currentManifest, "service") === url
      if (!stillService || !pluginRegistry.isEnabled(key) || shell.pluginReloading) {
        comp.destroy()
        return
      }
      manifest = currentManifest
      authenticationService = shell.isAuthenticationService(manifest, key)
      if ((authenticationService && AuthServiceStore.has(key))
          || (!authenticationService && _services[key])) {
        comp.destroy()
        return
      }
      // Authentication services and third-party services have no visual
      // parent. Parenting either to serviceHost would let a plugin's object
      // traversal walk between the host and credential-bearing QML.
      var inst = comp.createObject(manifest.__isFirstParty && !authenticationService ? serviceHost : null)
      comp.destroy()
      if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        return
      }
      if ("omarchyPath" in inst) inst.omarchyPath = shell.omarchyPath
      if ("shell" in inst) inst.shell = shell.pluginShellFor(manifest)
      if ("manifest" in inst) inst.manifest = shell.publicPluginManifest(manifest)
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.pluginBarWidgetRegistryFor(manifest)
      if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistryFor(manifest)
      if (authenticationService) {
        // Never publish lock/polkit through ShellRoot._services. The private JS
        // import retains their lifetime without adding a traversable property
        // or QObject parent back to the host shell.
        AuthServiceStore.put(key, inst)
      } else {
        var snext = ({})
        for (var sk in _services) snext[sk] = _services[sk]
        snext[key] = inst
        _services = snext
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return authenticationService ? null : (_services[key] || null)
  }

  function _syncServices() {
''',
     'shell.qml: ensureService drops stale async loads, revalidates manifest'),
    ('shell/shell.qml',
     r'''    // Drop services for plugins that have been disabled or removed, or that
    // no longer declare a service entry point.
    for (var existingId in _services) {
      var stillThere = plugins[existingId]
      var stillService = stillThere && Array.isArray(stillThere.kinds)
        && stillThere.kinds.indexOf("service") !== -1
        && stillThere.entryPoints && stillThere.entryPoints.service
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillService && stillEnabled) continue
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in _services) if (k !== existingId) next[k] = _services[k]
      _services = next
    }
    // Authentication services are retained outside the root object graph, so
''',
     r'''    // Drop services for plugins that have been disabled or removed, or that
    // no longer declare a service entry point.
    for (var existingId in _services) {
      var stillThere = plugins[existingId]
      var stillService = stillThere && Array.isArray(stillThere.kinds)
        && stillThere.kinds.indexOf("service") !== -1
        && stillThere.entryPoints && stillThere.entryPoints.service
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillService && stillEnabled) continue
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in _services) if (k !== existingId) next[k] = _services[k]
      _services = next
    }
    // Cancel pending async loads for services that are no longer enabled or declared.
    var pendingIds = Object.keys(_pendingServices)
    for (var pi = 0; pi < pendingIds.length; pi++) {
      var pendingId = pendingIds[pi]
      var pendingManifest = plugins[pendingId]
      var stillPendingService = pendingManifest
        && Array.isArray(pendingManifest.kinds)
        && pendingManifest.kinds.indexOf("service") !== -1
        && pendingManifest.entryPoints
        && pendingManifest.entryPoints.service
        && pluginRegistry.isEnabled(pendingId)
        && pluginRegistry.entryPointUrl(pendingManifest, "service") === _pendingServices[pendingId].url
      if (!stillPendingService) delete _pendingServices[pendingId]
    }
    // Authentication services are retained outside the root object graph, so
''',
     'shell.qml: _syncServices cancels pending loads for removed/disabled services'),
    ('shell/shell.qml',
     r'''  function unloadPluginServices() {
    var next = ({})
    for (var existingId in _services) {
      if (serviceKeepLoaded(existingId)) {
        next[existingId] = _services[existingId]
        continue
      }
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
    }
    _services = next
    var authenticationIds = AuthServiceStore.ids()
    for (var ai = 0; ai < authenticationIds.length; ai++) {
      var authenticationId = authenticationIds[ai]
      if (!serviceKeepLoaded(authenticationId))
        AuthServiceStore.destroy(authenticationId)
    }
  }

  Connections {
''',
     r'''  function unloadPluginServices() {
    _pendingServices = ({})
    var next = ({})
    for (var existingId in _services) {
      if (serviceKeepLoaded(existingId)) {
        next[existingId] = _services[existingId]
        continue
      }
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
    }
    _services = next
    var authenticationIds = AuthServiceStore.ids()
    for (var ai = 0; ai < authenticationIds.length; ai++) {
      var authenticationId = authenticationIds[ai]
      if (!serviceKeepLoaded(authenticationId))
        AuthServiceStore.destroy(authenticationId)
    }
  }

  Connections {
''',
     'shell.qml: unloadPluginServices clears _pendingServices'),
    ('shell/shell.qml',
     r'''      var row = panelEntryModel.get(j)
      var next = wanted[row.pluginId]
      if (next && next.kind === row.entryKind && next.keepLoaded === row.keepLoaded && next.sourceUrl === row.sourceUrl) {
        delete wanted[row.pluginId]
      } else {
        panelEntryModel.remove(j)
''',
     r'''      var row = panelEntryModel.get(j)
      var next = wanted[row.pluginId]
      if (next && next.kind === row.entryKind && next.keepLoaded === row.keepLoaded && next.sourceUrl === row.sourceUrl) {
        var loader = panelLoaders[row.pluginId]
        if (loader && loader.item) {
          if ("shell" in loader.item) loader.item.shell = shell.pluginShellFor(next.manifest)
          if ("manifest" in loader.item) loader.item.manifest = shell.publicPluginManifest(next.manifest)
          if ("service" in loader.item) loader.item.service = shell.serviceFor(row.pluginId)
        }
        delete wanted[row.pluginId]
      } else {
        panelEntryModel.remove(j)
''',
     'shell.qml: panel entries refresh shell/manifest/service on reconcile'),
    ('shell/shell.qml',
     r'''      loadPluginWidget(registryKey, url, meta)
    }

    // Drop registrations for plugins that are no longer present or enabled.
    var allIds = shell.barWidgetRegistry.availableIds()
    for (var i = 0; i < allIds.length; i++) {
      var id = allIds[i]
      if (!pluginWidgetComponents[id]) continue
      if (!seen[id]) {
        shell.barWidgetRegistry.unregister(id)
        var next = ({})
        for (var k in pluginWidgetComponents) if (k !== id) next[k] = pluginWidgetComponents[k]
        pluginWidgetComponents = next
      }
    }
  }

  function unloadPluginWidgets() {
''',
     r'''      loadPluginWidget(registryKey, url, meta)
    }

    // Drop registrations and in-flight loads for plugins that are no longer present or enabled.
    var trackedIds = Object.keys(pluginWidgetComponents)
    var nextWidgets = null
    for (var i = 0; i < trackedIds.length; i++) {
      var id = trackedIds[i]
      if (seen[id]) continue
      if (shell.barWidgetRegistry.has(id)) shell.barWidgetRegistry.unregister(id)
      if (!nextWidgets) {
        nextWidgets = ({})
        for (var k in pluginWidgetComponents) nextWidgets[k] = pluginWidgetComponents[k]
      }
      delete nextWidgets[id]
    }
    if (nextWidgets) pluginWidgetComponents = nextWidgets
  }

  function unloadPluginWidgets() {
''',
     'shell.qml: syncPluginWidgets drops in-flight loads for removed plugins'),
    ('shell/shell.qml',
     r'''    function onScanFinished() {
      if (shell.pluginReloadPending) {
        shell.pluginReloadPending = false
        shell.pluginReloading = false
        shell.pluginRescanPending = false
        Qt.callLater(shell.reloadPlugins)
        return
      }
      shell.pluginReloading = false
      shell._syncServices()
      shell.syncPanelEntries()
      shell.syncPluginWidgets()
      if (shell.pluginRescanPending) {
        shell.pluginRescanPending = false
        Qt.callLater(shell.rescanPlugins)
''',
     r'''    function onScanFinished() {
      if (shell.pluginReloadPending) {
        shell.pluginReloadPending = false
        shell.pluginReloading = false
        shell.pluginRescanPending = false
        Qt.callLater(shell.reloadPlugins)
        return
      }
      var wasReloading = shell.pluginReloading
      shell.pluginReloading = false
      if (wasReloading) {
        shell._syncServices()
        shell.syncPanelEntries()
        shell.syncPluginWidgets()
      }
      if (shell.pluginRescanPending) {
        shell.pluginRescanPending = false
        Qt.callLater(shell.rescanPlugins)
''',
     'shell.qml: rescan syncs services/panels/widgets only when a reload ran'),
    ('shell/shell.qml',
     r'''  function loadPluginWidget(registryKey, url, meta) {
    // Claim the key before the component exists. Qt.createComponent is
    // asynchronous and syncPluginWidgets runs several times while the shell
    // starts, so without a marker the later passes cannot tell a load in
    // flight from one that never happened.
    setPluginWidgetComponent(registryKey, { url: url, component: null })

    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Ready) {
        shell.barWidgetRegistry.register(registryKey, comp, meta)
        shell.setPluginWidgetComponent(registryKey, { url: url, component: comp })
      } else if (comp.status === Component.Error) {
        console.warn("Plugin widget " + registryKey + " failed: " + comp.errorString())
        // Drop the claim so a later rescan can retry.
        shell.setPluginWidgetComponent(registryKey, null)
        shell.pluginRegistry.pluginLoadFailed(registryKey, comp.errorString())
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
    } else {
      finalize()
    }
  }

  // ------------------------------------------------------ global shortcuts
''',
     r'''  function loadPluginWidget(registryKey, url, meta) {
    // Claim the key before the component exists. Qt.createComponent is
    // asynchronous and syncPluginWidgets runs several times while the shell
    // starts, so without a marker the later passes cannot tell a load in
    // flight from one that never happened.
    var token = { url: url, component: null }
    setPluginWidgetComponent(registryKey, token)

    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Loading) return
      var currentManifest = shell.pluginRegistry.installedPlugins[registryKey]
      var stillWidget = currentManifest
        && Array.isArray(currentManifest.kinds)
        && currentManifest.kinds.indexOf("bar-widget") !== -1
        && shell.pluginRegistry.isEnabled(registryKey)
        && shell.pluginRegistry.entryPointUrl(currentManifest, "barWidget") === url
      if (pluginWidgetComponents[registryKey] !== token || !stillWidget || shell.pluginReloading) {
        if (pluginWidgetComponents[registryKey] === token) shell.setPluginWidgetComponent(registryKey, null)
        comp.destroy()
        return
      }
      if (comp.status === Component.Ready) {
        shell.barWidgetRegistry.register(registryKey, comp, meta)
        shell.setPluginWidgetComponent(registryKey, { url: url, component: comp })
      } else if (comp.status === Component.Error) {
        console.warn("Plugin widget " + registryKey + " failed: " + comp.errorString())
        // Drop the claim so a later rescan can retry.
        shell.setPluginWidgetComponent(registryKey, null)
        shell.pluginRegistry.pluginLoadFailed(registryKey, comp.errorString())
        comp.destroy()
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
    } else {
      finalize()
    }
  }

  // ------------------------------------------------------ global shortcuts
''',
     'shell.qml: loadPluginWidget drops stale async widget loads'),
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
print("24 patch: %d file edits applied" % len(changed))
PY

# The python block above writes through >>"$_patch_log", a separate open
# file description when _patch_log is /dev/stdout. If this script's stdout
# is a regular file, the shell's fd offset is still where it was before
# python ran, so the validation/info prints below would overwrite the
# start of python's output (observed in sim: the first patched: lines
# were clobbered by the trailing info line). Seek stdout to EOF first;
# a guarded no-op on terminals and pipes, where lseek fails.
python3 -c "import os
try:
    os.lseek(1, 0, os.SEEK_END)
except OSError:
    pass" 2>/dev/null || true

# Every edited file must still parse. Missing files were warned and
# skipped above, so only check the ones that exist. bash -n does not
# apply to QML; qmllint is warning-only when present (Quickshell imports
# are not all resolvable here).
if command -v qmllint >/dev/null 2>&1; then
  for _f in shell/services/PluginRegistry.qml shell/shell.qml; do
    if [ -f "$FORK_OUT/$_f" ]; then
      qmllint "$FORK_OUT/$_f" || warn "qmllint reported issues on patched $_f (warning only)"
    fi
  done
  unset _f
else
  warn "qmllint not found; QML syntax not checked here"
fi
info "  plugin-manifest-hardening: manifest scan framed by line count, __proto__ ids rejected, stale async plugin loads dropped"
