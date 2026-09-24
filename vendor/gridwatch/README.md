# Gridwatch

Gridwatch is a native GPUIX/Bun dashboard for an APC UPS on NixOS. It currently targets the APC Back-UPS RS 1500G-IN through `apcupsd` and is intentionally safe-by-default: read-only monitoring works without root, while maintenance actions are capability-gated and agent-mediated.

## Development

```sh
bun install
bun run typecheck
bun test
bun run dev
```

Use `GRIDWATCH_DEMO=1 bun run dev` to run against deterministic simulated telemetry. The Nix flake provides Bun, Rust, apcupsd, and Linux GPUI/Vulkan dependencies.

The app is not yet a replacement for the existing Serpantinum integration. Its NixOS module is opt-in and does not read or modify Serpantinum settings.
