# Gridwatch feature map

## Overview

The Electric Observatory overview makes the current electrical state legible at a glance: animated charge core, online/on-battery state, line voltage, load, runtime, battery voltage, transfer count, and a load pulse chart.

## History and events

The agent samples every five seconds while online, stores raw changes for 24 hours, rolls up older data, and retains event text with normalized severity. The UI derives outage duration/frequency, transfer reasons, runtime drift, estimated energy/cost, and explainable health recommendations.

## Settings and diagnostics

Settings use a draft/effective model so a partially edited threshold can never silently become active. Device controls only appear when the capability probe reports support. Diagnostic exports redact serials and secret-like keys.

## Calibration Lab

The Back-UPS RS 1500G-IN does not expose a verified software calibration or self-test command, so Gridwatch never takes direct USB control and never switches mains power. Instead, the agent provides a persisted monitored-manual workflow: 100% charge, fresh online telemetry, a stable 30–40% non-critical load observed for one minute, Polkit authorization, an expiring challenge plus three-second confirmation delay, guided mains disconnect/reconnect, recharge verification, result comparison, abort/recovery, scheduling, audit records, and a 30-day cooldown. Reported `SELFTEST` output is treated as history—not proof of command support.
