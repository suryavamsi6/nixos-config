#!/usr/bin/env bash
# One-shot installer for Claude Code automation in this repo:
#   .claude/settings.json  — hooks (nixfmt on edit + nix parse check)
#   .claude/agents/        — module-wiring-reviewer, pi-security-reviewer
#   .claude/skills/        — symlink to .agents/skills/nixos-config, pre-switch-check
#   .mcp.json              — mcp-nixos (uvx) + GitHub MCP (HTTP, OAuth on first use)
#
# Usage:  bash scripts/setup-claude.sh
# Safe to re-run; existing files are backed up to *.bak before overwrite.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

install_file() {
  local dest=$1
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    cp "$dest" "$dest.bak"
    echo "  backed up existing $dest -> $dest.bak"
  fi
  mkdir -p "$(dirname "$dest")"
  cat > "$dest"
  echo "  wrote $dest"
}

# Pre-flight checks
for cmd in jq nix; do
  command -v "$cmd" >/dev/null 2>&1 || echo "WARN: '$cmd' not found on PATH — hooks may not work"
done
command -v nixfmt >/dev/null 2>&1 || echo "WARN: 'nixfmt' not found on PATH — format hook will be skipped"
command -v uvx >/dev/null 2>&1 || echo "WARN: 'uvx' not found — install uv (pacman -S uv or curl -LsSf https://astral.sh/uv/install.sh | sh) for the nixos MCP server"

echo "==> Installing .claude/settings.json (hooks)"
install_file .claude/settings.json <<'SETTINGS'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "f=$(jq -r '.tool_input.file_path // empty'); case \"$f\" in *.nix) command -v nixfmt >/dev/null 2>&1 && nixfmt \"$f\" 2>/dev/null || true ;; esac"
          },
          {
            "type": "command",
            "command": "f=$(jq -r '.tool_input.file_path // empty'); case \"$f\" in *.nix) if ! out=$(nix-instantiate --parse \"$f\" 2>&1); then printf 'Nix parse failed for %s:\\n%s\\nFix the syntax error before proceeding.\\n' \"$f\" \"$out\" >&2; exit 2; fi ;; esac"
          }
        ]
      }
    ]
  }
}
SETTINGS

echo "==> Installing .claude/agents/module-wiring-reviewer.md"
install_file .claude/agents/module-wiring-reviewer.md <<'AGENT1'
---
name: module-wiring-reviewer
description: Reviews Nix module changes for this repo's #1 failure mode — a flake.modules.* option declared in a leaf file but never imported into the module tree or selected by any host. Use after adding or editing .nix modules.
tools: Read, Glob, Grep, Bash
---

You are reviewing a flake-parts NixOS/Home Manager/nix-darwin configuration. Read AGENTS.md and .agents/skills/nixos-config/modules.md first for the architecture.

Your single most important check: **an orphan module is a silent bug.** In this repo a module only takes effect when (a) its file is imported transitively from `modules/default.nix`, AND (b) the option it defines is selected in at least one host file under `modules/hosts/`. Defining the file alone does nothing.

Workflow:
1. Run `git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null || true` and `git status --porcelain` to find changed/new `.nix` files. If the repo uses jj, also try `jj diff --summary`. Fall back to asking which files changed if git history is unclear.
2. For each changed/new module file, extract every `options.flake.modules.{nixos,homeManager,darwin}.<name>` declaration.
3. For each declaration verify:
   - The file is reachable from `modules/default.nix` through the import chain (trace it; name the importing parent file).
   - The option is actually `flake.modules.<kind>.<name>`-selected inside at least one host composition file in `modules/hosts/` (or intentionally dormant — flag dormant ones as INFO, not error).
4. Convention spot-checks on changed files only:
   - Hyprland config changes belong in `modules/hyprland/lua/*.lua`, not hyprlang.
   - No credentials, API keys, Wi-Fi PSKs, or work usernames anywhere.
   - Serpantinum patches keep their ordering (patchTopBar after clock substitutions).

Report format: one line per finding, `[ERROR]` (orphan module, broken import, secret leak), `[WARN]` (convention drift), or `[INFO]` (dormant-but-valid module). Always cite file:line. End with a one-sentence verdict: safe to hand back to the main session, or list what must be fixed first. You are read-only — never edit files.
AGENT1

echo "==> Installing .claude/agents/pi-security-reviewer.md"
install_file .claude/agents/pi-security-reviewer.md <<'AGENT2'
---
name: pi-security-reviewer
description: Security and correctness review of the Raspberry Pi server configuration (modules/hosts/nixos-raspberry-pi.nix and related networking/container modules) — secrets, firewall exposure, container wiring, mounts. Use before deploying Pi changes.
tools: Read, Glob, Grep, Bash
---

You are a security reviewer for the `#raspberry-pi` NixOS host (aarch64, hostname `pi`, user `suryavamsi`). It runs SSH, Tailscale, Nginx, Cockpit, AdGuard Home, Unbound with Redis caching, and Podman containers (MariaDB, Nextcloud, Booklore, Speedtest Tracker).

Scope: read `modules/hosts/nixos-raspberry-pi.nix` plus anything it imports (networking, firewall, container modules). You are read-only — never edit files, never suggest running rebuilds.

Check for:
1. **Secrets**: any inline password, token, API key, or Wi-Fi PSK. Credentials must live in referenced external `.env` files or generated state, never in the repo. Also flag secret-looking strings in comments or default values.
2. **Firewall/exposure**: `allowedTCPPorts`/`allowedUDPPorts` — every open port must map to an identifiable service. Flag anything bound to 0.0.0.0 that should be loopback-only or Tailscale-only (Cockpit and admin surfaces are prime candidates). Check reverse-proxy vhosts route through Nginx rather than exposing upstream ports directly.
3. **Container wiring**: virtualisation.oci-containers units must keep `dependsOn`, network, volume, and `environmentFiles` wiring intact. Flag env values inlined that should come from env files, and env files referenced that don't have `environmentFile` permissions noted.
4. **Storage**: bind mounts under `/mnt/media`, `/var/lib/AdGuardHome`, `/var/lib/redis-unbound` — check mount path consistency, and that service units that need the mounts order after them.
5. **DNS chain**: AdGuard -> Unbound -> Redis caching — flag config that would break resolution or cache persistence.

Report format: `[CRITICAL]` (secret in repo, unintended exposure), `[WARN]` (fragile wiring, missing dependency ordering), `[INFO]` (observation). Cite file:line. Never print secret contents — reference their location only. End with a verdict: safe to deploy, or the blocking items.
AGENT2

echo "==> Installing .claude/skills/pre-switch-check"
install_file .claude/skills/pre-switch-check/SKILL.md <<'SKILL'
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
SKILL

echo "==> Symlinking .claude/skills/nixos-config -> .agents/skills/nixos-config"
mkdir -p .claude/skills
if [[ -e .claude/skills/nixos-config || -L .claude/skills/nixos-config ]]; then
  echo "  already exists, skipping"
else
  ln -s ../../.agents/skills/nixos-config .claude/skills/nixos-config
  echo "  linked"
fi

echo "==> Installing .mcp.json"
install_file .mcp.json <<'MCPJSON'
{
  "mcpServers": {
    "nixos": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-nixos"],
      "env": {}
    },
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/"
    }
  }
}
MCPJSON

cat <<'NOTES'

Done. Next steps:

1. Restart Claude Code in this repo (or start a new session) so hooks/skills/MCP load.
2. First MCP use: the 'nixos' server launches via uvx (may download once).
   The 'github' server will prompt you to sign in with OAuth on first use.
   Verify both with:  /mcp
3. Project hooks and MCP servers are trust prompts — Claude Code will ask you
   to approve them on first load. Approve to enable.
4. Decide whether to commit the new files. For a solo repo, committing
   .claude/ and .mcp.json keeps the setup synced across machines; add both
   to .gitignore instead if you'd rather keep them local.
5. Sanity-check the hooks: ask Claude to edit any .nix file and watch for a
   nixfmt reformat + parse check afterwards.

NOTES
