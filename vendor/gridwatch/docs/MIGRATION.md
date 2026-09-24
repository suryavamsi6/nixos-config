# Serpantinum migration later

The first Gridwatch release is app-only. It does not read `/home/surya/.config/serpantinum/settings.json`, patch Serpantinum, or alter the active NixOS configuration.

Gridwatch's own module is disabled by default, and enabling it with `enableApcupsd = false` (the default) keeps the agent read-only: shutdown thresholds are refused with `policy-owner-unavailable` instead of being written anywhere.

After Gridwatch has been exercised against the APC Back-UPS RS 1500G-IN:

1. Export the effective shutdown policy from Gridwatch.
2. Enable the Gridwatch NixOS module in a test generation with `enableApcupsd = true` and `manageShutdownPolicy = true` so apcupsd uses the Gridwatch-owned runtime configuration.
3. Disable the Serpantinum UPS page and policy watcher.
4. Verify `apcupsd` ownership (atomically applied `BATTERYLEVEL`/`MINUTES` with health verification and rollback), event history, notifications, and shutdown behavior.
5. Remove the old patch only after a rollback generation is available.