#!/usr/bin/env python3
"""macOS network, DNS, route, topology, and bufferbloat diagnostics.

Network tests are read-only. By default, compact results are saved under the
user state directory so later runs can show before/after changes. Pass
--load-test to temporarily saturate the connection and measure responsiveness.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import json
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Sequence


PUBLIC_DNS = "1.1.1.1"
DEFAULT_DOMAIN = "example.com"
PING_PAYLOAD_BYTES = 120
PING_REPLY_BYTES = PING_PAYLOAD_BYTES + 8
HISTORY_VERSION = 1
HISTORY_LIMIT = 100
DEFAULT_HISTORY_FILE = (
    Path.home() / ".local" / "state" / "network-diagnostics" / "history.json"
)
RFC1918_NETWORKS = tuple(
    ipaddress.ip_network(network)
    for network in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)
CGNAT_NETWORK = ipaddress.ip_network("100.64.0.0/10")


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    output: str


@dataclass(frozen=True)
class PingResult:
    target: str
    transmitted: int
    received: int
    latencies_ms: tuple[float, ...]

    @property
    def loss_percent(self) -> float:
        if self.transmitted <= 0:
            return 100.0
        lost = max(0, self.transmitted - self.received)
        return 100.0 * lost / self.transmitted

    @property
    def average_ms(self) -> float | None:
        return statistics.fmean(self.latencies_ms) if self.latencies_ms else None

    @property
    def minimum_ms(self) -> float | None:
        return min(self.latencies_ms) if self.latencies_ms else None

    @property
    def maximum_ms(self) -> float | None:
        return max(self.latencies_ms) if self.latencies_ms else None


@dataclass(frozen=True)
class RouteHop:
    number: int
    address: str
    latency_ms: float | None


@dataclass(frozen=True)
class DnsResult:
    server: str
    cached_ms: tuple[float, ...]
    uncached_ms: float | None

    @property
    def cached_average_ms(self) -> float | None:
        return statistics.fmean(self.cached_ms) if self.cached_ms else None


@dataclass(frozen=True)
class InterfaceCounters:
    input_bytes: int
    output_bytes: int
    input_errors: int
    output_errors: int
    collisions: int


@dataclass(frozen=True)
class SystemBridge:
    name: str
    status: str
    members: tuple[str, ...]


@dataclass(frozen=True)
class WanTopology:
    mode: str
    summary: str
    first_public_hop: RouteHop | None
    pre_public_hops: tuple[RouteHop, ...]


def run(command: Sequence[str], *, timeout: float = 15) -> CommandResult:
    """Run a command without invoking a shell and merge stderr into stdout."""
    try:
        completed = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return CommandResult(124, str(error))
    return CommandResult(completed.returncode, completed.stdout)


def system_command(path: str, fallback: str) -> str | None:
    preferred = Path(path)
    if preferred.is_file() and preferred.stat().st_mode & 0o111:
        return str(preferred)
    return shutil.which(fallback)


def default_route() -> tuple[str, str]:
    route = system_command("/sbin/route", "route")
    if not route:
        raise RuntimeError("route command not found")
    result = run([route, "-n", "get", "default"])
    interface_match = re.search(r"^\s*interface:\s*(\S+)", result.output, re.MULTILINE)
    gateway_match = re.search(r"^\s*gateway:\s*(\S+)", result.output, re.MULTILINE)
    if not interface_match or not gateway_match:
        raise RuntimeError(f"could not read the default route: {result.output.strip()}")
    return interface_match.group(1), gateway_match.group(1)


def dns_servers() -> list[str]:
    scutil = system_command("/usr/sbin/scutil", "scutil")
    servers: list[str] = []
    if scutil:
        output = run([scutil, "--dns"]).output
        in_primary_resolver = False
        for line in output.splitlines():
            if line.strip().startswith("resolver #"):
                if in_primary_resolver:
                    break
                in_primary_resolver = line.strip() == "resolver #1"
                continue
            if in_primary_resolver:
                match = re.match(r"\s*nameserver\[\d+\]\s*:\s*(\S+)", line)
                if match and match.group(1) not in servers:
                    servers.append(match.group(1))

    if servers:
        return servers

    try:
        resolv_conf = Path("/etc/resolv.conf").read_text(encoding="utf-8")
    except OSError:
        return []
    for match in re.finditer(r"^\s*nameserver\s+(\S+)", resolv_conf, re.MULTILINE):
        if match.group(1) not in servers:
            servers.append(match.group(1))
    return servers


def proxy_state() -> str:
    scutil = system_command("/usr/sbin/scutil", "scutil")
    if not scutil:
        return "unknown"
    output = run([scutil, "--proxy"]).output
    enabled_keys = re.findall(
        r"^\s*(HTTPEnable|HTTPSEnable|SOCKSEnable|ProxyAutoConfigEnable|"
        r"ProxyAutoDiscoveryEnable)\s*:\s*1\s*$",
        output,
        re.MULTILINE,
    )
    return ", ".join(enabled_keys) if enabled_keys else "none enabled"


def interface_details(interface: str) -> tuple[str, str]:
    ifconfig = system_command("/sbin/ifconfig", "ifconfig")
    if not ifconfig:
        return "unknown", "unknown"
    output = run([ifconfig, interface]).output
    media_match = re.search(r"^\s*media:\s*(.+)$", output, re.MULTILINE)
    status_match = re.search(r"^\s*status:\s*(\S+)", output, re.MULTILINE)
    media = media_match.group(1).strip() if media_match else "unknown"
    status = status_match.group(1) if status_match else "unknown"
    return media, status


def hardware_port_name(interface: str) -> str:
    networksetup = system_command("/usr/sbin/networksetup", "networksetup")
    if not networksetup:
        return "unknown"
    output = run([networksetup, "-listallhardwareports"]).output
    current_port = "unknown"
    for line in output.splitlines():
        port_match = re.match(r"Hardware Port:\s*(.+)", line)
        if port_match:
            current_port = port_match.group(1).strip()
            continue
        device_match = re.match(r"Device:\s*(\S+)", line)
        if device_match and device_match.group(1) == interface:
            return current_port
    return "unknown"


def system_bridges() -> list[SystemBridge]:
    """Return macOS software bridges; these are distinct from modem bridge mode."""
    ifconfig = system_command("/sbin/ifconfig", "ifconfig")
    if not ifconfig:
        return []
    interface_names = run([ifconfig, "-l"]).output.split()
    bridges: list[SystemBridge] = []
    for name in interface_names:
        if not name.startswith("bridge"):
            continue
        output = run([ifconfig, name]).output
        status_match = re.search(r"^\s*status:\s*(\S+)", output, re.MULTILINE)
        members = tuple(
            dict.fromkeys(re.findall(r"^\s*member:\s*(\S+)", output, re.MULTILINE))
        )
        bridges.append(
            SystemBridge(
                name=name,
                status=status_match.group(1) if status_match else "unknown",
                members=members,
            )
        )
    return bridges


def interface_counters(interface: str) -> InterfaceCounters | None:
    netstat = system_command("/usr/sbin/netstat", "netstat")
    if not netstat:
        return None
    output = run([netstat, "-ibn", "-I", interface]).output
    headers: list[str] | None = None
    for line in output.splitlines():
        fields = line.split()
        if fields and fields[0] == "Name":
            headers = fields
            continue
        if (
            headers
            and len(fields) >= len(headers)
            and fields[0] == interface
            and fields[2].startswith("<Link#")
        ):
            values = dict(zip(headers, fields, strict=False))

            def number(name: str) -> int:
                value = values.get(name, "0")
                return int(value) if value.isdigit() else 0

            return InterfaceCounters(
                input_bytes=number("Ibytes"),
                output_bytes=number("Obytes"),
                input_errors=number("Ierrs"),
                output_errors=number("Oerrs"),
                collisions=number("Coll"),
            )
    return None


def interface_activity(interface: str) -> tuple[float, float, InterfaceCounters | None]:
    before = interface_counters(interface)
    started = time.monotonic()
    time.sleep(1)
    after = interface_counters(interface)
    elapsed = max(0.001, time.monotonic() - started)
    if not before or not after:
        return 0.0, 0.0, after
    receive_mbps = (
        max(0, after.input_bytes - before.input_bytes) * 8 / elapsed / 1_000_000
    )
    send_mbps = (
        max(0, after.output_bytes - before.output_bytes) * 8 / elapsed / 1_000_000
    )
    return receive_mbps, send_mbps, after


def trace_route(target: str) -> list[RouteHop]:
    traceroute = system_command("/usr/sbin/traceroute", "traceroute")
    if not traceroute:
        return []
    result = run(
        [traceroute, "-n", "-q", "1", "-w", "1", "-m", "8", target],
        timeout=12,
    )
    hops: list[RouteHop] = []
    pattern = re.compile(
        r"^\s*(\d+)\s+(\d{1,3}(?:\.\d{1,3}){3})(?:\s+([\d.]+)\s*ms)?",
        re.MULTILINE,
    )
    for match in pattern.finditer(result.output):
        latency = float(match.group(3)) if match.group(3) else None
        hops.append(RouteHop(int(match.group(1)), match.group(2), latency))
    return hops


def ping(target: str, count: int) -> PingResult:
    ping_command = system_command("/sbin/ping", "ping")
    if not ping_command:
        return PingResult(target, count, 0, ())
    result = run(
        [
            ping_command,
            "-n",
            "-s",
            str(PING_PAYLOAD_BYTES),
            "-c",
            str(count),
            "-i",
            "0.25",
            target,
        ],
        timeout=count * 0.25 + 8,
    )
    # The exact reply size filters unrelated short ICMP health-check packets that
    # macOS may deliver to the same raw socket.
    reply_pattern = re.compile(
        rf"^{PING_REPLY_BYTES} bytes from {re.escape(target)}:.*\btime=([\d.]+)\s*ms$",
        re.MULTILINE,
    )
    latencies = tuple(float(value) for value in reply_pattern.findall(result.output))
    summary = re.search(r"(\d+) packets transmitted", result.output)
    transmitted = int(summary.group(1)) if summary else count
    return PingResult(target, transmitted, min(transmitted, len(latencies)), latencies)


def dig_query(server: str, domain: str) -> float | None:
    dig = system_command("/usr/bin/dig", "dig")
    if not dig:
        return None
    result = run(
        [
            dig,
            f"@{server}",
            domain,
            "A",
            "+noall",
            "+stats",
            "+time=2",
            "+tries=1",
        ],
        timeout=4,
    )
    match = re.search(r"Query time:\s*(\d+)\s*msec", result.output)
    return float(match.group(1)) if match else None


def test_dns(server: str, domain: str) -> DnsResult:
    dig_query(server, domain)  # Warm caches before measuring repeated lookups.
    cached = tuple(
        latency for _ in range(5) if (latency := dig_query(server, domain)) is not None
    )
    unique_domain = f"diagnostic-{uuid.uuid4().hex}.{domain}"
    return DnsResult(server, cached, dig_query(server, unique_domain))


def run_load_test(interface: str, maximum_seconds: int) -> dict[str, Any] | None:
    network_quality = system_command("/usr/bin/networkQuality", "networkQuality")
    if not network_quality:
        return None
    result = run(
        [
            network_quality,
            "-I",
            interface,
            "-s",
            "-M",
            str(maximum_seconds),
            "-c",
        ],
        timeout=maximum_seconds + 15,
    )
    start = result.output.find("{")
    end = result.output.rfind("}")
    if start < 0 or end < start:
        return None
    try:
        data = json.loads(result.output[start : end + 1])
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def address_scope(address: str) -> str:
    try:
        parsed = ipaddress.ip_address(address)
    except ValueError:
        return "unknown"
    if parsed in CGNAT_NETWORK:
        return "carrier-nat"
    if any(parsed in network for network in RFC1918_NETWORKS):
        return "private"
    if parsed.is_loopback or parsed.is_link_local:
        return "private"
    return "public"


def is_private(address: str) -> bool:
    return address_scope(address) == "private"


def infer_wan_topology(hops: list[RouteHop], gateway: str) -> WanTopology:
    """Infer local NAT topology without mistaking later ISP-private hops for routers."""
    if not hops:
        return WanTopology(
            mode="unknown",
            summary="WAN topology unknown because traceroute returned no hops.",
            first_public_hop=None,
            pre_public_hops=(),
        )

    gateway_hop = next((hop for hop in hops if hop.address == gateway), hops[0])
    after_gateway = [hop for hop in hops if hop.number > gateway_hop.number]
    first_public = next(
        (hop for hop in after_gateway if address_scope(hop.address) == "public"),
        None,
    )
    pre_public = tuple(
        hop
        for hop in after_gateway
        if first_public is None or hop.number < first_public.number
    )
    if not after_gateway:
        return WanTopology(
            mode="unknown",
            summary="WAN topology unknown beyond the default gateway.",
            first_public_hop=None,
            pre_public_hops=(),
        )

    next_hop = after_gateway[0]
    next_scope = address_scope(next_hop.address)
    if next_scope == "public":
        return WanTopology(
            mode="single-router-likely",
            summary=(
                "No second private home-router hop detected; one local router and "
                "a bridged modem are likely."
            ),
            first_public_hop=first_public,
            pre_public_hops=pre_public,
        )
    if next_scope == "carrier-nat":
        return WanTopology(
            mode="carrier-grade-nat",
            summary=(
                "The next hop is carrier-grade NAT. The modem may be bridged, but "
                "the ISP still performs upstream NAT."
            ),
            first_public_hop=first_public,
            pre_public_hops=pre_public,
        )
    if next_scope == "private" and next_hop.address.startswith(("192.168.", "172.")):
        return WanTopology(
            mode="possible-double-nat",
            summary=(
                f"A second private hop ({next_hop.address}) appears before the ISP; "
                "modem router mode or double NAT is likely."
            ),
            first_public_hop=first_public,
            pre_public_hops=pre_public,
        )
    if next_scope == "private":
        return WanTopology(
            mode="private-upstream",
            summary=(
                f"A private upstream hop ({next_hop.address}) exists before a public hop; "
                "it may be another router or the ISP access network."
            ),
            first_public_hop=first_public,
            pre_public_hops=pre_public,
        )
    return WanTopology(
        mode="unknown",
        summary="The hop sequence was not sufficient to infer modem/router mode.",
        first_public_hop=first_public,
        pre_public_hops=pre_public,
    )


def format_latency(value: float | None) -> str:
    return "timeout" if value is None else f"{value:.1f} ms"


def build_snapshot(
    *,
    label: str | None,
    interface: str,
    interface_type: str,
    gateway: str,
    topology: WanTopology,
    hops: list[RouteHop],
    bridges: list[SystemBridge],
    ping_by_role: dict[str, PingResult],
    dns_results: list[DnsResult],
    load_test: dict[str, Any] | None,
) -> dict[str, Any]:
    local_dns = next(
        (result for result in dns_results if is_private(result.server)), None
    )
    public_dns = next(
        (result for result in dns_results if address_scope(result.server) == "public"),
        None,
    )

    def ping_metric(role: str, property_name: str) -> float | None:
        result = ping_by_role.get(role)
        if not result:
            return None
        value = getattr(result, property_name)
        return float(value) if value is not None else None

    metrics: dict[str, float | None] = {
        "gateway_latency_ms": ping_metric("local_gateway", "average_ms"),
        "first_public_latency_ms": ping_metric("first_public_hop", "average_ms"),
        "public_latency_ms": ping_metric("public_target", "average_ms"),
        "public_loss_percent": ping_metric("public_target", "loss_percent"),
        "local_dns_cached_ms": (
            local_dns.cached_average_ms if local_dns is not None else None
        ),
        "local_dns_uncached_ms": local_dns.uncached_ms if local_dns else None,
        "public_dns_cached_ms": (
            public_dns.cached_average_ms if public_dns is not None else None
        ),
        "public_dns_uncached_ms": public_dns.uncached_ms if public_dns else None,
    }
    if load_test:
        responsiveness = [
            float(load_test.get(key, 0) or 0)
            for key in ("dl_responsiveness", "ul_responsiveness")
        ]
        responsiveness = [value for value in responsiveness if value > 0]
        metrics.update(
            {
                "download_mbps": float(load_test.get("dl_throughput", 0) or 0)
                / 1_000_000,
                "upload_mbps": float(load_test.get("ul_throughput", 0) or 0)
                / 1_000_000,
                "idle_rtt_ms": float(load_test.get("base_rtt", 0) or 0),
                "loaded_response_ms": (
                    60_000 / min(responsiveness) if responsiveness else None
                ),
            }
        )

    return {
        "timestamp": datetime.now(UTC).isoformat(timespec="seconds"),
        "label": label,
        "public_target": (
            ping_by_role["public_target"].target
            if "public_target" in ping_by_role
            else None
        ),
        "interface": {"name": interface, "type": interface_type},
        "gateway": gateway,
        "topology": {
            "mode": topology.mode,
            "summary": topology.summary,
            "pre_public_hops": [hop.address for hop in topology.pre_public_hops],
            "route": [
                {
                    "number": hop.number,
                    "address": hop.address,
                    "latency_ms": hop.latency_ms,
                }
                for hop in hops
            ],
        },
        "system_bridges": [
            {"name": bridge.name, "status": bridge.status, "members": bridge.members}
            for bridge in bridges
        ],
        "metrics": metrics,
    }


def load_history(path: Path) -> tuple[list[dict[str, Any]], str | None]:
    if not path.exists():
        return [], None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [], f"could not read {path}: {error}"
    if not isinstance(data, dict) or data.get("version") != HISTORY_VERSION:
        return [], f"unsupported history format in {path}; leaving it unchanged"
    snapshots = data.get("snapshots")
    if not isinstance(snapshots, list) or not all(
        isinstance(snapshot, dict) for snapshot in snapshots
    ):
        return [], f"invalid history data in {path}; leaving it unchanged"
    return snapshots, None


def save_history(path: Path, snapshots: list[dict[str, Any]]) -> str | None:
    payload = {
        "version": HISTORY_VERSION,
        "snapshots": snapshots[-HISTORY_LIMIT:],
    }
    temporary_path = path.with_suffix(f"{path.suffix}.tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        temporary_path.replace(path)
    except OSError as error:
        return f"could not save {path}: {error}"
    return None


def select_baseline(
    snapshots: list[dict[str, Any]], label: str | None
) -> dict[str, Any] | None:
    if not snapshots:
        return None
    if label is None:
        return snapshots[-1]
    return next(
        (
            snapshot
            for snapshot in reversed(snapshots)
            if snapshot.get("label") == label
        ),
        None,
    )


def comparison_lines(baseline: dict[str, Any], current: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    before_topology = baseline.get("topology", {})
    after_topology = current.get("topology", {})
    before_mode = before_topology.get("mode", "unknown")
    after_mode = after_topology.get("mode", "unknown")
    mode_labels = {
        "single-router-likely": "single router / bridged modem likely",
        "possible-double-nat": "possible second router / double NAT",
        "carrier-grade-nat": "ISP carrier-grade NAT",
        "private-upstream": "private upstream hop",
        "unknown": "unknown topology",
    }
    if before_mode != after_mode:
        lines.append(
            f"Topology: {mode_labels.get(before_mode, before_mode)} -> "
            f"{mode_labels.get(after_mode, after_mode)}"
        )
    else:
        lines.append(f"Topology: unchanged ({mode_labels.get(after_mode, after_mode)})")

    before_interface = baseline.get("interface", {})
    after_interface = current.get("interface", {})
    before_interface_text = f"{before_interface.get('name', 'unknown')} ({before_interface.get('type', 'unknown')})"
    after_interface_text = f"{after_interface.get('name', 'unknown')} ({after_interface.get('type', 'unknown')})"
    if before_interface_text != after_interface_text:
        lines.append(f"Interface: {before_interface_text} -> {after_interface_text}")

    before_metrics = baseline.get("metrics", {})
    after_metrics = current.get("metrics", {})
    metric_specs = (
        ("gateway_latency_ms", "Gateway latency", "ms", True, 5.0),
        ("first_public_latency_ms", "First public-hop latency", "ms", True, 5.0),
        ("public_latency_ms", "Internet latency", "ms", True, 5.0),
        ("public_loss_percent", "Packet loss", "%", True, 1.0),
        ("local_dns_cached_ms", "Local cached DNS", "ms", True, 5.0),
        ("local_dns_uncached_ms", "Local uncached DNS", "ms", True, 10.0),
        ("public_dns_cached_ms", "Public DNS", "ms", True, 10.0),
        ("download_mbps", "Download throughput", "Mbps", False, 2.0),
        ("upload_mbps", "Upload throughput", "Mbps", False, 2.0),
        ("loaded_response_ms", "Loaded response time", "ms", True, 20.0),
    )
    for key, title, unit, lower_is_better, meaningful_delta in metric_specs:
        before_value = before_metrics.get(key)
        after_value = after_metrics.get(key)
        if not isinstance(before_value, (int, float)) or not isinstance(
            after_value, (int, float)
        ):
            continue
        delta = float(after_value) - float(before_value)
        if abs(delta) < meaningful_delta:
            status = "stable"
        else:
            improved = delta < 0 if lower_is_better else delta > 0
            status = "improved" if improved else "worse"
        percent = (
            f", {delta / float(before_value) * 100:+.0f}%"
            if float(before_value) != 0
            else ""
        )
        lines.append(
            f"{title}: {float(before_value):.1f} -> {float(after_value):.1f} "
            f"{unit} ({status}{percent})"
        )
    return lines


def print_ping(label: str, result: PingResult) -> None:
    if result.average_ms is None:
        print(f"  {label:<20} {result.target:<15} timeout (100% loss)")
        return
    print(
        f"  {label:<20} {result.target:<15} "
        f"avg {result.average_ms:6.1f} ms  "
        f"min {result.minimum_ms:6.1f}  max {result.maximum_ms:6.1f}  "
        f"loss {result.loss_percent:4.1f}%"
    )


def analyze(
    *,
    topology: WanTopology,
    gateway_ping: PingResult,
    upstream_ping: PingResult | None,
    public_hop_ping: PingResult | None,
    public_ping: PingResult,
    dns_results: list[DnsResult],
    counters: InterfaceCounters | None,
    load_test: dict[str, Any] | None,
) -> list[str]:
    findings: list[str] = []
    if topology.mode == "single-router-likely":
        findings.append(
            "No second private home-router hop is visible; bridge mode/single-router routing is likely."
        )
    elif topology.mode == "possible-double-nat":
        findings.append(
            "A second private router hop is visible before the ISP; double NAT is likely."
        )
    elif topology.mode == "carrier-grade-nat":
        findings.append(
            "ISP carrier-grade NAT is visible; this does not prove that modem bridge mode is off."
        )
    gateway_good = (
        gateway_ping.average_ms is not None
        and gateway_ping.average_ms < 10
        and gateway_ping.loss_percent <= 1
    )
    public_bad = (
        public_ping.average_ms is None
        or public_ping.average_ms >= 150
        or public_ping.loss_percent > 2
    )

    link_errors = bool(
        counters
        and (counters.input_errors or counters.output_errors or counters.collisions)
    )
    if gateway_good and not link_errors:
        findings.append(
            "The Mac-to-router link looks healthy; latency and link errors are low."
        )
    elif gateway_good and link_errors:
        findings.append(
            "Gateway latency is healthy, but the interface has cumulative link errors."
        )
    elif not gateway_good:
        findings.append(
            "The local link/router is unhealthy: gateway latency or packet loss is high."
        )

    if upstream_ping and public_hop_ping:
        upstream_latency = upstream_ping.average_ms
        public_hop_latency = public_hop_ping.average_ms
        if upstream_latency is not None and public_hop_latency is not None:
            jump = public_hop_latency - upstream_latency
            if jump >= 50:
                findings.append(
                    f"Latency jumps by about {jump:.0f} ms at the first public/ISP hop."
                )
            elif jump >= 25:
                findings.append(
                    "Latency first becomes elevated at the WAN/ISP boundary."
                )

    private_dns = next((item for item in dns_results if is_private(item.server)), None)
    if private_dns and private_dns.cached_average_ms is not None:
        if private_dns.cached_average_ms <= 10:
            findings.append(
                "The local DNS cache is fast; slow first-time lookups come from the upstream path."
            )
        elif private_dns.cached_average_ms >= 100:
            findings.append(
                "The configured local DNS server is itself responding slowly."
            )

    external_dns_slow = any(
        (result.uncached_ms is not None and result.uncached_ms >= 100)
        or (
            not is_private(result.server)
            and result.cached_average_ms is not None
            and result.cached_average_ms >= 100
        )
        for result in dns_results
    )
    if external_dns_slow:
        findings.append(
            "External DNS lookups are slow (100 ms or more), matching WAN delay."
        )

    if gateway_good and public_bad:
        findings.append(
            "The bottleneck is beyond the local router: likely WAN saturation, modem/ONT queueing, "
            "or ISP congestion."
        )

    if load_test:
        base_rtt = float(load_test.get("base_rtt", 0) or 0)
        responsiveness = [
            float(load_test.get(key, 0) or 0)
            for key in ("dl_responsiveness", "ul_responsiveness")
        ]
        responsiveness = [value for value in responsiveness if value > 0]
        if base_rtt > 0 and responsiveness:
            loaded_rtt = 60_000 / min(responsiveness)
            if loaded_rtt >= base_rtt * 3 and loaded_rtt - base_rtt >= 100:
                findings.append(
                    f"Severe bufferbloat detected: estimated loaded response time is "
                    f"~{loaded_rtt:.0f} ms versus {base_rtt:.0f} ms idle."
                )
            elif loaded_rtt - base_rtt >= 50:
                findings.append(
                    f"Bufferbloat is present: loaded response time rises to ~{loaded_rtt:.0f} ms."
                )

    if not findings:
        findings.append(
            "No clear fault was captured. Re-run during the slowdown and include --load-test."
        )
    elif not load_test:
        findings.append(
            "Use --load-test to confirm whether WAN queueing/bufferbloat is the cause."
        )
    return findings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Diagnose macOS LAN, WAN, DNS, bridge/NAT topology, historical changes, "
            "and optional bufferbloat."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  network-diagnostics.py --label before-bridge
  network-diagnostics.py --label after-bridge --compare-to before-bridge
  network-diagnostics.py --load-test --label loaded-test

Without --compare-to, each run compares automatically with the previous run.
""",
    )
    parser.add_argument(
        "--target",
        default=PUBLIC_DNS,
        help=f"public IPv4 target for route and ping tests (default: {PUBLIC_DNS})",
    )
    parser.add_argument(
        "--domain",
        default=DEFAULT_DOMAIN,
        help=f"public domain used for DNS tests (default: {DEFAULT_DOMAIN})",
    )
    parser.add_argument(
        "--ping-count",
        type=int,
        default=12,
        help="number of ICMP requests per target (default: 12)",
    )
    parser.add_argument(
        "--load-test",
        action="store_true",
        help="run networkQuality; temporarily saturates the connection and transfers data",
    )
    parser.add_argument(
        "--load-test-seconds",
        type=int,
        default=20,
        metavar="SECONDS",
        help="maximum networkQuality runtime when --load-test is used (default: 20)",
    )
    parser.add_argument(
        "--label",
        help="label the saved snapshot, for example before-bridge or after-bridge",
    )
    parser.add_argument(
        "--compare-to",
        metavar="LABEL",
        help="compare with the newest saved snapshot carrying this label",
    )
    parser.add_argument(
        "--history-file",
        type=Path,
        default=DEFAULT_HISTORY_FILE,
        metavar="PATH",
        help=f"snapshot history path (default: {DEFAULT_HISTORY_FILE})",
    )
    parser.add_argument(
        "--no-history",
        action="store_true",
        help="do not read, compare, or save snapshot history",
    )
    args = parser.parse_args()
    if not 3 <= args.ping_count <= 100:
        parser.error("--ping-count must be between 3 and 100")
    if not 8 <= args.load_test_seconds <= 60:
        parser.error("--load-test-seconds must be between 8 and 60")
    if args.label and (
        len(args.label) > 64 or any(char in args.label for char in "\r\n")
    ):
        parser.error("--label must be one line and no more than 64 characters")
    if args.compare_to and args.no_history:
        parser.error("--compare-to cannot be combined with --no-history")
    try:
        target = ipaddress.ip_address(args.target)
    except ValueError:
        parser.error("--target must be an IP address")
    if target.version != 4:
        parser.error("--target currently requires an IPv4 address")
    return args


def main() -> int:
    args = parse_args()
    if platform.system() != "Darwin":
        print("error: this diagnostic currently supports macOS only", file=sys.stderr)
        return 2

    history: list[dict[str, Any]] = []
    history_error: str | None = None
    baseline: dict[str, Any] | None = None
    if not args.no_history:
        history, history_error = load_history(args.history_file)
        if history_error:
            print(f"warning: {history_error}", file=sys.stderr)
        else:
            baseline = select_baseline(history, args.compare_to)

    try:
        interface, gateway = default_route()
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    servers = dns_servers()
    media, link_status = interface_details(interface)
    interface_type = hardware_port_name(interface)
    bridges = system_bridges()

    print("Network diagnostics")
    print("=" * 19)
    print(f"Default interface : {interface}")
    print(f"Interface type    : {interface_type}")
    print(f"Default gateway   : {gateway}")
    print(f"Link              : {link_status}; {media}")
    print(f"DNS servers       : {', '.join(servers) if servers else 'not detected'}")
    print(f"System proxy      : {proxy_state()}")
    if not args.no_history:
        print(f"History           : {args.history_file}")

    receive_mbps, send_mbps, counters = interface_activity(interface)
    print(
        f"Mac traffic now   : receive {receive_mbps:.2f} Mbps; send {send_mbps:.2f} Mbps"
    )
    if counters:
        print(
            "Link error totals : "
            f"input {counters.input_errors}; output {counters.output_errors}; "
            f"collisions {counters.collisions}"
        )

    print("\nTracing the WAN boundary...")
    hops = trace_route(args.target)
    if hops:
        for hop in hops:
            print(
                f"  {hop.number:>2}  {hop.address:<15} {format_latency(hop.latency_ms)}"
            )
    else:
        print("  traceroute unavailable or no hops replied")

    topology = infer_wan_topology(hops, gateway)
    first_public_hop = topology.first_public_hop
    upstream_hop = topology.pre_public_hops[-1] if topology.pre_public_hops else None

    print("\nTopology")
    print(f"  WAN inference      : {topology.summary}")
    if bridges:
        for bridge in bridges:
            members = ", ".join(bridge.members) if bridge.members else "no members"
            print(
                f"  macOS {bridge.name:<10} : {bridge.status}; members: {members} "
                "(not modem bridge mode)"
            )
    else:
        print("  macOS bridges      : none detected")

    ping_targets: list[tuple[str, str, str]] = [
        ("local_gateway", "local gateway", gateway)
    ]
    if upstream_hop:
        scope = address_scope(upstream_hop.address)
        upstream_label = (
            "carrier NAT hop" if scope == "carrier-nat" else "upstream private hop"
        )
        ping_targets.append(("upstream_hop", upstream_label, upstream_hop.address))
    if first_public_hop:
        ping_targets.append(
            ("first_public_hop", "first public hop", first_public_hop.address)
        )
    ping_targets.append(("public_target", "public target", args.target))

    dig_available = system_command("/usr/bin/dig", "dig") is not None
    dns_test_servers = (
        list(dict.fromkeys([*servers[:2], PUBLIC_DNS])) if dig_available else []
    )
    print("\nMeasuring latency and DNS (this normally takes several seconds)...")
    ping_results: dict[str, PingResult] = {}
    dns_results: list[DnsResult] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        ping_futures = {
            executor.submit(ping, target, args.ping_count): target
            for target in dict.fromkeys(
                target for _role, _label, target in ping_targets
            )
        }
        dns_futures = {
            executor.submit(test_dns, server, args.domain): server
            for server in dns_test_servers
        }
        for future, target in ping_futures.items():
            ping_results[target] = future.result()
        dns_by_server = {
            server: future.result() for future, server in dns_futures.items()
        }
        dns_results = [dns_by_server[server] for server in dns_test_servers]

    print("\nLatency")
    displayed_targets: set[str] = set()
    for _role, label, target in ping_targets:
        if target in displayed_targets:
            continue
        print_ping(label, ping_results[target])
        displayed_targets.add(target)
    ping_by_role = {role: ping_results[target] for role, _label, target in ping_targets}

    print("\nDNS")
    if not dns_results:
        print("  dig is unavailable; DNS timing was skipped")
    for result in dns_results:
        cached = format_latency(result.cached_average_ms)
        uncached = format_latency(result.uncached_ms)
        print(f"  {result.server:<15} cached avg {cached:<10} uncached {uncached}")

    load_test: dict[str, Any] | None = None
    if args.load_test:
        print(
            "\nRunning Apple's load test; this temporarily saturates the connection "
            "and transfers data..."
        )
        load_test = run_load_test(interface, args.load_test_seconds)
        print("\nLoaded connection")
        if load_test:
            download_mbps = float(load_test.get("dl_throughput", 0) or 0) / 1_000_000
            upload_mbps = float(load_test.get("ul_throughput", 0) or 0) / 1_000_000
            base_rtt = float(load_test.get("base_rtt", 0) or 0)
            download_rpm = float(load_test.get("dl_responsiveness", 0) or 0)
            upload_rpm = float(load_test.get("ul_responsiveness", 0) or 0)
            print(
                f"  Throughput       : {download_mbps:.1f} Mbps down; {upload_mbps:.1f} Mbps up"
            )
            print(f"  Idle RTT         : {base_rtt:.1f} ms")
            print(
                f"  Responsiveness   : {download_rpm:.0f} RPM down; {upload_rpm:.0f} RPM up"
            )
        else:
            print("  networkQuality did not return a usable result")

    gateway_ping = ping_by_role["local_gateway"]
    public_ping = ping_by_role["public_target"]
    upstream_ping = ping_by_role.get("upstream_hop")
    public_hop_ping = ping_by_role.get("first_public_hop")
    findings = analyze(
        topology=topology,
        gateway_ping=gateway_ping,
        upstream_ping=upstream_ping,
        public_hop_ping=public_hop_ping,
        public_ping=public_ping,
        dns_results=dns_results,
        counters=counters,
        load_test=load_test,
    )

    print("\nDiagnosis")
    for finding in findings:
        print(f"  - {finding}")

    if not args.no_history and not history_error:
        snapshot = build_snapshot(
            label=args.label,
            interface=interface,
            interface_type=interface_type,
            gateway=gateway,
            topology=topology,
            hops=hops,
            bridges=bridges,
            ping_by_role=ping_by_role,
            dns_results=dns_results,
            load_test=load_test,
        )
        print("\nComparison")
        if baseline:
            baseline_label = baseline.get("label") or "unlabeled"
            baseline_time = baseline.get("timestamp", "unknown time")
            print(f"  Against: {baseline_label} ({baseline_time})")
            for line in comparison_lines(baseline, snapshot):
                print(f"  - {line}")
        elif args.compare_to:
            print(f"  No saved snapshot found with label: {args.compare_to}")
        else:
            print("  No previous snapshot yet; this run becomes the baseline.")

        save_error = save_history(args.history_file, [*history, snapshot])
        if save_error:
            print(f"  Warning: {save_error}")
        else:
            saved_label = args.label or "unlabeled"
            print(f"  Saved current snapshot as: {saved_label}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        raise SystemExit(130) from None
