# 1Password MCP — exposes vault reads (item fields, passwords, TOTP) to the
# Claude clients on this host.
#
# Both clients are configured, because they read different files and neither
# one picks up the other's list:
#
#   Claude Code CLI   ~/.claude.json
#   Claude Desktop    ~/.config/Claude/claude_desktop_config.json
#
# Both are read at client start, so restart the app (or the CLI session) after
# a switch for the server to appear.
#
# Both files are owned by the applications, not by this flake: the CLI writes
# project history and the desktop writes window/session state into them. So
# they are merged, never replaced — the activation script sets exactly one key
# (mcpServers.onepassword) and leaves every other key untouched. This mirrors
# home.activation.piConfig in dev.nix, which merges pi's app-owned keys the
# same way.
#
# Server invocation
# -----------------
# `opMcpCmd`/`opMcpArgs` below are the single place the server is named. The
# command runs as a stdio MCP server and needs `op` itself on PATH: the
# desktop module enables programs._1password (the CLI) and the GUI's SSH agent
# is what already signs git commits, so an authenticated `op` session is
# normally present.
#
# IMPORTANT: confirm the package name before switching. If it is wrong the
# server exits immediately and the client shows *no tools*, silently — there
# is no loud failure. Verify with:
#
#     npx -y <pkg> --help
#
# then correct opMcpArgs if the real name differs.
#
# Credentials are never stored here. The server authenticates through `op`,
# so access is bounded by the 1Password session and vault permissions of the
# logged-in user — nothing in this repo grants vault access.
{ lib, ... }:
{
  options.flake.modules.homeManager.onepasswordMcp = lib.mkOption {
    type = lib.types.deferredModule;
    # `lib` must be destructured here: the module-level lib is nixpkgs' and has
    # no `hm`, so `lib.hm.dag` only resolves against Home Manager's lib, which
    # this shadowing binding provides (same pattern as dev.nix).
    default =
      { pkgs, lib, ... }:
      let
        # Name used in both clients' mcpServers maps.
        serverName = "onepassword";

        # Absolute path on purpose: nodejs is not in this host's home.packages
        # (only `bun` is), so a bare "npx" resolves to nothing and the server
        # dies at spawn with no tools and no visible error.
        opMcpCmd = "${pkgs.nodejs_22}/bin/npx";

        # TODO(verify): confirm this is the real package name (see header).
        opMcpArgs = [
          "-y"
          "@1password/mcp"
        ];

        serverJson = builtins.toJSON {
          command = opMcpCmd;
          args = opMcpArgs;
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
        '';
      };
  };
}
