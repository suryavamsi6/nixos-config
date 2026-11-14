#!/usr/bin/env python3
"""Rebuild allowlisted Incus OCI instances onto newer upstream images.

Every instance is described by the JSON file the NixOS module writes
(`modules/services/incus-auto-update.nix`). Nothing is inferred from the
host: an instance is only touched if it appears there, its declared host
disks match exactly, its in-container data is mounted, it passes its HTTP
health check before the update, and its upstream image resolves to a
different fingerprint.

Each unit is updated as a whole, so paired instances (a backend and its
frontend) never run different builds. Before anything is rebuilt the
instances are stopped, snapshotted, and their host-side data directories
are copied to a private state directory.

A unit that is mid-update leaves `pending.json` behind and is never retried
automatically: the operator inspects the snapshot and the data copy first.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SEMVER = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def incus_result(*args):
    return subprocess.run(
        ["incus", *args], check=False, text=True, capture_output=True
    )


def incus(*args, check=True):
    result = incus_result(*args)
    if check and result.returncode != 0:
        raise RuntimeError(
            "incus " + " ".join(args) + ": " + (result.stderr or result.stdout).strip()
        )
    return result.stdout.strip()


def have_local_image(fingerprint):
    return subprocess.run(
        ["incus", "image", "info", fingerprint],
        check=False,
        text=True,
        capture_output=True,
    ).returncode == 0


def fetch_http(url):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(url, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except OSError:
        return None


def healthy(urls):
    return all((status or 0) in range(200, 400) for status in map(fetch_http, urls))


def wait_healthy(urls, attempts=60, delay=5):
    for _ in range(attempts):
        if healthy(urls):
            return
        time.sleep(delay)
    raise RuntimeError("health check failed for " + ", ".join(urls))


def check_data(instance, app):
    """Verify the app's host-backed disks before touching anything."""
    expanded = instance.get("expanded_devices", {})
    for device, expected in app.get("disks", {}).items():
        actual = expanded.get(device, {})
        found = (actual.get("type"), actual.get("source"), actual.get("path"))
        wanted = ("disk", expected["source"], expected["path"])
        if found != wanted:
            raise RuntimeError(
                f"{app['name']}: device {device!r} is {found}, expected {wanted}"
            )
    mounts = [
        f'grep -q " {expected["path"]} " /proc/mounts'
        for expected in app.get("disks", {}).values()
    ]
    for command in mounts + [f'test -e {path}' for path in app.get("requires", [])]:
        incus("exec", app["name"], "--", "sh", "-c", command)
    # A symlink or device node in the data tree would be copied or replaced
    # inconsistently, so refuse rather than guess.
    for expected in app.get("disks", {}).values():
        for entry in Path(expected["source"]).rglob("*"):
            if entry.is_symlink() or not (entry.is_dir() or entry.is_file()):
                raise RuntimeError(
                    f"{app['name']}: {entry} is not a plain file or directory"
                )


def installed_version(app):
    command = app.get("versionCommand")
    if not command:
        return None
    output = incus("exec", app["name"], "--", *command)
    match = SEMVER.match(output.strip())
    return tuple(map(int, match.groups())) if match else None


def resolve_target(app):
    """Return (fingerprint, semver-or-None) for the app's upstream image."""
    info = incus("image", "info", app["image"])
    fingerprint = re.search(r"(?m)^Fingerprint:\s*([0-9a-f]{64})\s*$", info)
    if not fingerprint:
        raise RuntimeError(f"{app['name']}: upstream fingerprint unavailable")
    version = re.search(r"(?m)^\s*oci\.version:\s*[\"']?([^\"'\s]+)[\"']?\s*$", info)
    semver = SEMVER.match(version.group(1)) if version else None
    return fingerprint.group(1), (tuple(map(int, semver.groups())) if semver else None)


def cache_image(app, target):
    if have_local_image(target):
        return
    incus("image", "copy", app["image"], "local:")
    if not have_local_image(target):
        raise RuntimeError(f"{app['name']}: {target} is not cached after copy")


def plan(app, report, dry_run):
    """Decide whether one instance needs a rebuild, without changing it.

    The image is pulled into the local cache here, while the instance is
    still running, so a failed pull can never leave an app stopped."""
    instance = json.loads(incus("query", f"/1.0/instances/{app['name']}"))
    if instance["status"] != "Running":
        raise RuntimeError(f"{app['name']}: instance is not running")
    current = instance.get("config", {}).get("volatile.base_image", "")
    if not re.fullmatch(r"[0-9a-f]{64}", current or ""):
        raise RuntimeError(f"{app['name']}: current base image fingerprint unavailable")
    check_data(instance, app)
    if not healthy(app["health"]):
        raise RuntimeError(f"{app['name']}: unhealthy before update")
    target, target_version = resolve_target(app)
    if current == target:
        report(app["name"], "current", target, None)
        return None
    if target_version is not None:
        running = installed_version(app)
        if running is not None and target_version < running:
            raise RuntimeError(
                f"{app['name']}: upstream {target_version} is older than running {running}"
            )
    if not dry_run:
        cache_image(app, target)
    report(app["name"], "update", target, target_version)
    return {"app": app, "instance": instance, "current": current, "target": target,
            "version": ".".join(map(str, target_version)) if target_version else None}


def backup_data(app, destination, record):
    """Copy each declared host data directory under a private state path."""
    for device, expected in app.get("disks", {}).items():
        source = Path(expected["source"])
        target = destination / app["name"] / device
        shutil.copytree(source, target, symlinks=True, copy_function=shutil.copy2)
        record.setdefault("data", {})[f"{app['name']}/{device}"] = str(target)
        # Compare file counts as a cheap sanity check on the copy.
        if sum(1 for _ in source.rglob("*")) != sum(1 for _ in target.rglob("*")):
            raise RuntimeError(f"{app['name']}: data copy verification failed")


def health_command_ok(unit):
    command = unit.get("healthCommand")
    if not command:
        return True
    output = incus("exec", unit["instance"], "--", *command, check=False)
    return output.strip() == unit.get("expect", "active")


def update_in_guest(unit, state, dry_run):
    """Update an app that installs itself inside its container.

    These instances are not built from an OCI image, so a rebuild would
    destroy the guest install. Instead the app's own updater runs inside
    the container, and the unit is only reported as updated once its health
    checks pass again.
    """
    name = unit["instance"]
    instance = json.loads(incus("query", f"/1.0/instances/{name}"))
    if instance["status"] != "Running":
        raise RuntimeError(f"{name}: instance is not running")
    if not healthy(unit.get("health", [])) or not health_command_ok(unit):
        raise RuntimeError(f"{name}: unhealthy before update")

    check = unit.get("checkCommand")
    if check:
        output = incus("exec", name, "--", *check, check=False)
        if unit.get("skipWhen") and unit["skipWhen"] in output:
            print(f"{unit['name']}: current", flush=True)
            return
        if unit.get("skipUnless") and unit["skipUnless"] not in output:
            print(f"{unit['name']}: current", flush=True)
            return
    print(f"{unit['name']}: update", flush=True)
    if dry_run:
        return

    record = {
        "unit": unit["name"],
        "kind": "in-guest",
        "instance": name,
        "started": datetime.now(timezone.utc).isoformat(),
        "phase": "updating",
    }
    pending = state / "pending.json"
    pending.write_text(json.dumps(record, indent=2) + "\n")
    pending.chmod(0o600)
    incus("exec", name, "--", *unit["updateCommand"])
    if unit.get("health") and not healthy(unit["health"]):
        raise RuntimeError(f"{name}: unhealthy after update")
    if not health_command_ok(unit):
        raise RuntimeError(f"{name}: health command failed after update")
    record["phase"] = "complete"
    (state / "last-success.json").write_text(json.dumps(record, indent=2) + "\n")
    (state / "last-success.json").chmod(0o600)
    pending.unlink()
    print(f"{unit['name']}: updated in place", flush=True)


def update_unit(unit, work, state, dry_run):
    if unit.get("precondition") and not Path(unit["precondition"]).exists():
        print(f"{unit['name']}: skipped, {unit['precondition']} is missing", flush=True)
        return
    if unit.get("kind") == "in-guest":
        return update_in_guest(unit, state, dry_run)
    report = lambda name, action, target, version: print(
        f"{name}: {action}"
        + (f" -> {target}" if action == "update" else "")
        + (f" ({version})" if version else ""),
        flush=True,
    )
    todo = [
        item
        for item in (plan(app, report, dry_run) for app in unit["instances"])
        if item
    ]
    if not todo:
        return
    if dry_run:
        return

    snapshot = "pre-update-" + datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    record = {
        "unit": unit["name"],
        "started": datetime.now(timezone.utc).isoformat(),
        "phase": "preparing",
        "instances": {
            item["app"]["name"]: {
                "previous": item["current"],
                "target": item["target"],
                "version": item["version"],
                "snapshot": snapshot,
            }
            for item in todo
        },
    }
    pending = state / "pending.json"
    pending.write_text(json.dumps(record, indent=2) + "\n")
    pending.chmod(0o600)

    stopped = []
    rebuild_started = False
    try:
        for item in todo:
            incus("stop", item["app"]["name"])
            stopped.append(item["app"])
        for item in todo:
            incus("snapshot", "create", item["app"]["name"], snapshot, "--expiry", "30d")
            backup_data(item["app"], work / (snapshot + "-data"), record)
        record["phase"] = "rebuilding"
        pending.write_text(json.dumps(record, indent=2) + "\n")
        rebuild_started = True
        for item in todo:
            incus("rebuild", item["target"], item["app"]["name"])
        for item in todo:
            incus("start", item["app"]["name"])
        stopped = []
        for item in todo:
            wait_healthy(item["app"]["health"])
            check_data(item["app"], item["instance"])
        record["phase"] = "complete"
        (state / "last-success.json").write_text(json.dumps(record, indent=2) + "\n")
        (state / "last-success.json").chmod(0o600)
        pending.unlink()
        for item in todo:
            print(f"{item['app']['name']}: updated to {item['target']}"
                  f"; snapshot {snapshot}", flush=True)
    finally:
        if stopped and not rebuild_started:
            for app in stopped:
                if incus_result("start", app["name"]).returncode != 0:
                    print(f"{app['name']}: could not restart", file=sys.stderr)
        elif stopped:
            print("unit is stopped mid-rebuild; review pending.json and restore "
                  "from the snapshot and data copy", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--only", action="append", default=[],
                        help="limit to these unit names")
    parser.add_argument("--dry-run", action="store_true",
                        help="report planned updates without changing anything")
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text())
    state = Path(config["stateDir"])
    work = Path(config["backupDir"])
    if not args.dry_run:
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        work.mkdir(mode=0o700, parents=True, exist_ok=True)
        if (state / "pending.json").exists():
            raise RuntimeError(
                f"{state / 'pending.json'} exists; review the failed update first"
            )
        if (state / "disabled").exists():
            print("updates are disabled by the flag file", flush=True)
            return

    units = [u for u in config["units"] if not args.only or u["name"] in args.only]
    if args.only and not units:
        raise RuntimeError("no configured unit matched --only")
    for unit in units:
        update_unit(unit, work, state, args.dry_run)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError,
            subprocess.CalledProcessError) as exc:
        print(f"incus app update failed: {exc}", file=sys.stderr)
        sys.exit(1)
