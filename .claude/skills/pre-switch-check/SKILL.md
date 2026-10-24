---
name: pre-switch-check
description: Parse-check changed Nix files and dry-build the target host before switching. Run before nh os switch.
disable-model-invocation: true
---

# Pre-switch check

Run this before the user switches. Accept an optional host argument (`nixos`, `mango`, `raspberry-pi`, `macbook-air`); default to `nixos` per repo convention.

1. Find changed Nix files:
   - `git diff --name-only --diff-filter=ACMR HEAD -- '*.nix'` plus `git status --porcelain -- '*.nix'` (also try `jj diff --summary` if git looks stale — this repo has a jj colocated working copy).
   - If nothing changed, say so and stop.
2. Parse-check each changed file:
   `nix-instantiate --parse <file>` — collect all failures, show them, and stop if any fail (do not dry-build a flake that cannot parse).
3. Dry-build the host (safe — evaluates and builds, never activates):
   - Linux hosts: `nixos-rebuild dry-build --flake .#<host>`
   - macbook-air: `nix-darwin build --flake .#macbook-air`
   This can take a while on first run; report progress, don't abort early.
4. Report: files checked, parse results, build result, and which services/surfaces the diff touches.

Hard rules (from AGENTS.md — do not violate):
- NEVER run `nh os switch`, `nixos-rebuild switch`, `darwin-rebuild switch`, reboot, or anything that activates. The user runs `nh os switch` themselves.
- After a Home Manager/Quickshell-only change, tell the user: once switched, `systemctl --user restart quickshell` is enough.
