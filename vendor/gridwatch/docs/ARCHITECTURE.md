# Gridwatch architecture

The GPUIX/Bun app is an unprivileged client. It renders the Electric Observatory shell and reads telemetry built from the agent's `apcaccess status` snapshot. The always-on Rust agent is the single writer for telemetry, history, audit, and settings, and exposes a versioned JSON-lines protocol over `/run/gridwatch/agent.sock`.

Mutating actions are intentionally separate from telemetry. The agent validates policy values, writes an audit entry, and requires verified peer credentials plus Polkit authorization for every mutation. A user-session notifier is the only process that talks to the desktop notification bus.

The backend uses a capability probe. Unsupported features are shown as explanations rather than disabled mystery buttons. This is important for Back-UPS models, where software runtime calibration is not universal.

## Shutdown policy ownership

When the NixOS module's `enableApcupsd` and `manageShutdownPolicy` options are on, apcupsd runs from `/var/lib/gridwatch/apcupsd.conf` instead of a store-immutable file. The module seeds it from `/etc/gridwatch/apcupsd.template` (the standard `services.apcupsd.configText`), and the agent:

1. Reconciles the runtime file with the persisted policy at boot.
2. Applies saves atomically: renders only the `BATTERYLEVEL`/`MINUTES` directives, backs up the last-good file, restarts `apcupsd`, and verifies the reported thresholds before accepting.
3. Rolls back to the last-good file and restarts if verification fails.

Without those options the agent is read-only for threshold changes and refuses with `policy-owner-unavailable` rather than silently diverging from the daemon.

## Manual runtime calibration

The RS 1500G-IN has no verified non-interactive calibration driver. The agent instead persists a monitored-manual workflow: one-minute stable-load observation, an expiring challenge, Polkit + three-second hold confirmation, guided mains disconnect/reconnect, recharge verification, result comparison, 30-day cooldown, and abort/recovery with audit records on every transition.