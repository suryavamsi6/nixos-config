#!/usr/bin/env python3
"""Loopback JSON feed for the Homepage dashboard widgets.

Homepage's `customapi` widgets read small JSON documents from this service.
Everything is computed from local sources only:

  /apps.json          Incus instances (container/VM) and their memory
  /services.json      top systemd units by memory
  /procs.json         top processes by resident memory, merged per command
  /temps.json         hwmon temperatures (CPU package/cores, NVMe, board)
  /adguard/log.json   AdGuard Home query log, newest first
  /adguard/queries.json  the same log, longer tail for the dashboard tile
  /adguard/top.json   AdGuard Home most-blocked domains for today
  /health             liveness probe

It binds 127.0.0.1 only: the AdGuard query log carries client names and the
domains the LAN looks up, so it stays private to this host. Homepage runs in
the host network namespace (PrivateNetwork=no), so its server side can reach
this port while nothing else can.
"""

import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BIND = "127.0.0.1"
PORT = int(os.environ.get("HOMELAB_STATS_PORT", "8793"))
LIMIT = 6
# The dashboard's query-log tile renders this many rows. Bounded because the
# tile is a list card, not a scrolling log pane.
QUERY_LIMIT = 10
CACHE_TTL = 4.0  # seconds; a dashboard refresh hits several endpoints at once
HUMAN = re.compile(r"^\s*([0-9.]+)\s*([KMGTP]i?B?|B)?\s*$")

ADGUARD_URL = os.environ.get("HOMELAB_STATS_ADGUARD_URL", "http://adguard.home.arpa")
ADGUARD_USER = os.environ.get("HOMEPAGE_VAR_ADGUARD_USERNAME", "")
ADGUARD_PASS = os.environ.get("HOMEPAGE_VAR_ADGUARD_PASSWORD", "")

_cache = {}
_session = {"cookie": "", "at": 0.0}


def run(cmd, timeout=8):
    """Run a command and return stdout, or '' when it is missing/fails."""
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def to_bytes(value):
    """Parse '1.22GiB', '869M' or a plain byte count into bytes."""
    match = HUMAN.match(str(value or ""))
    if not match:
        return 0
    try:
        number = float(match.group(1))
    except ValueError:
        return 0
    unit = (match.group(2) or "B").rstrip("B")[:1].upper()
    return int(number * {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4, "P": 1024**5}[unit])


def human(nbytes):
    nbytes = int(nbytes or 0)
    for unit in ("B", "K", "M", "G", "T"):
        if nbytes < 1024 or unit == "T":
            return f"{nbytes:.0f}{unit}" if unit == "B" else f"{nbytes:.1f}{unit}"
        nbytes /= 1024.0


# --- data sources ---------------------------------------------------------


def incus_apps():
    """Incus instances with their memory usage (containers and VMs)."""
    out = run(["incus", "list", "--format=csv", "-c", "n,s,t,m"], timeout=10)
    apps = []
    for line in out.splitlines():
        cols = [c.strip() for c in line.split(",")]
        if len(cols) < 4:
            continue
        name, state, kind, mem = cols[0], cols[1], cols[2], cols[3]
        if not name or state != "RUNNING":
            continue
        apps.append({"name": name, "mem": mem or "0", "kind": kind.lower(), "_bytes": to_bytes(mem)})
    apps.sort(key=lambda a: a["_bytes"], reverse=True)
    for app in apps:
        app.pop("_bytes", None)
    return apps[:LIMIT]


def top_services():
    """Top systemd units by cgroup memory. Incus is excluded: /apps.json covers it."""
    out = run(["systemd-cgtop", "-b", "-n1", "-m", "--depth=2"], timeout=10)
    units = []
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 4:
            continue
        path = cols[0]
        if not re.fullmatch(r"system\.slice/[^/]+\.(service|scope)", path):
            continue
        unit = path.split("/", 1)[1]
        if unit.startswith("incus") or unit.startswith("homepage-stats"):
            continue
        mem = cols[3]
        if mem == "-":
            continue
        units.append({"name": unit.removesuffix(".service").removesuffix(".scope"), "mem": mem, "_bytes": to_bytes(mem)})
    units.sort(key=lambda u: u["_bytes"], reverse=True)
    for unit in units:
        unit.pop("_bytes", None)
    return units[:LIMIT]


def top_processes():
    """Top processes by RSS, merged per command so multi-process apps rank whole."""
    out = run(["ps", "-eo", "comm=,rss=,pcpu=", "--sort=-rss"], timeout=8)
    merged = {}
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 3:
            continue
        name, rss, pcpu = cols[0], cols[1], cols[2]
        try:
            bytes_used = int(rss) * 1024
        except ValueError:
            continue
        entry = merged.setdefault(name, {"name": name, "bytes": 0, "cpu": 0.0})
        entry["bytes"] += bytes_used
        try:
            entry["cpu"] += float(pcpu)
        except ValueError:
            pass
    ordered = sorted(merged.values(), key=lambda p: p["bytes"], reverse=True)[:LIMIT]
    return [{"name": p["name"], "mem": human(p["bytes"]), "cpu": f"{p['cpu']:.1f}%"} for p in ordered]


# chip name -> (display name, sensors worth showing)
TEMP_CHIPS = {
    "coretemp": ("CPU", lambda label: label in ("Package id 0", "")),
    "nvme": ("NVMe", lambda label: label in ("Composite", "")),
    "acpitz": ("Board", lambda label: label in ("", "acpitz")),
    "iwlwifi_1": ("Wi-Fi", lambda label: True),
}


def temperatures():
    """Read hwmon temperatures; lm_sensors is not installed on this host.

    coretemp exposes a package value plus one per core, nvme exposes a
    composite value plus two controller sensors. Showing every one of them
    would fill the widget with noise, so only the representative sensor of
    each chip is kept.
    """
    found = []
    for hwmon in sorted(os.listdir("/sys/class/hwmon")):
        base = os.path.join("/sys/class/hwmon", hwmon)
        try:
            with open(os.path.join(base, "name")) as handle:
                chip = handle.read().strip()
        except OSError:
            continue
        if chip not in TEMP_CHIPS:
            continue
        display, wanted = TEMP_CHIPS[chip]
        for entry in sorted(os.listdir(base)):
            if not re.fullmatch(r"temp\d+_input", entry):
                continue
            node = os.path.join(base, entry)
            try:
                with open(node) as handle:
                    celsius = int(handle.read().strip()) // 1000
            except (OSError, ValueError):
                continue
            label = ""
            try:
                with open(node.replace("_input", "_label")) as handle:
                    label = handle.read().strip()
            except OSError:
                pass
            if not wanted(label):
                continue
            found.append({"name": display, "temp": f"{celsius}C", "_c": celsius})
            break  # one representative sensor per chip
    found.sort(key=lambda item: -item["_c"])
    unique = []
    for item in found:
        # Two NVMe drives report the same display name; keep the hotter one.
        if any(seen["name"] == item["name"] for seen in unique):
            continue
        unique.append(item)
    for item in unique:
        item.pop("_c", None)
    return unique[:LIMIT]


# --- AdGuard Home ---------------------------------------------------------

FILTERED = ("FilteredBlackList", "FilteredSafeBrowsing", "FilteredParental", "FilteredSafeSearch",
            "FilteredBlockedService", "Filtered")


def _adguard_creds():
    user = ADGUARD_USER.strip()
    password = ADGUARD_PASS.strip()
    if not user or not password or user == "changeme" or password == "changeme":
        return None
    return user, password


def _get_json(url, headers):
    request = urllib.request.Request(url, headers={**headers, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.loads(response.read().decode())
    except (urllib.error.URLError, ValueError, TimeoutError, OSError):
        return None


def _adguard_session():
    """Log in and cache the session cookie for the API calls."""
    creds = _adguard_creds()
    if not creds:
        return ""
    now = time.time()
    if _session["cookie"] and now - _session["at"] < 600:
        return _session["cookie"]
    body = json.dumps({"name": creds[0], "password": creds[1]}).encode()
    request = urllib.request.Request(
        ADGUARD_URL.rstrip("/") + "/control/login",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            cookie = (response.headers.get("Set-Cookie") or "").split(";", 1)[0]
    except (urllib.error.URLError, TimeoutError, OSError):
        return ""
    _session.update({"cookie": cookie, "at": now})
    return cookie


def adguard_request(path):
    """GET an AdGuard API path.

    AdGuard answers 401 without a WWW-Authenticate header, so urllib's
    challenge-response never fires and basic auth has to be sent up front.
    Some builds only accept a session cookie from /control/login, so a
    failed attempt retries once with that cookie.
    """
    creds = _adguard_creds()
    if not creds:
        return None
    url = ADGUARD_URL.rstrip("/") + path
    token = base64.b64encode(f"{creds[0]}:{creds[1]}".encode()).decode()
    data = _get_json(url, {"Authorization": f"Basic {token}"})
    if data is not None:
        return data
    cookie = _adguard_session()
    if not cookie:
        return None
    return _get_json(url, {"Cookie": cookie})


def adguard_log(limit=LIMIT):
    data = adguard_request("/control/querylog?limit=%d" % limit)
    if not data:
        return [{"name": "AdGuard auth needed", "label": "set HOMEPAGE_VAR_*"}]
    rows = []
    for entry in data.get("data") or []:
        question = entry.get("question") or {}
        domain = question.get("unicode_name") or question.get("name") or "?"
        reason = entry.get("reason") or ""
        status = entry.get("status") or ""
        if any(reason.startswith(prefix) for prefix in FILTERED):
            verdict = "blocked"
        elif reason in ("Rewrite", "RewriteRule"):
            verdict = "rewrite"
        elif reason == "NotFilteredWhiteList":
            verdict = "allow"
        elif entry.get("cached"):
            verdict = "cached"
        else:
            verdict = status.lower() or "ok"
        rows.append({"name": domain, "label": verdict, "target": ADGUARD_URL.rstrip("/") + "/#/logs"})
    return rows or [{"name": "AdGuard", "label": "no queries yet"}]


def adguard_top():
    data = adguard_request("/control/stats")
    if not data:
        return [{"name": "AdGuard auth needed", "label": "set HOMEPAGE_VAR_*"}]
    # top_blocked_domains is a list of single-key maps: [{"ads.example": 42}]
    rows = []
    for item in data.get("top_blocked_domains") or []:
        if not isinstance(item, dict) or not item:
            continue
        domain, hits = next(iter(item.items()))
        rows.append({"name": domain, "label": str(hits), "target": ADGUARD_URL.rstrip("/") + "/#/logs"})
    rows.sort(key=lambda row: -int(row["label"] or 0))
    return rows[:LIMIT] or [{"name": "AdGuard", "label": "nothing blocked"}]


# --- HTTP -----------------------------------------------------------------

ROUTES = {
    "/apps.json": incus_apps,
    "/services.json": top_services,
    "/procs.json": top_processes,
    "/temps.json": temperatures,
    "/adguard/log.json": adguard_log,
    "/adguard/queries.json": lambda: adguard_log(QUERY_LIMIT),
    "/adguard/top.json": adguard_top,
}


def payload(path):
    now = time.time()
    cached = _cache.get(path)
    if cached and now - cached[0] < CACHE_TTL:
        return cached[1]
    try:
        body = ROUTES[path]()
    except Exception as error:  # a broken source must not take the dashboard down
        print(f"{path}: {error}", file=sys.stderr, flush=True)
        body = []
    _cache[path] = (now, body)
    return body


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 - http.server API
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path == "/health":
            return self._send({"ok": True})
        if path not in ROUTES:
            return self._send({"error": "not found"}, status=404)
        return self._send(payload(path))

    def _send(self, body, status=200):
        encoded = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt, *args):  # keep the journal quiet
        pass


def main():
    if "--once" in sys.argv:
        for path in ROUTES:
            print(f"== {path}")
            print(json.dumps(payload(path)))
        return
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    print(f"homelab-stats listening on {BIND}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
