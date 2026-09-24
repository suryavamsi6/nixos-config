# Gridwatch — GPUIX APC UPS Manager Plan

## Context

Create **Gridwatch**, a standalone NixOS desktop application for managing an APC UPS. It will eventually replace the APC-specific settings currently embedded in Serpantinum, expand toward PowerChute-style monitoring and controls, and add safe automation such as runtime calibration.

Initial repository finding: `/home/surya/Projects/APC-UPS` is an empty, non-Git project directory (apart from Pi task metadata), so this will be a greenfield application. The current implementation is a staged downstream Serpantinum/NixOS change in `/home/surya/Dotfiles/nixos-config`: a QML page polls `apcaccess status`, while `modules/hardware/ups.nix` generates `/run/apcupsd/apcupsd.conf` from Serpantinum JSON and restarts `apcupsd` on policy changes. Live read-only probing confirms an active USB **APC Back-UPS RS 1500G-IN** (865 W nominal) exposing line voltage, load, charge, runtime, battery voltage/date, transfer thresholds/counts, sensitivity, self-test result, and firmware through local NIS. The present applied shutdown policy is 5% / 1 minute, although source defaults remain 50% / 5 minutes.

## Approach

Build the native interface with **GPUIX** (`@gpuix/react` + the prebuilt `@gpuix/native` renderer), React, TypeScript, and Bun. The chosen **Electric Observatory** visual direction uses an obsidian canvas, luminous cyan-to-lime status energy, restrained aurora gradients, glassy depth, strong instrument typography, and state-aware motion. Its hero is an animated “energy core” joining charge, grid state, load, and remaining runtime; secondary “load pulse” and “power DNA” views make trends legible without becoming a conventional admin dashboard. GPUIX supports native gradients/animations, images/SVG, inputs, virtual lists, and accessibility metadata; because custom canvas and Linux GPU screenshot testing are not ready, charts use layout primitives/generated SVG and domain/state logic remains independently testable with Vitest.

Target the detected APC Back-UPS RS 1500G-IN through `apcupsd` first. A typed `UpsBackend` capability model will prevent unsupported controls from appearing and leave room for more models/backends. Normal telemetry will use local `apcaccess`/NIS without opening USB directly. A small Rust system agent will own validated persistent policy, exclusive-device maintenance actions, scheduling, and controlled `apcupsd` stop/restart behind a root-owned Unix socket; the GUI never runs as root. The service checks socket peer credentials and Polkit authorization for mutations. Dangerous operations add prepare/confirm challenges, audit records, strict preconditions, timeouts, and guaranteed daemon restoration/rollback.

Deliver staged milestones: (1) live dashboard, event timeline, local history, notifications, and read-only diagnostics; (2) shutdown policy/settings and safe self-test through the agent; (3) capability-probed guarded runtime calibration and deeper insights. Calibration is offered only when the model proves support; otherwise the app provides a manual guided workflow. It requires full charge, stable 30–40% non-critical load, healthy communications, no recent outage/calibration, explicit confirmation, continuous monitoring, abort, and post-run recharge guidance. Because deep discharge consumes battery life, it is recommended only after battery replacement or a materially inaccurate runtime estimate—not as routine maintenance.

An always-on Rust system agent will collect/downsample telemetry, ingest events, evaluate local alerts, and run approved schedules even when the Gridwatch window is closed. A tiny unprivileged user-session notifier will relay agent events to the desktop session, so the root service never connects to the user notification bus; unread alerts replay when the user session returns. The UI supplies a rich in-app alert inbox and desktop notifications only; email/webhook delivery stays behind future extension interfaces. This repository will include its own opt-in NixOS/Home Manager modules and package but will not modify or remove the active staged Serpantinum/NixOS work. Later migration can switch the settings owner and retire the existing patch after Gridwatch is validated.

### Product scope by milestone

- **Foundation:** live energy core; line/load/charge/runtime/battery telemetry; connection freshness; on-battery session banner; device/firmware details; event timeline; desktop/in-app alerts; local history; demo mode. Poll live state every five seconds, persist changed/raw samples for 24 hours, one-minute aggregates for 90 days, and hourly aggregates indefinitely by default, all configurable.
- **Power analytics:** outage duration/frequency, transfer reasons, min/max voltage, load and runtime trends, actual-discharge-vs-estimate comparison, estimated watts/kWh and configurable local energy cost, battery age/charge-time signals, and explainable health recommendations.
- **Configuration:** effective/draft shutdown threshold and time-on-battery policy, notification/silent-hours preferences, retention and energy-rate settings, plus capability-gated sensitivity, transfer voltage, UPS alarm, self-test cadence, battery replacement date, and shutdown/hibernate action when supported.
- **Maintenance:** communication checks, daemon/agent status, exportable diagnostic bundle with serial redaction, self-test preparation/results, battery replacement acknowledgement, and auditable action history.
- **Calibration Lab:** capability probe, readiness score, stable-load observation window, explicit hold-to-confirm, scheduled reminder/maintenance window, live discharge/recharge progress, abort/failure recovery, result comparison, cooldown, and a guided manual path when software calibration is unsupported.
- **Not in the initial app:** LAN/multi-host monitoring, multiple UPS devices, cloud accounts, SMTP/webhooks, outlet-group control, firmware updates, or edits to the current Serpantinum/NixOS deployment; the architecture keeps extension seams for these.

## Files to modify

Expected greenfield paths:

- `package.json`, `bun.lock`, `bun.nix`, `tsconfig.json` — pinned GPUIX/React toolchain, scripts, compile target, and reproducible Bun dependencies.
- `src/main.tsx` and `src/app/` — GPUIX bootstrap, Gridwatch shell/navigation, shared state, keyboard handling, and error boundaries.
- `src/notifier.ts` and `src/agent-client/` — headless user-session notification relay and typed/versioned agent RPC client.
- `src/ui/` and `assets/` — Electric Observatory tokens, reusable controls/cards/overlays, icons, generated-SVG chart renderer, motion, and accessibility helpers.
- `src/domain/` — typed telemetry, status/event normalization, capability flags, settings schema, calibration state machine, and health insights.
- `src/backends/apcupsd/` — safe process wrapper, `apcaccess` parser, local event reader, polling/reconnect logic, and fixtures.
- `src/storage/` — UI-side query models; the system agent is the sole SQLite writer and serves bounded history queries over RPC.
- `src/features/{overview,history,events,device,settings,diagnostics,calibration}/` — product screens and workflows.
- `protocol/gridwatch-v1.schema.json` — bounded request/event payloads shared by the TypeScript client and Rust service with compatibility fixtures.
- `agent/Cargo.toml` and `agent/src/` — always-on root service, SQLite telemetry/history writer, local alert evaluator, peer-credential/Polkit authorization, Unix-socket JSON protocol, policy/config generation, self-test/calibration orchestration, scheduler, and audit log.
- `nix/package.nix`, `nix/module.nix`, `nix/home-manager.nix`, `nix/gridwatch.policy`, `flake.nix`, `gridwatch.desktop`, desktop icon metadata — bun2nix/offline build, pre/post-embed ELF patching, Vulkan/Wayland/X11 runtime wrapping, and disabled-by-default app/system-agent/apcupsd integration.
- `tests/` and colocated `*.test.ts(x)` / Rust tests — parsers, reducers/state machines, storage, protocol, policy, failure recovery, and deterministic device scenarios.
- No external Serpantinum or active NixOS configuration files in the initial implementation; migration is explicitly deferred.

## Reuse

- `/home/surya/Dotfiles/nixos-config/modules/desktop/serpantinum-ups/ups_status.sh` — preserve the `value`/`number`/`text` field extraction behavior and missing-device fallbacks, but replace shell/awk/jq with typed parsing.
- `/home/surya/Dotfiles/nixos-config/modules/hardware/ups-policy.py` — port `bounded_integer`, `load_policy`, `render_config`, and `atomic_write` semantics into the Rust agent.
- `/home/surya/Dotfiles/nixos-config/modules/hardware/ups.nix` — reuse the `generateRuntimeConfig` flow, local-only NIS (`127.0.0.1:3551`), USB driver/event paths, controlled systemd restart behavior, and packaged `apccontrol` scripts.
- `/home/surya/Dotfiles/nixos-config/tests/test_ups_policy.py` — carry forward malformed/missing settings, clamping, local USB/NIS config, and idempotence expectations as new project tests.
- `/var/log/apcupsd.events` and `journalctl -u apcupsd.service` — existing event vocabulary to normalize/import (power failure, on battery, mains restored, exhausted battery, service lifecycle).
- GPUIX’s official `README.md` and `example-app` — `render`, React hooks, tokenized styles, embedded SVG icons, `motion.div`, accessibility props, `bun --hot`, `bun build --compile`, and Vitest testing APIs; account for the documented lack of Linux GPU screenshot tests.
- APC/Schneider self-test and calibration guidance plus apcupsd protocol/release documentation — derive readiness thresholds, battery-wear warnings, capability probes, and abort semantics rather than assuming every Back-UPS supports software calibration.
- `bun2nix`, Nixpkgs `autoPatchelfHook`, and GPUIX’s Linux CI dependency list — reproducible dependencies and the Vulkan/fontconfig/Wayland/X11 libraries needed by the embedded N-API renderer.
- Serpantinum’s QML patch files are reference behavior only; they are not imported or edited in this app-only phase.

## Steps

- [x] Scaffold the Bun/React/GPUIX app and Rust system-agent workspace with pinned dependencies, lint/typecheck/test/build scripts, shared versioned protocol schema, and a reproducible Nix dev shell.
- [x] Define the typed UPS model, capability matrix, normalized states/units/events, parser fixtures from the RS 1500G-IN, and simulated backend before building UI.
- [x] Establish the Electric Observatory design system and responsive shell, then implement Overview, History, Events/Alerts, Device, Settings, Diagnostics, and Calibration Lab routes with empty/loading/stale/offline/degraded states.
- [x] Implement read-only `apcupsd` integration, resilient polling, event import, SQLite sampling/downsampling/retention, derived outage/runtime/load/cost insights, always-on local alert evaluation, in-app inbox, and an unprivileged desktop-notification relay.
- [x] Implement and harden the root agent: peer-credential-restricted socket, Polkit authorization for mutations, schema/version handshake, bounded RPC, policy validation/atomic persistence, generated runtime config, controlled reload/rollback, audit logging, database ownership, and least-privilege systemd sandboxing.
- [x] Add user settings and capability-gated UPS controls; distinguish estimated values from directly measured values and effective configuration from unsaved drafts.
- [x] Add self-test preparation/results, then capability-probe calibration support and implement the guarded scheduler/state machine with load observation, confirmation, live progress, abort, recovery, recharge verification, cooldown, and unsupported-device guidance.
- [x] Package with bun2nix, patch the embedded GPUIX N-API addon before compilation, wrap Vulkan/fontconfig/Wayland/X11/XKB runtime paths, build the Rust agent, and expose disabled-by-default NixOS/Home Manager modules.
- [x] Add deterministic automated coverage, demo/simulation mode, operator documentation, safety warnings, diagnostics export/redaction, and a later migration guide from Serpantinum.

## Verification

- Run `bun run typecheck`, lint/format checks, Vitest unit/component tests, Rust format/Clippy/tests, protocol compatibility tests, SQLite migration tests, and production builds.
- Evaluate `nix flake check`; verify bun2nix’s offline dependency closure and GPUIX native-addon ELF/RPATH handling; build/run on NixOS with Vulkan, Wayland, and X11 fallbacks.
- Validate the opt-in NixOS/Home Manager modules in a VM/test configuration, including disabled-by-default behavior, service sandboxing, socket peer/group permissions, Polkit allow/deny/challenge paths, user notifier routing, startup ordering, restart rollback, and unread-alert replay.
- Replay deterministic fixtures for online, on-battery, low/exhausted battery, mains return, overload, replace-battery, communication loss/staleness, malformed output, daemon restart, self-test, supported/unsupported calibration, abort, and interrupted-agent recovery.
- Verify sampling retention/downsampling, power/cost integration, alert deduplication/silent hours, bounded history queries, DB migration/backup, audit immutability, and serial redaction in diagnostics.
- Verify the RS 1500G-IN read-only path first; run self-test/calibration hardware checks only with explicit user approval and a safe non-critical load. Confirm `apcupsd` is always restored and history survives GUI/agent restarts.
- Manually verify Wayland/X11 startup, desktop notifications, generated-SVG charts, keyboard/focus/accessibility metadata, reduced-motion behavior, responsive layouts, error recovery, and Electric Observatory polish. GPUIX Linux lacks GPU screenshot capture, so visual regression is manual/screenshot-assisted while pure layout/state logic stays automated.
- Confirm the build does not read or alter Serpantinum settings or `/home/surya/Dotfiles/nixos-config`, and that installing the package alone does not activate the privileged agent or replace the active `apcupsd` configuration.
