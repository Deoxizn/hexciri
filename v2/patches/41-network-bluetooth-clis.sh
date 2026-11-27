#!/usr/bin/env bash
# Hexciri fork patch 41: network wifi/ethernet + bluetooth CLIs.
# Forward-port of omarchy PR #20331 (commit 03e670714, "Add omarchy network
# wifi and ethernet CLI commands") and PR #20332 (commit c5fbeec6e, "Add
# omarchy bluetooth CLI command"). Large, self-contained; CLI cores only.
#
# What it does: three new Python CLIs, all nmcli/bluetoothctl-based, all
# with human + --json output for the shell and for agents:
# - hexciri network wifi: status, on/off/toggle, list/scan (--rescan,
#   --known), connect (known/open/PSK/enterprise), disconnect, forget,
#   password, band (auto/2.4/5/6).
# - hexciri network ethernet: status, list, connect/disconnect, dhcp,
#   static (IPv4 + gateway + DNS), forget.
# - hexciri bluetooth: status, on/off/toggle, list, scan, info, pair,
#   connect/disconnect, forget, trust/untrust.
# The router needs no new dispatch code: bin/hexciri resolves
# hexciri-network-wifi / hexciri-network-ethernet / hexciri-bluetooth by
# file name and # omarchy:group= metadata, as upstream. Only the network
# group description changes, exactly as upstream did ("Network status
# helpers" -> "Network, Wi-Fi, and Ethernet controls").
#
# Overlap check vs the fork's own bin/hexciri-network (358 lines,
# fork-native, read on nyx @ 5b8e3b9): NO OVERLAP, full port is correct.
# hexciri-network is a controller with subcommands menu/dns/qr/status:
# DNS-provider management (Cloudflare/Google/DHCP/Custom, untouched by
# these PRs), a Wi-Fi QR generator, a fuzzel menu, and a one-word status
# ("wifi" or "ethernet"). It has no wifi scan/connect, no ethernet
# connect/dhcp/static, and no bluetooth at all. The new CLIs are new
# files (hexciri-network-wifi, hexciri-network-ethernet, hexciri-bluetooth),
# not edits to hexciri-network, so nothing is duplicated and nothing is
# clobbered. The one-word `hexciri-network status` stays as-is.
# Delegations land on files the fork already ships: wifi band/password call
# hexciri-network-band / hexciri-network-password, bluetooth power calls
# hexciri-bluetooth-power (same-dir lookup), all renamed by the installer's
# map. HEXCIRI_NET_CLASS_PATH / HEXCIRI_BLUETOOTH_POWER_WAIT_SECONDS follow
# the same map. HEXCIRI_PATH is required (os.environ["HEXCIRI_PATH"], no
# fallback), exactly as upstream requires OMARCHY_PATH and as other fork
# scripts already do.
#
# Deliberate non-rename: wifi.py's local helper is still called
# omarchy_bin(). No rule in the installer's rename map matches it (the
# rules cover omarchy-, "omarchy ", OMARCHY_, and the like; an underscore
# identifier matches none), so a file that had gone through the pipeline
# would keep that name. It is a local function, not a file, path, or CLI
# name, so it stays. The # omarchy: metadata keys likewise stay, as they
# do in every other renamed fork bin (the router parses omarchy:group=).
#
# Skipped from the PRs, deliberately:
# - shell/plugins/panels/network/{Model.js,Panel.qml} and
#   shell/plugins/panels/bluetooth/Panel.qml (panel wiring; the fork's
#   panels are the stock ones and panel wiring is N/A for this patch --
#   the CLIs work standalone via the router and the panels keep calling
#   hexciri-network-status/band/password as before).
# - #20351 Wi-Fi autoconnect fix (not portable alone: it rides on #20331's
#   nmcli-connection-edit flow; excluded per the task).
# - test/shell.d/network-test.sh, bluetooth-test.sh (test/ is not in
#   FORK_OUT; no existing patch touches tests). Sim runs --json/usage
#   smoke checks and a py_compile parse check instead; see the README.
#
# Standalone: bash v2/patches/41-network-bluetooth-clis.sh [FORK_OUT]
#   FORK_OUT may also come from the environment. HEXCIRI_REPO_ROOT,
#   INSTALLER_DIR, FORK_LOG and _patch_log are honored from the
#   environment when set (the installer and apply.sh export them);
#   defaults below match a checkout layout. Idempotent: re-running on
#   an already-patched tree prints "already present, skipping" and
#   changes nothing. A file missing from FORK_OUT is warned and skipped
#   (partial sim trees); a present file whose anchor is not found dies,
#   so a real upstream drift fails loud instead of shipping unpatched.
#   A new file that already exists with different content dies rather
#   than clobbering it.
#
# Syntax check note: the new files are Python, the edited router is bash,
# so the end-of-patch check is a compile() parse check on the three CLIs
# (no bytecode written, nothing executed) plus bash -n on bin/hexciri.
# bash -n would fail on the Python files by construction and is
# deliberately not used there.

set -euo pipefail
FORK_OUT="${1:-${FORK_OUT:-}}"
[ -n "$FORK_OUT" ] || { printf 'ERROR: %s\n' "41-network-bluetooth-clis.sh: FORK_OUT is required (pass it as \$1 or set FORK_OUT)" >&2; exit 1; }
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
CHANGED=0
# Write a new file from stdin; idempotent via content compare, dies rather
# than clobbering a different existing file. $1 = FORK_OUT-relative path,
# $2 = mode (755 for bin/, 644 for config/drop-ins).
install_new_file() {
  local rel="$1" mode="$2" dest tmp
  dest="$FORK_OUT/$rel"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ]; then
    if cmp -s "$tmp" "$dest"; then
      printf '%s: already present, skipping\n' "$rel" >>"$_patch_log"
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
    die "$rel already exists with different content, refusing to clobber it"
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod "$mode" "$dest"
  CHANGED=$((CHANGED + 1))
  printf 'patched: created %s\n' "$rel" >>"$_patch_log"
}
# --- Network wifi/ethernet + bluetooth CLIs, omarchy PRs #20331/#20332 ---
install_new_file "bin/hexciri-network-ethernet" 755 <<'HEXCIRI_EOF_NET_ETH'
#!/usr/bin/python3

# omarchy:summary=Control wired Ethernet interfaces, profiles, DHCP, and static IPv4
# omarchy:group=network
# omarchy:subcommand=status [--json] — Show Ethernet interfaces, carrier, link speed, and IP details
# omarchy:subcommand=list [--json] — List saved Ethernet connection profiles
# omarchy:subcommand=connect [interface|profile] [--json] — Connect an Ethernet interface or profile
# omarchy:subcommand=disconnect [interface] [--json] — Disconnect an Ethernet interface
# omarchy:subcommand=dhcp [interface|profile] [--json] — Configure an Ethernet connection for automatic DHCP
# omarchy:subcommand=static <ip/prefix> --gateway <gw> [--dns <ip,...>] [interface|profile] — Set a static IPv4 address
# omarchy:subcommand=forget <profile|uuid> [--json] — Delete saved Ethernet connection profile(s)
# omarchy:examples=hexciri network ethernet status | hexciri network ethernet connect | hexciri network ethernet static 192.168.1.50/24 --gateway 192.168.1.1 --dns 1.1.1.1 | hexciri network ethernet dhcp

"""Human- and agent-friendly CLI for wired Ethernet management via NetworkManager."""

import ipaddress
import json
import os
import subprocess
import sys

USAGE = """\
Usage: hexciri network ethernet [--json] <command> [args...]

  status [interface] [--json]           Show Ethernet interfaces, carrier, speed, and IP
  list [--json]                         List saved Ethernet connection profiles
  connect [interface|profile] [--json]  Connect an Ethernet interface or profile
  disconnect [interface] [--json]       Disconnect an Ethernet interface
  dhcp [interface|profile] [--json]     Switch an Ethernet connection to DHCP (IPv4)
  static <ip/prefix> --gateway <gw> [--dns <ip,...>] [interface|profile] [--json]
                                        Configure a static IPv4 address and apply
  forget <profile|uuid> [--json]        Delete saved Ethernet profile(s)
"""


class UsageError(Exception):
    pass


def c_env() -> dict[str, str]:
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    return env


def run_cmd(args: list[str], *, check: bool = False) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=c_env(),
    )
    if check and proc.returncode != 0:
        msg = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(msg or f"{args[0]} exited with status {proc.returncode}")
    return proc


def nm_split_escaped(line: str) -> list[str]:
    fields: list[str] = []
    cur: list[str] = []
    esc = False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if esc:
        cur.append("\\")
    fields.append("".join(cur))
    return fields


def nm_parse_kv(output: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for line in output.splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        key = key.strip()
        val = val.strip()
        if not val or val == "--":
            continue
        result.setdefault(key, []).append(val)
    return result


def sysfs_read(iface: str, attr: str) -> str:
    net_root = os.environ.get("HEXCIRI_NET_CLASS_PATH", "/sys/class/net")
    try:
        with open(os.path.join(net_root, iface, attr), "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def default_route_interface() -> str:
    proc = run_cmd(["ip", "-j", "route", "get", "1.1.1.1"])
    if proc.returncode != 0:
        return ""
    try:
        routes = json.loads(proc.stdout)
        if routes and isinstance(routes, list):
            return str(routes[0].get("dev") or "")
    except (ValueError, TypeError):
        pass
    return ""


IDLE_DEVICE_STATES = {"disconnected", "unavailable", "unmanaged"}


def ethernet_devices() -> list[dict]:
    proc = run_cmd(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"], check=True)
    default_dev = default_route_interface()
    devices: list[dict] = []
    for line in proc.stdout.splitlines():
        parts = nm_split_escaped(line)
        if len(parts) < 4:
            continue
        dev, dev_type, state, conn = parts[0], parts[1], parts[2], parts[3]
        if dev_type != "ethernet" or state == "unmanaged":
            continue
        kv = nm_parse_kv(
            run_cmd(
                [
                    "nmcli",
                    "-e",
                    "no",
                    "-t",
                    "-f",
                    "GENERAL.HWADDR,GENERAL.CON-UUID,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,WIRED-PROPERTIES.CARRIER",
                    "device",
                    "show",
                    dev,
                ],
                check=True,
            ).stdout
        )
        con_uuid = (kv.get("GENERAL.CON-UUID") or [""])[0]
        mac = (kv.get("GENERAL.HWADDR") or [""])[0]
        ip_cidr = (kv.get("IP4.ADDRESS[1]") or [""])[0]
        ip_addr = ""
        prefix: int | None = None
        if "/" in ip_cidr:
            ip_addr, pref_s = ip_cidr.split("/", 1)
            prefix = int(pref_s) if pref_s.isdigit() else None
        elif ip_cidr:
            ip_addr = ip_cidr
        gateway = (kv.get("IP4.GATEWAY") or [""])[0]
        dns = [v for k, vals in kv.items() if k.startswith("IP4.DNS[") for v in vals]

        carrier_raw = sysfs_read(dev, "carrier")
        if carrier_raw in ("0", "1"):
            carrier = carrier_raw == "1"
        else:
            carrier = (kv.get("WIRED-PROPERTIES.CARRIER") or [""])[0].lower() == "on"

        speed_raw = sysfs_read(dev, "speed")
        speed_mbps = int(speed_raw) if speed_raw.isdigit() and int(speed_raw) > 0 else None
        duplex = sysfs_read(dev, "duplex")
        if duplex not in ("full", "half"):
            duplex = ""

        devices.append(
            {
                "device": dev,
                "state": state,
                "connected": state == "connected",
                "carrier": carrier,
                "connection": "" if conn in ("", "--") else conn,
                "uuid": con_uuid,
                "speed_mbps": speed_mbps,
                "duplex": duplex,
                "ip": ip_addr,
                "prefix": prefix,
                "gateway": gateway,
                "dns": dns,
                "mac": mac,
                "default_route": dev == default_dev,
            }
        )
    return devices


def saved_ethernet_profiles() -> list[dict]:
    proc = run_cmd(
        ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,AUTOCONNECT", "connection", "show"],
        check=True,
    )
    profiles: list[dict] = []
    for line in proc.stdout.splitlines():
        parts = nm_split_escaped(line)
        if len(parts) < 5:
            continue
        name, uid, ctype, dev, auto = parts[0], parts[1], parts[2], parts[3], parts[4]
        if ctype != "802-3-ethernet":
            continue
        meta_proc = run_cmd(
            [
                "nmcli",
                "-e",
                "no",
                "-g",
                "ipv4.method,connection.interface-name",
                "connection",
                "show",
                "uuid",
                uid,
            ],
            check=True,
        )
        meta_lines = meta_proc.stdout.splitlines()
        method = (meta_lines[0].strip() if len(meta_lines) >= 1 else "") or "auto"
        bound_iface = meta_lines[1].strip() if len(meta_lines) >= 2 else ""
        if bound_iface == "--":
            bound_iface = ""
        profiles.append(
            {
                "name": name,
                "uuid": uid,
                "device": "" if dev in ("", "--") else dev,
                "interface": bound_iface,
                "active": dev not in ("", "--"),
                "autoconnect": auto.lower() == "yes",
                "method": method,
            }
        )
    return profiles


def pick_ethernet_device(preferred: str | None = None) -> dict:
    devs = ethernet_devices()
    if preferred:
        for d in devs:
            if d["device"] == preferred:
                return d
        raise RuntimeError(f"Ethernet interface '{preferred}' not found")
    if not devs:
        raise RuntimeError("no Ethernet interface found")
    for d in devs:
        if d["connected"]:
            return d
    for d in devs:
        if d["carrier"]:
            return d
    return devs[0]


def profile_for_device(dev: dict, profiles: list[dict]) -> dict | None:
    if dev["uuid"]:
        for p in profiles:
            if p["uuid"] == dev["uuid"]:
                return p
    for p in profiles:
        if p["device"] == dev["device"] or p["interface"] == dev["device"]:
            return p
    return None


def resolve_profile_for_target(target: str | None) -> tuple[dict, str | None]:
    """Resolve an optional interface/profile/UUID target to (profile_dict, iface_or_None)."""
    profiles = saved_ethernet_profiles()
    devs = ethernet_devices()

    if target:
        for p in profiles:
            if p["uuid"] == target or p["name"] == target:
                return p, p["device"] or p["interface"] or None
        for d in devs:
            if d["device"] == target:
                matched = profile_for_device(d, profiles)
                if matched:
                    return matched, d["device"]
                raise RuntimeError(
                    f"no saved Ethernet profile for '{target}'; connect it first or pass a profile name"
                )
        raise RuntimeError(f"no Ethernet interface or profile matching '{target}'")

    dev = pick_ethernet_device()
    matched = profile_for_device(dev, profiles)
    if matched:
        return matched, dev["device"]
    raise RuntimeError(
        f"no saved Ethernet profile for '{dev['device']}'; connect it first or pass a profile name"
    )


def format_speed(speed_mbps: int | None, duplex: str) -> str:
    if not speed_mbps:
        return ""
    if speed_mbps >= 1000 and speed_mbps % 1000 == 0:
        base = f"{speed_mbps // 1000} Gbps"
    elif speed_mbps >= 1000:
        base = f"{speed_mbps / 1000:.1f} Gbps"
    else:
        base = f"{speed_mbps} Mbps"
    return f"{base} ({duplex})" if duplex else base


def print_ethernet_status(devs: list[dict], as_json: bool) -> None:
    if as_json:
        print(json.dumps({"interfaces": devs}))
        return
    if not devs:
        print("Ethernet:    no wired interfaces found")
        return
    for idx, d in enumerate(devs):
        if idx > 0:
            print()
        print(f"Interface:   {d['device']}")
        print(f"State:       {d['state']}")
        print(f"Carrier:     {'yes' if d['carrier'] else 'no'}")
        if d["connection"]:
            print(f"Profile:     {d['connection']}")
        speed = format_speed(d["speed_mbps"], d["duplex"])
        if speed:
            print(f"Link:        {speed}")
        if d["ip"]:
            addr = f"{d['ip']}/{d['prefix']}" if d["prefix"] is not None else d["ip"]
            print(f"IPv4:        {addr}")
        if d["gateway"]:
            print(f"Gateway:     {d['gateway']}")
        if d["dns"]:
            print(f"DNS:         {', '.join(d['dns'])}")


def print_ethernet_profiles(profiles: list[dict], as_json: bool) -> None:
    if as_json:
        print(json.dumps(profiles))
        return
    if not profiles:
        print("No saved Ethernet profiles.")
        return
    print(f"{'':2s} {'NAME':28s} {'METHOD':8s} {'AUTO':5s}  UUID")
    for p in profiles:
        mark = "*" if p["active"] else " "
        auto = "yes" if p["autoconnect"] else "no"
        print(f"{mark:2s} {p['name'][:28]:28s} {p['method']:8s} {auto:5s}  {p['uuid']}")


def strip_double_dash(args: list[str]) -> list[str]:
    if args and args[0] == "--":
        return args[1:]
    return args


def cmd_connect(args: list[str], as_json: bool) -> int:
    pos = strip_double_dash(args)
    if len(pos) > 1:
        raise UsageError("Usage: hexciri network ethernet connect [interface|profile]")
    target = pos[0] if pos else None
    devs = ethernet_devices()
    profiles = saved_ethernet_profiles()

    if target:
        matched_dev = next((d for d in devs if d["device"] == target), None)
        if matched_dev:
            run_cmd(["nmcli", "device", "connect", matched_dev["device"]], check=True)
            chosen_iface = matched_dev["device"]
        else:
            matched_prof = next((p for p in profiles if p["uuid"] == target or p["name"] == target), None)
            if not matched_prof:
                raise RuntimeError(f"no Ethernet interface or profile matching '{target}'")
            run_cmd(["nmcli", "connection", "up", "uuid", matched_prof["uuid"]], check=True)
            chosen_iface = matched_prof["device"] or None
    else:
        dev = pick_ethernet_device()
        run_cmd(["nmcli", "device", "connect", dev["device"]], check=True)
        chosen_iface = dev["device"]

    updated = ethernet_devices()
    if chosen_iface:
        updated = [d for d in updated if d["device"] == chosen_iface] or updated
    if as_json:
        print(json.dumps({"interfaces": updated}))
    else:
        for d in updated:
            addr = f" ({d['ip']})" if d["ip"] else ""
            print(f"Connected {d['device']}{addr}")
    return 0


def cmd_disconnect(args: list[str], as_json: bool) -> int:
    pos = strip_double_dash(args)
    if len(pos) > 1:
        raise UsageError("Usage: hexciri network ethernet disconnect [interface]")
    dev = pick_ethernet_device(pos[0] if pos else None)
    if dev["state"] not in IDLE_DEVICE_STATES:
        run_cmd(["nmcli", "device", "disconnect", dev["device"]], check=True)
    updated = [d for d in ethernet_devices() if d["device"] == dev["device"]]
    if as_json:
        print(json.dumps({"interfaces": updated}))
    else:
        print(f"Disconnected {dev['device']}")
    return 0


def cmd_dhcp(args: list[str], as_json: bool) -> int:
    pos = strip_double_dash(args)
    if len(pos) > 1:
        raise UsageError("Usage: hexciri network ethernet dhcp [interface|profile]")
    prof, iface = resolve_profile_for_target(pos[0] if pos else None)
    run_cmd(
        [
            "nmcli",
            "connection",
            "modify",
            "uuid",
            prof["uuid"],
            "ipv4.method",
            "auto",
            "ipv4.addresses",
            "",
            "ipv4.gateway",
            "",
        ],
        check=True,
    )
    up_cmd = ["nmcli", "connection", "up", "uuid", prof["uuid"]]
    if iface:
        up_cmd += ["ifname", iface]
    run_cmd(up_cmd, check=True)
    updated = ethernet_devices()
    if iface:
        updated = [d for d in updated if d["device"] == iface] or updated
    if as_json:
        print(json.dumps({"profile": prof["name"], "method": "auto", "interfaces": updated}))
    else:
        print(f"Switched '{prof['name']}' to DHCP")
    return 0


def cmd_static(args: list[str], as_json: bool) -> int:
    cidr: str | None = None
    gateway: str | None = None
    dns_list: list[str] = []
    dns_specified = False
    target: str | None = None
    after_dash = False

    i = 0
    while i < len(args):
        tok = args[i]
        if not after_dash and tok == "--":
            after_dash = True
            i += 1
        elif not after_dash and tok == "--gateway":
            if i + 1 >= len(args):
                raise UsageError("--gateway requires an IPv4 address")
            gateway = args[i + 1]
            i += 2
        elif not after_dash and tok == "--dns":
            if i + 1 >= len(args):
                raise UsageError("--dns requires comma-separated IPv4 address(es)")
            dns_specified = True
            dns_list.extend(x.strip() for x in args[i + 1].split(",") if x.strip())
            i += 2
        elif not after_dash and tok.startswith("-"):
            raise UsageError(f"unknown option '{tok}'")
        elif cidr is None:
            cidr = tok
            i += 1
        elif target is None:
            target = tok
            i += 1
        else:
            raise UsageError(f"unexpected argument '{tok}'")

    if not cidr or not gateway:
        raise UsageError(
            "Usage: hexciri network ethernet static <ip/prefix> --gateway <gw> [--dns <ip,...>] [interface|profile]"
        )

    if "/" not in cidr:
        raise UsageError(f"invalid IPv4 address '{cidr}' (expected CIDR like 192.168.1.50/24)")
    try:
        iface_net = ipaddress.IPv4Interface(cidr)
    except ValueError as exc:
        raise UsageError(f"invalid IPv4 CIDR '{cidr}': {exc}") from exc
    if iface_net.network.prefixlen == 0:
        raise UsageError(f"invalid prefix length in '{cidr}'")
    if iface_net.network.prefixlen < 31 and iface_net.ip in (
        iface_net.network.network_address,
        iface_net.network.broadcast_address,
    ):
        raise UsageError(f"'{cidr}' cannot be the network or broadcast address")

    try:
        gw_ip = ipaddress.IPv4Address(gateway)
    except ValueError as exc:
        raise UsageError(f"invalid IPv4 gateway '{gateway}': {exc}") from exc

    validated_dns: list[str] = []
    for entry in dns_list:
        try:
            validated_dns.append(str(ipaddress.IPv4Address(entry)))
        except ValueError as exc:
            raise UsageError(f"invalid IPv4 DNS address '{entry}': {exc}") from exc

    prof, iface = resolve_profile_for_target(target)
    mod_cmd = [
        "nmcli",
        "connection",
        "modify",
        "uuid",
        prof["uuid"],
        "ipv4.method",
        "manual",
        "ipv4.addresses",
        str(iface_net),
        "ipv4.gateway",
        str(gw_ip),
    ]
    if dns_specified:
        if validated_dns:
            mod_cmd += ["ipv4.dns", " ".join(validated_dns), "ipv4.ignore-auto-dns", "yes"]
        else:
            mod_cmd += ["ipv4.dns", "", "ipv4.ignore-auto-dns", "no"]
    run_cmd(mod_cmd, check=True)

    up_cmd = ["nmcli", "connection", "up", "uuid", prof["uuid"]]
    if iface:
        up_cmd += ["ifname", iface]
    run_cmd(up_cmd, check=True)

    updated = ethernet_devices()
    if iface:
        updated = [d for d in updated if d["device"] == iface] or updated
    if as_json:
        print(
            json.dumps(
                {
                    "profile": prof["name"],
                    "method": "manual",
                    "address": str(iface_net),
                    "gateway": str(gw_ip),
                    "dns": validated_dns,
                    "interfaces": updated,
                }
            )
        )
    else:
        print(f"Configured '{prof['name']}' with static IPv4 {iface_net} via {gw_ip}")
    return 0


def cmd_forget(args: list[str], as_json: bool) -> int:
    pos = strip_double_dash(args)
    if len(pos) != 1:
        raise UsageError("Usage: hexciri network ethernet forget <profile|uuid>")
    target = pos[0]
    matches = [p for p in saved_ethernet_profiles() if p["uuid"] == target or p["name"] == target]
    if not matches:
        raise RuntimeError(f"no saved Ethernet profile matching '{target}'")
    deleted = []
    for p in matches:
        run_cmd(["nmcli", "connection", "delete", "uuid", p["uuid"]], check=True)
        deleted.append({"name": p["name"], "uuid": p["uuid"]})
    if as_json:
        print(json.dumps({"forgotten": deleted}))
    else:
        for p in deleted:
            print(f"Forgot Ethernet profile: {p['name']} ({p['uuid']})")
    return 0


def parse_global_flags(argv: list[str]) -> tuple[bool, list[str]]:
    as_json = False
    rest: list[str] = []
    after_dash = False
    skip_next = False
    value_flags = {"--gateway", "--dns"}
    for arg in argv:
        if skip_next:
            rest.append(arg)
            skip_next = False
            continue
        if not after_dash and arg == "--":
            after_dash = True
            rest.append(arg)
            continue
        if not after_dash and arg in value_flags:
            rest.append(arg)
            skip_next = True
            continue
        if not after_dash and arg == "--json":
            as_json = True
            continue
        rest.append(arg)
    return as_json, rest


def main(argv: list[str]) -> int:
    if any(a in ("-h", "--help") for a in argv[:2]) and "--" not in argv[:2]:
        print(USAGE, end="")
        return 0

    as_json, args = parse_global_flags(argv)
    cmd = args[0] if args else "status"
    rest = args[1:]

    if cmd == "status":
        pos = strip_double_dash(rest)
        if len(pos) > 1:
            raise UsageError("Usage: hexciri network ethernet status [interface]")
        devs = ethernet_devices()
        if pos:
            devs = [d for d in devs if d["device"] == pos[0]]
            if not devs:
                raise RuntimeError(f"Ethernet interface '{pos[0]}' not found")
        print_ethernet_status(devs, as_json)
        return 0

    if cmd == "list":
        if strip_double_dash(rest):
            raise UsageError("Usage: hexciri network ethernet list")
        print_ethernet_profiles(saved_ethernet_profiles(), as_json)
        return 0

    if cmd == "connect":
        return cmd_connect(rest, as_json)

    if cmd == "disconnect":
        return cmd_disconnect(rest, as_json)

    if cmd == "dhcp":
        return cmd_dhcp(rest, as_json)

    if cmd == "static":
        return cmd_static(rest, as_json)

    if cmd == "forget":
        return cmd_forget(rest, as_json)

    raise UsageError(f"unknown command '{cmd}'\n\n{USAGE}")


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)
    except UsageError as exc:
        sys.stderr.write(f"hexciri-network-ethernet: {exc}\n")
        raise SystemExit(2)
    except (RuntimeError, OSError) as exc:
        sys.stderr.write(f"hexciri-network-ethernet: {exc}\n")
        raise SystemExit(1)
HEXCIRI_EOF_NET_ETH
install_new_file "bin/hexciri-network-wifi" 755 <<'HEXCIRI_EOF_NET_WIFI'
#!/usr/bin/python3

# omarchy:summary=Control Wi-Fi radio, networks, connections, and band
# omarchy:group=network
# omarchy:subcommand=status [--json] — Show Wi-Fi radio, active connection, signal, band, and IP details
# omarchy:subcommand=on|off|toggle [--json] — Turn the Wi-Fi radio on, off, or toggle it
# omarchy:subcommand=list [--rescan] [--known] [--json] — List nearby Wi-Fi networks or saved profiles
# omarchy:subcommand=scan [--json] — Rescan and list nearby Wi-Fi networks
# omarchy:subcommand=connect <ssid> [options] — Connect to a Wi-Fi network (known, open, PSK, or enterprise)
# omarchy:subcommand=disconnect [interface] — Disconnect the active Wi-Fi interface
# omarchy:subcommand=forget <ssid|uuid> — Delete saved Wi-Fi connection profile(s)
# omarchy:subcommand=password [interface] — Print the active Wi-Fi connection's password
# omarchy:subcommand=band [auto|2.4|5|6] [--json] — Show or pin the Wi-Fi frequency band
# omarchy:examples=hexciri network wifi status | hexciri network wifi list --rescan | hexciri network wifi connect "MyWiFi" --password-stdin | hexciri network wifi band 5

"""Human- and agent-friendly CLI for Wi-Fi management via NetworkManager."""

import getpass
import json
import os
import re
import signal
import subprocess
import sys
import uuid as uuid_mod

USAGE = """\
Usage: hexciri network wifi [--json] <command> [args...]

  status [--json]                       Show Wi-Fi radio, link, signal, band, and IP
  on | off | toggle [--json]            Turn the Wi-Fi radio on, off, or toggle it
  list [--rescan] [--known] [--json]    List nearby networks (or saved profiles with --known)
  scan [--json]                         Rescan and list nearby Wi-Fi networks
  connect <ssid> [options]              Connect to a Wi-Fi network
    --password <secret>                   Passphrase (visible in /proc; prefer --password-stdin)
    --password-stdin                      Read passphrase from stdin (recommended for scripts/agents)
    --identity <user>                     Username for WPA-Enterprise (PEAP/MSCHAPv2)
    --hidden                              Connect to a hidden SSID
    --interface <dev>                     Use a specific Wi-Fi interface
  disconnect [interface] [--json]       Disconnect the active Wi-Fi interface
  forget [--ssid] <ssid|uuid> [--json]  Delete saved Wi-Fi profile(s) matching SSID or UUID
  password [interface]                  Print the active Wi-Fi connection's password
  band [auto|2.4|5|6] [--json]          Show or pin the Wi-Fi frequency band
"""


class UsageError(Exception):
    pass


class CancelledError(BaseException):
    pass


def _handle_sigterm(_signum: int, _frame: object) -> None:
    raise CancelledError("cancelled")


def c_env() -> dict[str, str]:
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    return env


def run_cmd(
    args: list[str],
    *,
    input_text: str | None = None,
    check: bool = False,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        proc = subprocess.run(
            args,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=c_env(),
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"command timed out: {' '.join(args)}") from exc
    if check and proc.returncode != 0:
        msg = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(msg or f"{args[0]} exited with status {proc.returncode}")
    return proc


def cleanup_cancelled_connection(
    con_uuid: str,
    *,
    delete_profile: bool = False,
    restore_key_mgmt: str | None = None,
) -> None:
    """Cancel an in-progress activation and roll back profile changes without interruption."""
    prev_handler = signal.signal(signal.SIGTERM, signal.SIG_IGN)
    try:
        run_cmd(["nmcli", "connection", "down", "uuid", con_uuid], timeout=3)
        if delete_profile:
            run_cmd(["nmcli", "connection", "delete", "uuid", con_uuid], timeout=3)
        elif restore_key_mgmt:
            run_cmd(
                ["nmcli", "connection", "modify", "uuid", con_uuid, "wifi-sec.key-mgmt", restore_key_mgmt],
                timeout=3,
            )
    except Exception:
        pass
    finally:
        signal.signal(signal.SIGTERM, prev_handler)


def nm_split_escaped(line: str) -> list[str]:
    """Split an nmcli `-t` line on unescaped `:` and unescape `\\:` / `\\\\`."""
    fields: list[str] = []
    cur: list[str] = []
    esc = False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if esc:
        cur.append("\\")
    fields.append("".join(cur))
    return fields


def nm_parse_kv(output: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for line in output.splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        key = key.strip()
        val = val.strip()
        if not val or val == "--":
            continue
        result.setdefault(key, []).append(val)
    return result


def band_for_freq(freq_raw: str) -> str:
    match = re.match(r"^\s*(\d+)", str(freq_raw or ""))
    if not match:
        return ""
    mhz = int(match.group(1))
    if 2400 <= mhz < 2500:
        return "2.4"
    if 4900 <= mhz < 5925:
        return "5"
    if 5925 <= mhz < 7125:
        return "6"
    return ""


def normalize_security(raw: str) -> str:
    sec = (raw or "").strip()
    if not sec or sec == "--":
        return "open"
    return sec


IDLE_DEVICE_STATES = {"disconnected", "unavailable", "unmanaged"}


def radio_enabled() -> bool:
    proc = run_cmd(["nmcli", "radio", "wifi"], check=True)
    return proc.stdout.strip().lower() == "enabled"


def wifi_devices() -> list[dict]:
    proc = run_cmd(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"], check=True)
    devices: list[dict] = []
    for line in proc.stdout.splitlines():
        parts = nm_split_escaped(line)
        if len(parts) < 4:
            continue
        dev, dev_type, state, conn = parts[0], parts[1], parts[2], parts[3]
        if dev_type != "wifi":
            continue
        devices.append(
            {
                "device": dev,
                "state": state,
                "connection": "" if conn in ("", "--") else conn,
            }
        )
    return devices


def pick_wifi_device(preferred: str | None = None) -> dict | None:
    devs = wifi_devices()
    if preferred:
        for d in devs:
            if d["device"] == preferred:
                return d
        raise RuntimeError(f"Wi-Fi interface '{preferred}' not found")
    for d in devs:
        if d["state"] == "connected":
            return d
    return devs[0] if devs else None


def saved_wifi_profiles() -> list[dict]:
    proc = run_cmd(
        ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,AUTOCONNECT", "connection", "show"],
        check=True,
    )
    profiles: list[dict] = []
    for line in proc.stdout.splitlines():
        parts = nm_split_escaped(line)
        if len(parts) < 5:
            continue
        name, uid, ctype, dev, auto = parts[0], parts[1], parts[2], parts[3], parts[4]
        if ctype != "802-11-wireless":
            continue
        meta_lines = run_cmd(
            [
                "nmcli",
                "-e",
                "no",
                "-g",
                "802-11-wireless.ssid,connection.interface-name",
                "connection",
                "show",
                "uuid",
                uid,
            ]
        ).stdout.splitlines()
        ssid = (meta_lines[0].strip() if len(meta_lines) >= 1 else "") or name
        bound_iface = meta_lines[1].strip() if len(meta_lines) >= 2 else ""
        if bound_iface == "--":
            bound_iface = ""
        profiles.append(
            {
                "name": name,
                "ssid": ssid,
                "uuid": uid,
                "device": "" if dev in ("", "--") else dev,
                "interface": bound_iface,
                "active": dev not in ("", "--"),
                "autoconnect": auto.lower() == "yes",
            }
        )
    return profiles


def matching_wifi_profiles(ssid: str, target_iface: str) -> list[dict]:
    """Return saved profiles for `ssid` compatible with `target_iface`, exact adapter match first."""
    compatible = [
        p
        for p in saved_wifi_profiles()
        if p["ssid"] == ssid and p["interface"] in ("", target_iface)
    ]
    compatible.sort(key=lambda p: (p["interface"] != target_iface, not p["active"]))
    return compatible


def decode_iw_ssid(raw: str) -> str:
    """Decode `iw` \\xNN byte escapes into UTF-8 text."""
    if "\\x" not in raw:
        return raw
    out = bytearray()
    i = 0
    n = len(raw)
    while i < n:
        if raw[i : i + 2] == "\\x" and i + 4 <= n:
            hex_part = raw[i + 2 : i + 4]
            if all(c in "0123456789abcdefABCDEF" for c in hex_part):
                out.append(int(hex_part, 16))
                i += 4
                continue
        out.extend(raw[i].encode("utf-8"))
        i += 1
    try:
        return out.decode("utf-8")
    except UnicodeDecodeError:
        return raw


def read_iw_link(device: str) -> dict:
    proc = run_cmd(["iw", "dev", device, "link"])
    info = {"ssid": "", "freq_mhz": None, "signal_dbm": None, "bitrate": ""}
    if proc.returncode != 0:
        return info
    for line in proc.stdout.splitlines():
        s = line.strip()
        if s.startswith("SSID:"):
            info["ssid"] = decode_iw_ssid(s.split("SSID:", 1)[1].strip())
        elif s.startswith("freq:"):
            m = re.match(r"freq:\s*(\d+)", s)
            if m:
                info["freq_mhz"] = int(m.group(1))
        elif s.startswith("signal:"):
            m = re.match(r"signal:\s*(-?\d+)", s)
            if m:
                info["signal_dbm"] = int(m.group(1))
        elif s.startswith("tx bitrate:"):
            m = re.match(r"tx bitrate:\s*([0-9.]+\s+\S+)", s)
            if m:
                info["bitrate"] = m.group(1)
    return info


def band_from_nm(raw: str) -> str:
    return {"bg": "2.4", "a": "5", "6GHz": "6"}.get(raw.strip(), "auto")


def read_band_info_for(iface: str, ssid: str, freq_mhz: int | None, con_uuid: str) -> dict:
    current = band_for_freq(str(freq_mhz)) if freq_mhz else ""
    selected = "auto"
    if con_uuid:
        sel_proc = run_cmd(
            ["nmcli", "-e", "no", "-g", "802-11-wireless.band", "connection", "show", "uuid", con_uuid]
        )
        if sel_proc.returncode == 0:
            selected = band_from_nm(sel_proc.stdout)

    bands: set[str] = set()
    if current:
        bands.add(current)
    if ssid:
        scan_proc = run_cmd(
            ["nmcli", "-t", "-f", "FREQ,SSID", "device", "wifi", "list", "ifname", iface, "--rescan", "no"]
        )
        if scan_proc.returncode == 0:
            for line in scan_proc.stdout.splitlines():
                parts = nm_split_escaped(line)
                if len(parts) >= 2 and parts[1] == ssid:
                    b = band_for_freq(parts[0])
                    if b:
                        bands.add(b)
    available = sorted(bands, key=lambda b: float(b))
    return {"current": current, "selected": selected, "available": available}


def omarchy_bin(name: str) -> str:
    return os.path.join(os.environ["HEXCIRI_PATH"], "bin", name)


def read_band_info() -> dict:
    proc = run_cmd([omarchy_bin("hexciri-network-band")])
    info = {"current": "", "selected": "auto", "available": []}
    if proc.returncode != 0:
        return info
    for line in proc.stdout.splitlines():
        if "\t" not in line:
            continue
        k, v = line.split("\t", 1)
        v = v.strip()
        if k == "band":
            info["current"] = v
        elif k == "selected":
            info["selected"] = v or "auto"
        elif k == "available":
            info["available"] = [tok for tok in v.split() if tok]
    return info


def active_ap_signal(device: str) -> int | None:
    proc = run_cmd(
        ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "ifname", device, "--rescan", "no"]
    )
    for line in proc.stdout.splitlines():
        parts = nm_split_escaped(line)
        if len(parts) >= 2 and parts[0] == "*" and parts[1].isdigit():
            return int(parts[1])
    return None


def read_wifi_status(preferred_iface: str | None = None) -> dict:
    enabled = radio_enabled()
    dev = pick_wifi_device(preferred_iface)
    if dev is None:
        return {
            "radio": "on" if enabled else "off",
            "available": False,
            "connected": False,
            "state": "unavailable",
            "device": "",
            "ssid": "",
            "connection": "",
            "uuid": "",
            "signal": None,
            "signal_dbm": None,
            "freq_mhz": None,
            "band": "",
            "band_selected": "auto",
            "band_available": [],
            "bitrate": "",
            "ip": "",
            "prefix": None,
            "gateway": "",
            "dns": [],
            "mac": "",
        }

    iface = dev["device"]
    connected = enabled and dev["state"] == "connected"
    kv = nm_parse_kv(
        run_cmd(
            [
                "nmcli",
                "-e",
                "no",
                "-t",
                "-f",
                "GENERAL.HWADDR,GENERAL.CON-UUID,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS",
                "device",
                "show",
                iface,
            ],
            check=True,
        ).stdout
    )
    mac = (kv.get("GENERAL.HWADDR") or [""])[0]
    con_uuid = (kv.get("GENERAL.CON-UUID") or [""])[0]
    ip_cidr = (kv.get("IP4.ADDRESS[1]") or [""])[0]
    ip_addr = ""
    prefix: int | None = None
    if "/" in ip_cidr:
        ip_addr, pref_s = ip_cidr.split("/", 1)
        prefix = int(pref_s) if pref_s.isdigit() else None
    elif ip_cidr:
        ip_addr = ip_cidr
    gateway = (kv.get("IP4.GATEWAY") or [""])[0]
    dns = [v for k, vals in kv.items() if k.startswith("IP4.DNS[") for v in vals]

    iw = read_iw_link(iface) if connected else {"ssid": "", "freq_mhz": None, "signal_dbm": None, "bitrate": ""}
    sig = active_ap_signal(iface) if connected else None
    ssid = iw["ssid"] or dev["connection"]
    band_info = (
        read_band_info_for(iface, ssid, iw["freq_mhz"], con_uuid)
        if connected
        else {"current": "", "selected": "auto", "available": []}
    )
    band = band_info["current"]

    return {
        "radio": "on" if enabled else "off",
        "available": True,
        "connected": connected,
        "state": "disabled" if not enabled else dev["state"],
        "device": iface,
        "ssid": iw["ssid"] or dev["connection"],
        "connection": dev["connection"],
        "uuid": con_uuid,
        "signal": sig,
        "signal_dbm": iw["signal_dbm"],
        "freq_mhz": iw["freq_mhz"],
        "band": band,
        "band_selected": band_info["selected"],
        "band_available": band_info["available"],
        "bitrate": iw["bitrate"],
        "ip": ip_addr,
        "prefix": prefix,
        "gateway": gateway,
        "dns": dns,
        "mac": mac,
    }


def print_wifi_status(st: dict, as_json: bool) -> None:
    if as_json:
        print(json.dumps(st))
        return
    if not st["available"]:
        print("Wi-Fi:       unavailable (no Wi-Fi interface found)")
        return
    print(f"Radio:       {st['radio']}")
    print(f"Interface:   {st['device']}")
    print(f"State:       {st['state']}")
    if not st["connected"]:
        return
    print(f"SSID:        {st['ssid']}")
    if st["signal"] is not None or st["signal_dbm"] is not None:
        parts = []
        if st["signal"] is not None:
            parts.append(f"{st['signal']}%")
        if st["signal_dbm"] is not None:
            parts.append(f"{st['signal_dbm']} dBm")
        print(f"Signal:      {' / '.join(parts)}")
    if st["band"] or st["freq_mhz"]:
        band_s = f"{st['band']} GHz" if st["band"] else ""
        if st["freq_mhz"]:
            band_s = f"{band_s} ({st['freq_mhz']} MHz)".strip()
        if st["band_selected"] and st["band_selected"] != "auto":
            band_s += f" [pinned {st['band_selected']} GHz]"
        print(f"Band:        {band_s}")
    if st["bitrate"]:
        print(f"Bitrate:     {st['bitrate']}")
    if st["ip"]:
        addr = f"{st['ip']}/{st['prefix']}" if st["prefix"] is not None else st["ip"]
        print(f"IPv4:        {addr}")
    if st["gateway"]:
        print(f"Gateway:     {st['gateway']}")
    if st["dns"]:
        print(f"DNS:         {', '.join(st['dns'])}")


def list_nearby_networks(rescan: bool, preferred_iface: str | None = None) -> list[dict]:
    if not radio_enabled():
        return []
    dev = pick_wifi_device(preferred_iface)
    if dev is None:
        return []
    iface = dev["device"]
    known_ssids = {p["ssid"] for p in saved_wifi_profiles()}

    cmd = [
        "nmcli",
        "-t",
        "-f",
        "IN-USE,SSID,SIGNAL,SECURITY,FREQ",
        "device",
        "wifi",
        "list",
        "ifname",
        iface,
        "--rescan",
        "yes" if rescan else "no",
    ]
    proc = run_cmd(cmd, check=True)
    by_ssid: dict[str, dict] = {}
    for line in proc.stdout.splitlines():
        parts = nm_split_escaped(line)
        if len(parts) < 5:
            continue
        in_use, ssid, sig_s, sec, freq = parts[0], parts[1], parts[2], parts[3], parts[4]
        if not ssid:
            continue
        sig = int(sig_s) if sig_s.isdigit() else 0
        band = band_for_freq(freq)
        connected = in_use == "*"
        existing = by_ssid.get(ssid)
        if existing is None:
            by_ssid[ssid] = {
                "ssid": ssid,
                "signal": sig,
                "security": normalize_security(sec),
                "bands": [band] if band else [],
                "connected": connected,
                "known": ssid in known_ssids,
            }
        else:
            if connected:
                existing["connected"] = True
            if sig > existing["signal"]:
                existing["signal"] = sig
                existing["security"] = normalize_security(sec)
            if band and band not in existing["bands"]:
                existing["bands"].append(band)

    rows = list(by_ssid.values())
    for row in rows:
        row["bands"].sort(key=lambda b: float(b))
    rows.sort(key=lambda r: (not r["connected"], not r["known"], -r["signal"], r["ssid"].lower()))
    return rows


def print_network_list(rows: list[dict], as_json: bool) -> None:
    if as_json:
        print(json.dumps(rows))
        return
    if not rows:
        print("No Wi-Fi networks found.")
        return
    print(f"{'':2s} {'SSID':32s} {'SIGNAL':>6s}  {'BANDS':11s}  {'SECURITY':16s}  STATUS")
    for r in rows:
        mark = "*" if r["connected"] else " "
        bands = ",".join(r["bands"]) + "G" if r["bands"] else "-"
        status = "connected" if r["connected"] else ("known" if r["known"] else "")
        print(f"{mark:2s} {r['ssid'][:32]:32s} {r['signal']:5d}%  {bands:11s}  {r['security'][:16]:16s}  {status}")


def print_known_profiles(profiles: list[dict], as_json: bool) -> None:
    if as_json:
        print(json.dumps(profiles))
        return
    if not profiles:
        print("No saved Wi-Fi profiles.")
        return
    print(f"{'':2s} {'SSID':32s} {'AUTO':5s}  UUID")
    for p in profiles:
        mark = "*" if p["active"] else " "
        auto = "yes" if p["autoconnect"] else "no"
        print(f"{mark:2s} {p['ssid'][:32]:32s} {auto:5s}  {p['uuid']}")


def validate_secret(prop: str, secret: str) -> None:
    if not secret:
        raise UsageError("passphrase cannot be empty")
    if "\n" in secret or "\r" in secret:
        raise UsageError("passphrase cannot contain newlines")
    if secret != secret.strip():
        raise UsageError("passphrase cannot start or end with whitespace")
    if prop == "wifi-sec.psk":
        is_hex_psk = len(secret) == 64 and all(c in "0123456789abcdefABCDEF" for c in secret)
        if not (8 <= len(secret) <= 63 or is_hex_psk):
            raise UsageError("Wi-Fi passphrase must be 8-63 characters (or 64 hex characters)")


def nm_set_secret_via_edit(
    profile_uuid: str,
    prop: str,
    secret: str,
    *,
    enable_autoconnect: bool = False,
) -> None:
    """Write a secret via `nmcli connection edit` stdin so it never appears in /proc argv."""
    validate_secret(prop, secret)
    lines = [f"set {prop} {secret}"]
    if enable_autoconnect:
        lines.append("set connection.autoconnect yes")
    lines += ["save", "quit"]
    script = "\n".join(lines) + "\n"
    proc = run_cmd(["nmcli", "connection", "edit", "uuid", profile_uuid], input_text=script, check=True)
    for stream in (proc.stderr, proc.stdout):
        for line in stream.splitlines():
            if line.strip().startswith("Error:"):
                raise RuntimeError(line.strip())


def detect_psk_key_mgmt(ssid: str, iface: str, pinned_band: str = "auto") -> str | None:
    proc = run_cmd(
        ["nmcli", "-t", "-f", "SSID,SECURITY,FREQ", "device", "wifi", "list", "ifname", iface, "--rescan", "no"]
    )
    if proc.returncode != 0:
        return None
    saw_match = False
    saw_wpa_psk = False
    saw_sae = False
    for line in proc.stdout.splitlines():
        parts = nm_split_escaped(line)
        if len(parts) < 3 or parts[0] != ssid:
            continue
        ap_band = band_for_freq(parts[2])
        if pinned_band != "auto" and ap_band != pinned_band:
            continue
        saw_match = True
        tokens = set(parts[1].upper().split())
        if "WPA2" in tokens or "WPA1" in tokens:
            saw_wpa_psk = True
        elif "WPA3" in tokens or "SAE" in tokens:
            saw_sae = True
    if not saw_match:
        return None
    if saw_sae and not saw_wpa_psk:
        return "sae"
    return "wpa-psk"


def connect_enterprise(
    ssid: str,
    identity: str,
    password: str,
    target_iface: str,
) -> None:
    validate_secret("802-1x.password", password)
    con_uuid = str(uuid_mod.uuid4())
    add_cmd = [
        "nmcli",
        "connection",
        "add",
        "type",
        "wifi",
        "con-name",
        ssid,
        "ssid",
        ssid,
        "connection.uuid",
        con_uuid,
        "connection.autoconnect",
        "no",
        "wifi-sec.key-mgmt",
        "wpa-eap",
        "802-1x.eap",
        "peap",
        "802-1x.phase2-auth",
        "mschapv2",
        "802-1x.identity",
        identity,
        "802-1x.auth-timeout",
        "8",
    ]
    try:
        run_cmd(add_cmd, check=True)
        nm_set_secret_via_edit(con_uuid, "802-1x.password", password, enable_autoconnect=True)
        run_cmd(
            ["nmcli", "--wait", "28", "connection", "up", "uuid", con_uuid, "ifname", target_iface],
            check=True,
            timeout=30,
        )
    except BaseException:
        cleanup_cancelled_connection(con_uuid, delete_profile=True)
        raise


def connect_psk_via_profile(
    ssid: str,
    password: str,
    hidden: bool,
    target_iface: str,
) -> None:
    # Validate before touching NetworkManager profiles, then set the PSK via
    # `nmcli connection edit` stdin so the passphrase never appears in argv.
    validate_secret("wifi-sec.psk", password)
    matches = matching_wifi_profiles(ssid, target_iface)
    created = False
    prev_km: str | None = None
    reused: tuple[str, str, str] | None = None
    for p in matches:
        meta_lines = run_cmd(
            [
                "nmcli",
                "-e",
                "no",
                "-g",
                "802-11-wireless-security.key-mgmt,802-11-wireless.band",
                "connection",
                "show",
                "uuid",
                p["uuid"],
            ],
            check=True,
        ).stdout.splitlines()
        km = meta_lines[0].strip() if len(meta_lines) >= 1 else ""
        if km in ("", "wpa-psk", "sae"):
            band_raw = meta_lines[1] if len(meta_lines) >= 2 else ""
            reused = (p["uuid"], km, band_raw)
            break

    if reused is not None:
        con_uuid, cur_km, band_raw = reused
        pinned_band = band_from_nm(band_raw)
        detected_km = detect_psk_key_mgmt(ssid, target_iface, pinned_band=pinned_band)
        desired_km = detected_km if detected_km is not None else (cur_km if cur_km in ("wpa-psk", "sae") else "wpa-psk")
        if cur_km != desired_km:
            prev_km = cur_km
            run_cmd(
                ["nmcli", "connection", "modify", "uuid", con_uuid, "wifi-sec.key-mgmt", desired_km],
                check=True,
            )
    else:
        key_mgmt = detect_psk_key_mgmt(ssid, target_iface) or "wpa-psk"
        con_uuid = str(uuid_mod.uuid4())
        add_cmd = [
            "nmcli",
            "connection",
            "add",
            "type",
            "wifi",
            "con-name",
            ssid,
            "ssid",
            ssid,
            "connection.uuid",
            con_uuid,
            "connection.autoconnect",
            "no",
            "wifi-sec.key-mgmt",
            key_mgmt,
        ]
        if hidden:
            add_cmd += ["802-11-wireless.hidden", "yes"]
        created = True
    try:
        if created:
            run_cmd(add_cmd, check=True)
        nm_set_secret_via_edit(con_uuid, "wifi-sec.psk", password, enable_autoconnect=created)
        run_cmd(
            ["nmcli", "--wait", "28", "connection", "up", "uuid", con_uuid, "ifname", target_iface],
            check=True,
            timeout=30,
        )
    except BaseException:
        cleanup_cancelled_connection(con_uuid, delete_profile=created, restore_key_mgmt=prev_km)
        raise


def connect_open_via_profile(
    ssid: str,
    hidden: bool,
    target_iface: str,
    *,
    owe: bool = False,
) -> None:
    con_uuid = str(uuid_mod.uuid4())
    add_cmd = [
        "nmcli",
        "connection",
        "add",
        "type",
        "wifi",
        "con-name",
        ssid,
        "ssid",
        ssid,
        "connection.uuid",
        con_uuid,
        "connection.autoconnect",
        "no",
    ]
    if owe:
        add_cmd += ["wifi-sec.key-mgmt", "owe"]
    if hidden:
        add_cmd += ["802-11-wireless.hidden", "yes"]
    try:
        run_cmd(add_cmd, check=True)
        run_cmd(
            ["nmcli", "--wait", "28", "connection", "up", "uuid", con_uuid, "ifname", target_iface],
            check=True,
            timeout=30,
        )
        run_cmd(["nmcli", "connection", "modify", "uuid", con_uuid, "connection.autoconnect", "yes"], check=True)
    except BaseException:
        cleanup_cancelled_connection(con_uuid, delete_profile=True)
        raise


def strip_double_dash(args: list[str]) -> list[str]:
    if args and args[0] == "--":
        return args[1:]
    return args


def cmd_connect(args: list[str], as_json: bool) -> int:
    ssid: str | None = None
    password: str | None = None
    password_stdin = False
    identity: str | None = None
    hidden = False
    iface: str | None = None
    after_dash = False

    i = 0
    while i < len(args):
        tok = args[i]
        if not after_dash and tok == "--":
            after_dash = True
            i += 1
        elif not after_dash and tok == "--password":
            if i + 1 >= len(args):
                raise UsageError("--password requires a value")
            password = args[i + 1]
            i += 2
        elif not after_dash and tok == "--password-stdin":
            password_stdin = True
            i += 1
        elif not after_dash and tok == "--identity":
            if i + 1 >= len(args):
                raise UsageError("--identity requires a username")
            identity = args[i + 1]
            i += 2
        elif not after_dash and tok == "--hidden":
            hidden = True
            i += 1
        elif not after_dash and tok == "--interface":
            if i + 1 >= len(args):
                raise UsageError("--interface requires a device name")
            iface = args[i + 1]
            i += 2
        elif not after_dash and tok.startswith("-"):
            raise UsageError(f"unknown option '{tok}'")
        elif ssid is None:
            ssid = tok
            i += 1
        else:
            raise UsageError(f"unexpected argument '{tok}'")

    if not ssid:
        raise UsageError("Usage: hexciri network wifi connect <ssid> [options]")
    if password is not None and password_stdin:
        raise UsageError("use only one of --password or --password-stdin")
    if password_stdin:
        line = sys.stdin.readline()
        password = line.rstrip("\r\n")

    if not radio_enabled():
        run_cmd(["nmcli", "radio", "wifi", "on"], check=True)

    dev = pick_wifi_device(iface)
    if dev is None:
        raise RuntimeError("no Wi-Fi interface found")
    target_iface = dev["device"]

    if identity is not None:
        if password is None:
            if sys.stdin.isatty():
                password = getpass.getpass(f"Password for {identity}@{ssid}: ")
            else:
                raise UsageError("--identity requires --password or --password-stdin")
        connect_enterprise(ssid, identity, password, target_iface)
    elif password is not None:
        connect_psk_via_profile(ssid, password, hidden, target_iface)
    else:
        existing = matching_wifi_profiles(ssid, target_iface)
        if existing:
            con_uuid = existing[0]["uuid"]
            try:
                run_cmd(
                    ["nmcli", "--wait", "28", "connection", "up", "uuid", con_uuid, "ifname", target_iface],
                    check=True,
                    timeout=30,
                )
            except BaseException:
                cleanup_cancelled_connection(con_uuid)
                raise
        else:
            # Check if the scanned network requires credentials so a TTY user gets a prompt.
            nearby = {r["ssid"]: r for r in list_nearby_networks(False, target_iface)}
            sec = nearby.get(ssid, {}).get("security", "open").upper()
            needs_pw = sec not in ("OPEN", "OWE", "")
            if needs_pw and sys.stdin.isatty():
                pw = getpass.getpass(f"Passphrase for {ssid}: ")
                connect_psk_via_profile(ssid, pw, hidden, target_iface)
            elif needs_pw:
                raise UsageError(f"network '{ssid}' requires credentials (pass --password-stdin or --identity)")
            else:
                connect_open_via_profile(ssid, hidden, target_iface, owe=(sec == "OWE"))

    st = read_wifi_status(target_iface)
    if as_json:
        print(json.dumps(st))
    else:
        print(f"Connected to {st['ssid'] or ssid} on {target_iface}")
    return 0


def cmd_forget(args: list[str], as_json: bool) -> int:
    ssid_only = False
    pos: list[str] = []
    after_dash = False
    for tok in args:
        if not after_dash and tok == "--":
            after_dash = True
            continue
        if not after_dash and tok == "--ssid":
            ssid_only = True
            continue
        if not after_dash and tok.startswith("-"):
            raise UsageError(f"unknown option '{tok}'")
        pos.append(tok)
    if len(pos) != 1:
        raise UsageError("Usage: hexciri network wifi forget [--ssid] <ssid|uuid>")
    target = pos[0]
    profiles = saved_wifi_profiles()
    if ssid_only:
        matches = [p for p in profiles if p["ssid"] == target]
    else:
        matches = [p for p in profiles if p["uuid"] == target or p["ssid"] == target]
        if not matches:
            matches = [p for p in profiles if p["name"] == target]
    if not matches:
        raise RuntimeError(f"no saved Wi-Fi profile matching '{target}'")
    deleted = []
    for p in matches:
        run_cmd(["nmcli", "connection", "delete", "uuid", p["uuid"]], check=True)
        deleted.append({"name": p["name"], "ssid": p["ssid"], "uuid": p["uuid"]})
    if as_json:
        print(json.dumps({"forgotten": deleted}))
    else:
        for p in deleted:
            print(f"Forgot Wi-Fi profile: {p['ssid']} ({p['uuid']})")
    return 0


def cmd_band(args: list[str], as_json: bool) -> int:
    pos = strip_double_dash(args)
    if len(pos) > 1:
        raise UsageError("Usage: hexciri network wifi band [auto|2.4|5|6]")
    if pos and pos[0] not in ("auto", "2.4", "5", "6"):
        raise UsageError(f"invalid band '{pos[0]}' (expected auto, 2.4, 5, or 6)")
    if pos:
        run_cmd([omarchy_bin("hexciri-network-band"), pos[0]], check=True)
    info = read_band_info()
    if as_json:
        print(json.dumps(info))
    elif not info["current"] and not info["available"]:
        print("No active Wi-Fi connection.")
    else:
        print(f"Band:        {info['current'] or 'unknown'} GHz")
        print(f"Selected:    {info['selected']}")
        if info["available"]:
            print(f"Available:   {', '.join(b + ' GHz' for b in info['available'])}")
    return 0


def parse_global_flags(argv: list[str]) -> tuple[bool, list[str]]:
    as_json = False
    rest: list[str] = []
    after_dash = False
    skip_next = False
    value_flags = {"--password", "--identity", "--interface"}
    for arg in argv:
        if skip_next:
            rest.append(arg)
            skip_next = False
            continue
        if not after_dash and arg == "--":
            after_dash = True
            rest.append(arg)
            continue
        if not after_dash and arg in value_flags:
            rest.append(arg)
            skip_next = True
            continue
        if not after_dash and arg == "--json":
            as_json = True
            continue
        rest.append(arg)
    return as_json, rest


def main(argv: list[str]) -> int:
    if any(a in ("-h", "--help") for a in argv[:2]) and "--" not in argv[:2]:
        print(USAGE, end="")
        return 0

    as_json, args = parse_global_flags(argv)
    cmd = args[0] if args else "status"
    rest = args[1:]

    if cmd == "status":
        pos = strip_double_dash(rest)
        if len(pos) > 1:
            raise UsageError("Usage: hexciri network wifi status [interface]")
        print_wifi_status(read_wifi_status(pos[0] if pos else None), as_json)
        return 0

    if cmd in ("on", "off", "toggle"):
        if strip_double_dash(rest):
            raise UsageError(f"Usage: hexciri network wifi {cmd}")
        target = ("off" if radio_enabled() else "on") if cmd == "toggle" else cmd
        run_cmd(["nmcli", "radio", "wifi", target], check=True)
        if as_json:
            print(json.dumps(read_wifi_status()))
        else:
            print(f"Wi-Fi radio {target}")
        return 0

    if cmd in ("list", "scan"):
        rescan = cmd == "scan"
        known_only = False
        iface: str | None = None
        i = 0
        while i < len(rest):
            tok = rest[i]
            if tok == "--rescan":
                rescan = True
                i += 1
            elif tok == "--known":
                known_only = True
                i += 1
            elif tok == "--interface":
                if i + 1 >= len(rest):
                    raise UsageError("--interface requires a device name")
                iface = rest[i + 1]
                i += 2
            else:
                raise UsageError(f"unknown option '{tok}'")
        if known_only:
            print_known_profiles(saved_wifi_profiles(), as_json)
        else:
            print_network_list(list_nearby_networks(rescan, iface), as_json)
        return 0

    if cmd == "connect":
        return cmd_connect(rest, as_json)

    if cmd == "disconnect":
        pos = strip_double_dash(rest)
        if len(pos) > 1:
            raise UsageError("Usage: hexciri network wifi disconnect [interface]")
        dev = pick_wifi_device(pos[0] if pos else None)
        if dev is None:
            raise RuntimeError("no Wi-Fi interface found")
        if dev["state"] not in IDLE_DEVICE_STATES:
            run_cmd(["nmcli", "device", "disconnect", dev["device"]], check=True)
        st = read_wifi_status(dev["device"])
        if as_json:
            print(json.dumps(st))
        else:
            print(f"Disconnected {dev['device']}")
        return 0

    if cmd == "forget":
        return cmd_forget(rest, as_json)

    if cmd == "password":
        pos = strip_double_dash(rest)
        if len(pos) > 1:
            raise UsageError("Usage: hexciri network wifi password [interface]")
        dev = pick_wifi_device(pos[0] if pos else None)
        if dev is None or dev["state"] != "connected":
            raise RuntimeError("no active Wi-Fi connection")
        proc = run_cmd([omarchy_bin("hexciri-network-password"), dev["device"]], check=True)
        pw = proc.stdout.rstrip("\r\n")
        if as_json:
            print(json.dumps({"interface": dev["device"], "ssid": dev["connection"], "password": pw}))
        else:
            print(pw)
        return 0

    if cmd == "band":
        return cmd_band(rest, as_json)

    raise UsageError(f"unknown command '{cmd}'\n\n{USAGE}")


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _handle_sigterm)
    try:
        raise SystemExit(main(sys.argv[1:]))
    except CancelledError:
        raise SystemExit(143)
    except KeyboardInterrupt:
        raise SystemExit(130)
    except UsageError as exc:
        sys.stderr.write(f"hexciri-network-wifi: {exc}\n")
        raise SystemExit(2)
    except (RuntimeError, OSError) as exc:
        sys.stderr.write(f"hexciri-network-wifi: {exc}\n")
        raise SystemExit(1)
HEXCIRI_EOF_NET_WIFI
install_new_file "bin/hexciri-bluetooth" 755 <<'HEXCIRI_EOF_BT'
#!/usr/bin/python3

# omarchy:summary=Control Bluetooth power, scanning, pairing, and devices
# omarchy:group=bluetooth
# omarchy:subcommand=status [--json] — Show Bluetooth adapter power, controller, and connected devices
# omarchy:subcommand=on|off|toggle [--json] — Turn Bluetooth on, off, or toggle it (persists across reboots)
# omarchy:subcommand=list [--connected] [--paired] [--all] [--json] — List known or discovered Bluetooth devices
# omarchy:subcommand=scan [--timeout <sec>] [--all] [--json] — Scan for nearby Bluetooth devices
# omarchy:subcommand=info <device> [--json] — Show detailed info for a Bluetooth device (name or MAC)
# omarchy:subcommand=pair <device> [--json] — Pair, trust, and connect to a Bluetooth device (name or MAC)
# omarchy:subcommand=connect <device> [--json] — Connect to a Bluetooth device (name or MAC)
# omarchy:subcommand=disconnect <device> [--json] — Disconnect a Bluetooth device (name or MAC)
# omarchy:subcommand=forget <device> [--json] — Disconnect and remove a paired Bluetooth device (name or MAC)
# omarchy:subcommand=trust|untrust <device> [--json] — Mark or unmark a Bluetooth device as trusted
# omarchy:examples=hexciri bluetooth status | hexciri bluetooth scan | hexciri bluetooth connect "AirPods Pro" | hexciri bluetooth off

"""Human- and agent-friendly CLI for Bluetooth management via BlueZ."""

import json
import os
import re
import subprocess
import sys
import time

USAGE = """\
Usage: hexciri bluetooth [--json] <command> [args...]

  status [--json]                         Show Bluetooth adapter power and connected devices
  on | off | toggle [--json]              Turn Bluetooth on, off, or toggle it
  list [--connected] [--paired] [--all] [--json]
                                          List known and discovered Bluetooth devices
  scan [--timeout <sec>] [--all] [--json] Scan for nearby Bluetooth devices (default: 6s)
  info <device> [--json]                  Show details for a device (name or MAC address)
  pair <device> [--json]                  Pair, trust, and connect to a device
  connect <device> [--json]               Connect to a device (name or MAC address)
  disconnect <device> [--json]            Disconnect a device (name or MAC address)
  forget <device> [--json]                Disconnect and remove a paired device
  trust | untrust <device> [--json]       Trust or untrust a device
"""

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
MAC_RE = re.compile(r"^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")


class UsageError(Exception):
    pass


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text).replace("\r", "")


def c_env() -> dict[str, str]:
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    return env


def run_cmd(
    args: list[str],
    *,
    timeout: float | None = 15,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    try:
        proc = subprocess.run(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=c_env(),
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"command timed out: {' '.join(args)}") from exc
    if check and proc.returncode != 0:
        msg = strip_ansi((proc.stderr or proc.stdout).strip())
        raise RuntimeError(msg or f"{args[0]} exited with status {proc.returncode}")
    return proc


def bt_cmd(args: list[str], *, timeout: float = 10, check: bool = False) -> subprocess.CompletedProcess[str]:
    proc = run_cmd(["bluetoothctl", *args], timeout=timeout, check=False)
    combined = strip_ansi(f"{proc.stdout}\n{proc.stderr}").strip()
    if check:
        if proc.returncode != 0:
            raise RuntimeError(combined or f"bluetoothctl {' '.join(args)} failed")
        for line in combined.splitlines():
            s = line.strip()
            if s.startswith("Failed to ") or s.startswith("Device ") and "not available" in s:
                raise RuntimeError(s)
    return proc


def power_bin() -> str:
    script_dir = os.path.dirname(os.path.realpath(__file__))
    return os.path.join(script_dir, "hexciri-bluetooth-power")


def normalize_mac(value: str) -> str:
    return value.strip().replace("-", ":").upper()


def is_mac(value: str) -> bool:
    return bool(MAC_RE.match(value.strip()))


def has_human_name(name: str, alias: str) -> bool:
    candidate = (name or alias or "").strip()
    if not candidate:
        return False
    if is_mac(candidate) or UUID_RE.match(candidate):
        return False
    return True


def parse_paren_int(raw: str) -> int | None:
    m = re.search(r"\((-?\d+)\)", raw)
    if m:
        return int(m.group(1))
    m2 = re.match(r"^\s*(-?\d+)\s*$", raw)
    if m2:
        return int(m2.group(1))
    return None


def read_controllers() -> list[dict]:
    proc = bt_cmd(["list"], timeout=5, check=True)
    controllers: list[dict] = []
    for line in strip_ansi(proc.stdout).splitlines():
        m = re.match(r"^Controller\s+([0-9A-Fa-f:]{17})\s+(.*)$", line.strip())
        if not m:
            continue
        addr = normalize_mac(m.group(1))
        tail = m.group(2).strip()
        is_default = tail.endswith("[default]")
        if is_default:
            tail = tail[: -len("[default]")].strip()
        info = read_controller_show(addr)
        info["address"] = addr
        info["default"] = is_default
        if not info["name"]:
            info["name"] = tail
        if not info["alias"]:
            info["alias"] = info["name"]
        controllers.append(info)
    return controllers


def read_controller_show(address: str) -> dict:
    proc = bt_cmd(["show", address], timeout=5)
    info = {
        "address": address,
        "name": "",
        "alias": "",
        "default": False,
        "powered": False,
        "discoverable": False,
        "pairable": False,
        "discovering": False,
    }
    if proc.returncode != 0:
        return info
    for line in strip_ansi(proc.stdout).splitlines():
        s = line.strip()
        if ":" not in s:
            continue
        k, v = s.split(":", 1)
        k = k.strip()
        v = v.strip()
        if k == "Name":
            info["name"] = v
        elif k == "Alias":
            info["alias"] = v
        elif k == "Powered":
            info["powered"] = v.lower() == "yes"
        elif k == "Discoverable":
            info["discoverable"] = v.lower() == "yes"
        elif k == "Pairable":
            info["pairable"] = v.lower() == "yes"
        elif k == "Discovering":
            info["discovering"] = v.lower() == "yes"
    return info


def any_powered(controllers: list[dict] | None = None) -> bool:
    ctrls = controllers if controllers is not None else read_controllers()
    return any(c["powered"] for c in ctrls)


def ensure_powered() -> None:
    ctrls = read_controllers()
    if not ctrls:
        raise RuntimeError("no Bluetooth adapter found")
    if any_powered(ctrls):
        return
    run_cmd([power_bin(), "on"], timeout=15, check=True)


def wait_powered_off() -> None:
    try:
        wait_s = float(os.environ.get("HEXCIRI_BLUETOOTH_POWER_WAIT_SECONDS", "2"))
    except ValueError:
        wait_s = 2.0
    deadline = time.monotonic() + max(0.0, wait_s)
    while True:
        if not any_powered():
            return
        if time.monotonic() >= deadline:
            return
        time.sleep(0.15)


def read_device_info(address: str, fallback_name: str = "") -> dict | None:
    addr = normalize_mac(address)
    proc = bt_cmd(["info", addr], timeout=5)
    text = strip_ansi(proc.stdout)
    if proc.returncode != 0 or f"Device {addr} not available" in text:
        return None
    info = {
        "address": addr,
        "name": "",
        "alias": "",
        "label": "",
        "icon": "",
        "paired": False,
        "bonded": False,
        "trusted": False,
        "blocked": False,
        "connected": False,
        "rssi": None,
        "battery": None,
        "profiles": [],
    }
    for line in text.splitlines():
        s = line.strip()
        if ":" not in s:
            continue
        k, v = s.split(":", 1)
        k = k.strip()
        v = v.strip()
        if k == "Name":
            info["name"] = v
        elif k == "Alias":
            info["alias"] = v
        elif k == "Icon":
            info["icon"] = v
        elif k == "Paired":
            info["paired"] = v.lower() == "yes"
        elif k == "Bonded":
            info["bonded"] = v.lower() == "yes"
        elif k == "Trusted":
            info["trusted"] = v.lower() == "yes"
        elif k == "Blocked":
            info["blocked"] = v.lower() == "yes"
        elif k == "Connected":
            info["connected"] = v.lower() == "yes"
        elif k == "RSSI":
            info["rssi"] = parse_paren_int(v)
        elif k == "Battery Percentage":
            info["battery"] = parse_paren_int(v)
        elif k == "UUID":
            prof = re.sub(r"\s*\([0-9a-fA-F-]+\)\s*$", "", v).strip()
            if prof and prof not in info["profiles"]:
                info["profiles"].append(prof)
    if not info["name"] and fallback_name and not is_mac(fallback_name):
        info["name"] = fallback_name
    if not info["alias"]:
        info["alias"] = info["name"] or fallback_name or addr
    info["label"] = info["name"] or info["alias"] or addr
    return info


def list_devices(
    *,
    include_unnamed: bool = False,
    filters: list[str] | None = None,
    strict: bool = False,
) -> list[dict]:
    queries = [["devices", f] for f in filters] if filters else [["devices"]]
    seen: set[str] = set()
    devices: list[dict] = []
    for query_args in queries:
        proc = bt_cmd(query_args, timeout=5, check=True)
        for line in strip_ansi(proc.stdout).splitlines():
            m = re.match(r"^Device\s+([0-9A-Fa-f:]{17})(?:\s+(.*))?$", line.strip())
            if not m:
                continue
            addr = normalize_mac(m.group(1))
            if addr in seen:
                continue
            seen.add(addr)
            fallback_name = (m.group(2) or "").strip()
            try:
                info = read_device_info(addr, fallback_name=fallback_name)
            except RuntimeError:
                if strict:
                    raise
                info = None
            if info is None:
                continue
            known = info["connected"] or info["paired"] or info["trusted"]
            if not include_unnamed and not known and not has_human_name(info["name"], info["alias"]):
                continue
            devices.append(info)

    devices.sort(
        key=lambda d: (
            not d["connected"],
            not (d["paired"] or d["trusted"]),
            d["label"].lower(),
            d["address"],
        )
    )
    return devices


def resolve_device(query: str) -> tuple[dict, bool]:
    raw = query.strip()
    if not raw:
        raise UsageError("device name must not be empty")
    if is_mac(raw):
        addr = normalize_mac(raw)
        info = read_device_info(addr)
        if info is not None:
            return info, True
        return (
            {
                "address": addr,
                "name": "",
                "alias": addr,
                "label": addr,
                "icon": "",
                "paired": False,
                "bonded": False,
                "trusted": False,
                "blocked": False,
                "connected": False,
                "rssi": None,
                "battery": None,
                "profiles": [],
            },
            False,
        )

    q = raw.lower()
    devices = list_devices(include_unnamed=True, strict=True)
    exact = [
        d
        for d in devices
        if d["name"].lower() == q or d["alias"].lower() == q or d["label"].lower() == q
    ]
    if len(exact) == 1:
        return exact[0], True
    if len(exact) > 1:
        choices = ", ".join(f"{d['label']} ({d['address']})" for d in exact)
        raise RuntimeError(f"multiple Bluetooth devices match '{query}': {choices}")

    partial = [
        d
        for d in devices
        if q in d["name"].lower() or q in d["alias"].lower() or q in d["label"].lower()
    ]
    if len(partial) == 1:
        return partial[0], True
    if len(partial) > 1:
        choices = ", ".join(f"{d['label']} ({d['address']})" for d in partial)
        raise RuntimeError(f"ambiguous Bluetooth device '{query}'; matches: {choices}")

    raise RuntimeError(f"Bluetooth device '{query}' not found (run `hexciri bluetooth scan` first)")


def read_status() -> dict:
    controllers = read_controllers()
    powered = any_powered(controllers)
    default_ctrl = next((c for c in controllers if c["default"]), controllers[0] if controllers else None)
    connected = (
        list_devices(include_unnamed=True, filters=["Connected"])
        if powered
        else []
    )
    return {
        "available": bool(controllers),
        "powered": powered,
        "power": "on" if powered else "off",
        "controller": default_ctrl,
        "controllers": controllers,
        "connected": connected,
    }


def print_status(st: dict, as_json: bool) -> None:
    if as_json:
        print(json.dumps(st))
        return
    if not st["available"]:
        print("Bluetooth:   unavailable (no Bluetooth adapter found)")
        return
    ctrl = st["controller"]
    print(f"Power:       {st['power']}")
    if ctrl:
        print(f"Controller:  {ctrl['alias']} ({ctrl['address']})")
        if ctrl["discovering"]:
            print("Scanning:    yes")
    if not st["connected"]:
        print("Connected:   none")
        return
    for idx, d in enumerate(st["connected"]):
        prefix = "Connected:   " if idx == 0 else "             "
        batt = f", {d['battery']}%" if d["battery"] is not None else ""
        print(f"{prefix}{d['label']} ({d['address']}{batt})")


def print_device_list(devices: list[dict], as_json: bool) -> None:
    if as_json:
        print(json.dumps(devices))
        return
    if not devices:
        print("No Bluetooth devices found.")
        return
    print(f"{'':2s} {'NAME':28s} {'ADDRESS':17s}  {'BATTERY':>7s}  STATUS")
    for d in devices:
        mark = "*" if d["connected"] else " "
        batt = f"{d['battery']}%" if d["battery"] is not None else "-"
        flags = []
        if d["connected"]:
            flags.append("connected")
        elif d["paired"]:
            flags.append("paired")
        if d["trusted"] and not d["connected"]:
            flags.append("trusted")
        if d["blocked"]:
            flags.append("blocked")
        status = ", ".join(flags) if flags else "discovered"
        print(f"{mark:2s} {d['label'][:28]:28s} {d['address']:17s}  {batt:>7s}  {status}")


def print_device_info(d: dict, as_json: bool) -> None:
    if as_json:
        print(json.dumps(d))
        return
    print(f"Name:        {d['label']}")
    print(f"Address:     {d['address']}")
    if d["icon"]:
        print(f"Type:        {d['icon']}")
    print(f"Connected:   {'yes' if d['connected'] else 'no'}")
    print(f"Paired:      {'yes' if d['paired'] else 'no'}")
    print(f"Trusted:     {'yes' if d['trusted'] else 'no'}")
    if d["blocked"]:
        print("Blocked:     yes")
    if d["battery"] is not None:
        print(f"Battery:     {d['battery']}%")
    if d["rssi"] is not None:
        print(f"RSSI:        {d['rssi']} dBm")
    if d["profiles"]:
        print(f"Profiles:    {', '.join(d['profiles'])}")


def strip_double_dash(args: list[str]) -> list[str]:
    if args and args[0] == "--":
        return args[1:]
    return args


def cmd_list(args: list[str], as_json: bool) -> int:
    connected_only = False
    paired_only = False
    include_unnamed = False
    for tok in args:
        if tok == "--connected":
            connected_only = True
        elif tok == "--paired":
            paired_only = True
        elif tok == "--all":
            include_unnamed = True
        else:
            raise UsageError(f"unknown option '{tok}'")
    if connected_only:
        devices = list_devices(include_unnamed=True, filters=["Connected"])
    elif paired_only:
        devices = list_devices(include_unnamed=True, filters=["Paired", "Trusted"])
    else:
        devices = list_devices(include_unnamed=include_unnamed)
    if connected_only:
        devices = [d for d in devices if d["connected"]]
    if paired_only:
        devices = [d for d in devices if d["paired"] or d["trusted"]]
    print_device_list(devices, as_json)
    return 0


def cmd_scan(args: list[str], as_json: bool) -> int:
    duration = 6
    include_unnamed = False
    i = 0
    while i < len(args):
        tok = args[i]
        if tok == "--timeout":
            if i + 1 >= len(args):
                raise UsageError("--timeout requires seconds (1..60)")
            try:
                duration = int(args[i + 1])
            except ValueError as exc:
                raise UsageError(f"invalid --timeout '{args[i + 1]}' (expected integer seconds)") from exc
            if duration < 1 or duration > 60:
                raise UsageError("--timeout must be between 1 and 60 seconds")
            i += 2
        elif tok == "--all":
            include_unnamed = True
            i += 1
        else:
            raise UsageError(f"unknown option '{tok}'")

    ensure_powered()
    # `bluetoothctl --timeout N scan on` exits cleanly after N seconds of scanning.
    bt_cmd(["--timeout", str(duration), "scan", "on"], timeout=duration + 10, check=True)
    print_device_list(list_devices(include_unnamed=include_unnamed), as_json)
    return 0


def cmd_device_action(action: str, args: list[str], as_json: bool) -> int:
    pos = strip_double_dash(args)
    if len(pos) != 1:
        raise UsageError(f"Usage: hexciri bluetooth {action} <device>")
    dev, known_in_bluez = resolve_device(pos[0])
    addr = dev["address"]
    label = dev["label"]

    if action == "info":
        if not known_in_bluez:
            raise RuntimeError(f"Bluetooth device '{addr}' not available")
        print_device_info(dev, as_json)
        return 0

    if action == "pair":
        ensure_powered()
        if not dev["paired"]:
            bt_cmd(["--timeout", "20", "pair", addr], timeout=25, check=True)
            after_pair = read_device_info(addr)
            if not after_pair or not after_pair["paired"]:
                raise RuntimeError(f"timed out pairing with {label} ({addr})")
        bt_cmd(["trust", addr], timeout=10, check=True)
        bt_cmd(["--timeout", "20", "connect", addr], timeout=25, check=True)
        updated = read_device_info(addr)
        if not updated or not updated["connected"]:
            raise RuntimeError(f"timed out connecting to {label} ({addr})")
        if as_json:
            print(json.dumps(updated))
        else:
            print(f"Paired and connected {updated['label']} ({addr})")
        return 0

    if action == "connect":
        ensure_powered()
        if dev["paired"] and not dev["trusted"]:
            bt_cmd(["trust", addr], timeout=10, check=False)
        bt_cmd(["--timeout", "20", "connect", addr], timeout=25, check=True)
        updated = read_device_info(addr)
        if not updated or not updated["connected"]:
            raise RuntimeError(f"timed out connecting to {label} ({addr})")
        if as_json:
            print(json.dumps(updated))
        else:
            print(f"Connected {updated['label']} ({addr})")
        return 0

    if action == "disconnect":
        bt_cmd(["--timeout", "10", "disconnect", addr], timeout=15, check=True)
        updated = read_device_info(addr)
        if updated and updated["connected"]:
            raise RuntimeError(f"timed out disconnecting {label} ({addr})")
        result = updated or {**dev, "connected": False}
        if as_json:
            print(json.dumps(result))
        else:
            print(f"Disconnected {result['label']} ({addr})")
        return 0

    if action == "forget":
        ensure_powered()
        if dev["connected"]:
            bt_cmd(["--timeout", "10", "disconnect", addr], timeout=15, check=False)
        bt_cmd(["--timeout", "10", "remove", addr], timeout=15, check=True)
        if as_json:
            print(json.dumps({"forgotten": {"address": addr, "label": label}}))
        else:
            print(f"Forgot {label} ({addr})")
        return 0

    if action in ("trust", "untrust"):
        bt_cmd([action, addr], timeout=10, check=True)
        updated = read_device_info(addr) or dev
        if as_json:
            print(json.dumps(updated))
        else:
            verb = "Trusted" if action == "trust" else "Untrusted"
            print(f"{verb} {updated['label']} ({addr})")
        return 0

    raise UsageError(f"unknown command '{action}'")


def parse_global_flags(argv: list[str]) -> tuple[bool, list[str]]:
    as_json = False
    rest: list[str] = []
    after_dash = False
    skip_next = False
    value_flags = {"--timeout"}
    for arg in argv:
        if skip_next:
            rest.append(arg)
            skip_next = False
            continue
        if not after_dash and arg == "--":
            after_dash = True
            rest.append(arg)
            continue
        if not after_dash and arg in value_flags:
            rest.append(arg)
            skip_next = True
            continue
        if not after_dash and arg == "--json":
            as_json = True
            continue
        rest.append(arg)
    return as_json, rest


def main(argv: list[str]) -> int:
    if any(a in ("-h", "--help") for a in argv[:2]) and "--" not in argv[:2]:
        print(USAGE, end="")
        return 0

    as_json, args = parse_global_flags(argv)
    cmd = args[0] if args else "status"
    rest = args[1:]

    if cmd == "status":
        if strip_double_dash(rest):
            raise UsageError("Usage: hexciri bluetooth status [--json]")
        print_status(read_status(), as_json)
        return 0

    if cmd in ("on", "off", "toggle"):
        if strip_double_dash(rest):
            raise UsageError(f"Usage: hexciri bluetooth {cmd} [--json]")
        target = ("off" if any_powered() else "on") if cmd == "toggle" else cmd
        run_cmd([power_bin(), target], timeout=15, check=True)
        if target == "off":
            wait_powered_off()
        if as_json:
            print(json.dumps(read_status()))
        else:
            print(f"Bluetooth {target}")
        return 0

    if cmd == "list":
        return cmd_list(rest, as_json)

    if cmd == "scan":
        return cmd_scan(rest, as_json)

    if cmd in ("info", "pair", "connect", "disconnect", "forget", "trust", "untrust"):
        return cmd_device_action(cmd, rest, as_json)

    raise UsageError(f"unknown command '{cmd}'\n\n{USAGE}")


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)
    except UsageError as exc:
        sys.stderr.write(f"hexciri-bluetooth: {exc}\n")
        raise SystemExit(2)
    except (RuntimeError, OSError) as exc:
        sys.stderr.write(f"hexciri-bluetooth: {exc}\n")
        raise SystemExit(1)
HEXCIRI_EOF_BT
PY_COUNT_FILE="$(mktemp)"
export PY_COUNT_FILE
python3 - "$FORK_OUT" <<'PY' >>"$_patch_log"
import os
import sys

root = sys.argv[1]
changed = []
REPLACEMENTS = [
    ("bin/hexciri",
     'GROUP_DESCRIPTIONS[network]="Network status helpers"',
     'GROUP_DESCRIPTIONS[network]="Network, Wi-Fi, and Ethernet controls"',
     "router: network group description (PR #20331)"),
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
with open(os.environ["PY_COUNT_FILE"], "w") as f:
    f.write(str(len(changed)))
for label in changed:
    print("patched: %s" % label)
print("network-bluetooth-clis python edits: %d" % len(changed))
PY
py_edits="$(cat "$PY_COUNT_FILE")"
rm -f "$PY_COUNT_FILE"
total_edits=$((py_edits + CHANGED))
printf 'network-bluetooth-clis patch: %d file edits applied\n' "$total_edits" >>"$_patch_log"

# Syntax-check the new files (parse only, nothing executed, no bytecode
# written) and the edited router.
python3 - "$FORK_OUT" <<'PY' || die "python parse check failed on the new network/bluetooth CLIs"
import sys
for rel in ["bin/hexciri-network-ethernet", "bin/hexciri-network-wifi", "bin/hexciri-bluetooth"]:
    p = sys.argv[1] + "/" + rel
    compile(open(p, encoding="utf-8").read(), p, "exec")
print("python parse check ok: hexciri-network-ethernet, hexciri-network-wifi, hexciri-bluetooth")
PY
bash -n "$FORK_OUT/bin/hexciri" || die "bash -n failed on patched bin/hexciri"
info "  network-bluetooth-clis: hexciri network wifi/ethernet + hexciri bluetooth CLIs installed (PRs #20331/#20332)"
