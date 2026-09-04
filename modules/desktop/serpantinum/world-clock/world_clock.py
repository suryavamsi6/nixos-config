#!/usr/bin/env python3
"""Offline timezone snapshots and a small IANA location catalog for Serpantinum."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

ZONE1970 = Path("__TZDATA_ZONE1970__")
DEFAULT_ZONES = ["local", "UTC", "America/New_York", "Europe/London", "Asia/Tokyo"]


def local_zone() -> str:
    try:
        link = Path("/etc/localtime").resolve()
        marker = "/zoneinfo/"
        text = str(link)
        if marker in text:
            return text.split(marker, 1)[1]
    except OSError:
        pass
    return os.environ.get("TZ", "UTC") or "UTC"


def parse_coord(value: str) -> tuple[float, float] | None:
    if not value:
        return None
    sign = -1 if value[0] == "S" else 1
    if value[0] in "NS":
        raw = value[1:]
        deg = int(raw[:2])
        minute = int(raw[2:4]) if len(raw) >= 4 else 0
        second = int(raw[4:6]) if len(raw) >= 6 else 0
        lat = sign * (deg + minute / 60 + second / 3600)
        return lat, 0.0
    return None


def coordinates(value: str) -> tuple[float, float] | None:
    # zone1970.tab uses ±DDMM[SS]±DDDMM[SS].
    if not value or len(value) < 9:
        return None
    split = 1
    while split < len(value) and value[split] not in "+-":
        split += 1
    lat_raw, lon_raw = value[:split], value[split:]
    if len(lat_raw) < 5 or len(lon_raw) < 5:
        return None
    def one(raw: str, lat: bool) -> float:
        sign = -1 if raw[0] == "-" or raw[0] == "S" or raw[0] == "W" else 1
        digits = raw[1:]
        degree_len = 2 if lat else 3
        deg = int(digits[:degree_len])
        minute = int(digits[degree_len:degree_len + 2] or 0)
        second = int(digits[degree_len + 2:degree_len + 4] or 0)
        return sign * (deg + minute / 60 + second / 3600)
    return one(lat_raw, True), one(lon_raw, False)


def catalog(query: str = "", limit: int = 80) -> list[dict]:
    needle = query.casefold().strip()
    result = []
    try:
        rows = ZONE1970.read_text(encoding="utf-8").splitlines()
    except OSError:
        rows = []
    for row in rows:
        if not row or row.startswith("#"):
            continue
        fields = row.split("\t")
        if len(fields) < 4:
            continue
        country, coord, _, *names = fields
        point = coordinates(coord)
        for zone in names:
            if "/" not in zone or zone.startswith(("Etc/", "US/", "Canada/", "Mexico/")):
                continue
            label = zone.rsplit("/", 1)[-1].replace("_", " ")
            haystack = f"{label} {zone} {country}".casefold()
            if needle and needle not in haystack:
                continue
            result.append({"zone": zone, "label": label, "country": country, "lat": point[0] if point else 0, "lon": point[1] if point else 0})
            if len(result) >= limit:
                return result
    return result


def snapshot(zones: list[str], now: dt.datetime | None = None) -> dict:
    instant = now or dt.datetime.now(dt.timezone.utc)
    local = local_zone()
    items = []
    errors = []
    for raw in zones[:12]:
        zone = local if raw in ("", "local", "Local") else raw
        try:
            current = instant.astimezone(ZoneInfo(zone))
        except (ZoneInfoNotFoundError, ValueError):
            errors.append({"zone": raw, "error": "Unknown IANA timezone"})
            continue
        offset = current.utcoffset() or dt.timedelta(0)
        total_minutes = int(offset.total_seconds() // 60)
        sign = "+" if total_minutes >= 0 else "-"
        total_minutes = abs(total_minutes)
        label = "Local" if raw in ("", "local", "Local") else raw.rsplit("/", 1)[-1].replace("_", " ")
        items.append({
            "zone": zone, "requestedZone": raw,
            "label": label, "time": current.strftime("%H:%M:%S"),
            "date": current.strftime("%a, %d %b"), "day": current.strftime("%Y-%m-%d"),
            "abbr": current.tzname() or zone, "offset": f"UTC{sign}{total_minutes // 60:02d}:{total_minutes % 60:02d}",
            "dayDelta": (current.date() - instant.astimezone(ZoneInfo(local)).date()).days,
            "isDay": 7 <= current.hour < 19, "lat": 0, "lon": 0,
        })
    by_zone = {entry["zone"]: entry for entry in catalog(limit=1000)}
    for item in items:
        point = by_zone.get(item["zone"])
        if point:
            item.update({"lat": point["lat"], "lon": point["lon"]})
    return {"localZone": local, "generatedAt": instant.isoformat(), "clocks": items, "errors": errors}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zones", default=",".join(DEFAULT_ZONES))
    parser.add_argument("--search", default=None)
    parser.add_argument("--catalog", action="store_true")
    args = parser.parse_args()
    if args.catalog:
        print(json.dumps({"catalog": catalog(args.search or "")}, separators=(",", ":")))
        return
    zones = [part.strip() for part in args.zones.split(",") if part.strip()]
    print(json.dumps(snapshot(zones), separators=(",", ":")))


if __name__ == "__main__":
    main()
