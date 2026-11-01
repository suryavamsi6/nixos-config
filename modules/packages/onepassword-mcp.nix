# 1Password Environments MCP — lets supported clients manage Environments
# without returning secret values to the agent.
#
# Clients are configured in their own user config files:
#
#   Claude Code CLI   ~/.claude.json
#   Claude Desktop    ~/.config/Claude/claude_desktop_config.json
#   Codex              ~/.codex/config.toml (via `codex mcp add`)
#
# Restart the client after a switch for the server to appear. In Codex, find it
# under MCP servers, not the Apps list.
#
# Both files are owned by the applications, not by this flake: the CLI writes
# project history and the desktop writes window/session state into them. So
# they are merged, never replaced — the activation script sets exactly one key
# (mcpServers.onepassword) and leaves every other key untouched. This mirrors
# home.activation.piConfig in dev.nix, which merges pi's app-owned keys the
# same way.
#
# The MCP binary ships with the 1Password desktop package. Credentials are
# never stored here; the server uses the desktop app's local authorization.
{ lib, ... }:
{
  options.flake.modules.homeManager.onepasswordMcp = lib.mkOption {
    type = lib.types.deferredModule;
    # `lib` must be destructured here: the module-level lib is nixpkgs' and has
    # no `hm`, so `lib.hm.dag` only resolves against Home Manager's lib, which
    # this shadowing binding provides (same pattern as dev.nix).
    default =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      let
        # Name used in each client's MCP server map.
        serverName = "onepassword";
        opMcpCmd = "${pkgs._1password-gui}/share/1password/1password-mcp";
        codexBin = "${config.home.profileDirectory}/bin/codex";

        serverJson = builtins.toJSON {
          command = opMcpCmd;
          args = [ ];
        };

        # Create the file if absent; add or replace only our server and leave
        # every other key alone. Written to a temp file and moved into place so
        # a half-written config can never be left behind.
        jq = "${pkgs.jq}/bin/jq";
      in
      {
        home.activation.onepasswordMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -eu
          server=${lib.escapeShellArg serverJson}
          name=${lib.escapeShellArg serverName}

          merge() {
            target="$1"
            mkdir -p "$(dirname "$target")"

            # These files belong to the applications, so treat their contents
            # as untrusted input: they can be mid-write, or hand-edited into
            # invalid JSON. A parse failure must not abort the whole switch —
            # warn, leave the file exactly as it is, and carry on.
            if [ -f "$target" ]; then
              if ! ${jq} -e . "$target" >/dev/null 2>&1; then
                echo "onepassword-mcp: $target is not valid JSON; leaving it untouched" >&2
                return 0
              fi
              src="$target"
            else
              printf '{}\n' > "$target"
              src="$target"
            fi

            tmp="$target.tmp.$$"
            if ${jq} --argjson server "$server" --arg name "$name" \
                 '.mcpServers = ((.mcpServers // {}) | .[$name] = $server)' \
                 "$src" > "$tmp"; then
              chmod 600 "$tmp"
              mv "$tmp" "$target"
            else
              echo "onepassword-mcp: failed to merge into $target" >&2
              rm -f "$tmp"
              return 0
            fi
          }

          # Claude Code CLI (user scope). Merge so per-project history and
          # oauth state in this file survive.
          merge "$HOME/.claude.json"

          # Claude Desktop.
          merge "$HOME/.config/Claude/claude_desktop_config.json"

          # Codex owns its TOML config and exposes this entry in Settings >
          # MCP servers. Use Codex's CLI so its other settings stay intact.
          if [ -x ${lib.escapeShellArg codexBin} ]; then
            current=$(${lib.escapeShellArg codexBin} mcp get "$name" 2>/dev/null || true)
            if ! printf '%s\n' "$current" | grep -Fq ${lib.escapeShellArg "command: ${opMcpCmd}"}; then
              if [ -n "$current" ]; then
                ${lib.escapeShellArg codexBin} mcp remove "$name"
              fi
              ${lib.escapeShellArg codexBin} mcp add "$name" -- ${lib.escapeShellArg opMcpCmd}
            fi
          else
            echo "onepassword-mcp: codex is not on PATH; skipped Codex configuration" >&2
          fi
        '';
      };
  };
}
