#!/usr/bin/env python3
"""Generate a validated apcupsd configuration from Serpantinum settings."""

import argparse
import json
import os
import tempfile
from pathlib import Path


DEFAULT_BATTERY_LEVEL = 50
DEFAULT_MINUTES = 5


def bounded_integer(value, default, minimum, maximum):
    if isinstance(value, bool):
        return default
    try:
        value = int(value)
    except (TypeError, ValueError):
        return default
    return max(minimum, min(maximum, value))


def load_policy(settings_path):
    try:
        settings = json.loads(Path(settings_path).read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        settings = {}

    ups = settings.get("ups", {})
    if not isinstance(ups, dict):
        ups = {}

    return {
        "batteryLevel": bounded_integer(
            ups.get("shutdownBatteryLevel"), DEFAULT_BATTERY_LEVEL, 5, 90
        ),
        "minutes": bounded_integer(
            ups.get("shutdownMinutes"), DEFAULT_MINUTES, 1, 60
        ),
    }


def render_config(policy, script_dir):
    return f"""## apcupsd.conf v1.1 ##
UPSNAME back-ups-rs-1500g-in
UPSCABLE usb
UPSTYPE usb
DEVICE
POLLTIME 30
LOCKFILE /run/lock
SCRIPTDIR {script_dir}
PWRFAILDIR /run/apcupsd
NOLOGINDIR /run/apcupsd
ONBATTERYDELAY 6
BATTERYLEVEL {policy['batteryLevel']}
MINUTES {policy['minutes']}
TIMEOUT 0
NETSERVER on
NISIP 127.0.0.1
NISPORT 3551
EVENTSFILE /var/log/apcupsd.events
EVENTSFILEMAX 10
"""


def atomic_write(path, content):
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=destination.name + ".", dir=destination.parent, text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--script-dir", required=True)
    args = parser.parse_args()

    policy = load_policy(args.settings)
    atomic_write(args.output, render_config(policy, args.script_dir))
    atomic_write(
        str(Path(args.output).with_name("policy.json")),
        json.dumps(policy, sort_keys=True) + "\n",
    )


if __name__ == "__main__":
    main()
