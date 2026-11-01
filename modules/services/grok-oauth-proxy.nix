# Grok OAuth proxy: a SuperGrok subscription as an OpenAI-compatible API.
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 5 of
# plans/clan-deploy-rs-migration.md). It carries its own derivation because
# dvcrn/grok-oauth-proxy publishes no container image: the package is built from
# source, pinned to a commit, and bumping it means updating rev plus both
# hashes below.
#
# Two faces, one process: /v1 is the OpenAI-compatible API, /mcp is a stateless
# MCP server. It listens on the loopback only and Caddy serves grok.home.arpa;
# Caddy also holds the /grok/* leg that Bifrost calls with the admin key
# injected, which is why the secrets file stays 0600 grok-oauth-proxy.
#
# Secrets: ADMIN_API_KEY is generated once into
# /var/lib/grok-oauth-proxy/secrets.env and never enters the flake. Gatus reads
# the same file as GROK_ADMIN_KEY (the host wires
# services.gatus.environmentFile to it), so the check authenticates without the
# key being rendered into YAML.
#
# OAuth login is interactive and deliberate: run
#   sudo systemctl start grok-oauth-proxy-login
# and follow the URL it prints. Tokens then live under the state dir.
{ lib, ... }:
{
  options.flake.modules.nixos.grokOauthProxy = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        # Clan var, not /var/lib. The file stays owned by the service user and
        # 0400 so `ProtectSystem = "strict"` below still works: /run/secrets is
        # tmpfs and the var file is chowned to grok-oauth-proxy at decrypt time.
        secretsFile = config.clan.core.vars.generators.grok-oauth.files.secrets-env.path;
        grokOauthProxy = pkgs.buildGoModule (finalAttrs: {
          pname = "grok-oauth-proxy";
          version = "1.0.1-unstable-2026-09-08";
          src = pkgs.fetchFromGitHub {
            owner = "dvcrn";
            repo = "grok-oauth-proxy";
            rev = "041025fb786663c400471b58ffd79939752351fa";
            hash = "sha256-WyS0ZU80wcCqJ06v5KIZ12F7Eg0wuI2EFmGsG5wNWw8=";
          };
          vendorHash = "sha256-GjV/PJULV6AVTImJ5TeRKhKJypS5b2E6ElTTYP9tFfE=";
          meta = {
            description = "OAuth API proxy for using a Grok subscription in other harnesses";
            homepage = "https://github.com/dvcrn/grok-oauth-proxy";
            mainProgram = "grok-oauth-proxy";
          };
        });
      in
      {
        users.groups.grok-oauth-proxy = { };
        users.users.grok-oauth-proxy = {
          isSystemUser = true;
          group = "grok-oauth-proxy";
          home = "/var/lib/grok-oauth-proxy";
          createHome = true;
        };

        # ── Migration bridge (plans/clan-deploy-rs-migration.md §6.3) ──────
        # The three keys now come from the `grok-oauth` Clan var. This unit is
        # kept as the ordering anchor the two services below still require, and
        # only ensures the old state directory still exists (the OAuth token
        # cache lives there and is NOT a secret var) plus a marker file.
        #
        # It never writes secrets.env again: the old file is the rollback path.
        systemd.services.grok-oauth-proxy-secrets = {
          description = "Keep grok-oauth-proxy state dir; secrets moved to Clan vars";
          wantedBy = [ "multi-user.target" ];
          requiredBy = [
            "grok-oauth-proxy.service"
            "gatus.service"
          ];
          before = [
            "grok-oauth-proxy.service"
            "gatus.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          path = [
            pkgs.coreutils
          ];
          script = ''
            set -euo pipefail
            install -d -m 700 -o grok-oauth-proxy -g grok-oauth-proxy /var/lib/grok-oauth-proxy
            if [ -s /var/lib/grok-oauth-proxy/secrets.env ]; then
              chown grok-oauth-proxy:grok-oauth-proxy /var/lib/grok-oauth-proxy/secrets.env
              : > /var/lib/grok-oauth-proxy/.migrated-to-clan
            fi
          '';
        };

        systemd.services.grok-oauth-proxy = {
          description = "grok-oauth-proxy (SuperGrok -> OpenAI-compatible API)";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            User = "grok-oauth-proxy";
            Group = "grok-oauth-proxy";
            ExecStart = "${grokOauthProxy}/bin/grok-oauth-proxy";
            Environment = [ "HOME=/var/lib/grok-oauth-proxy" ];
            EnvironmentFile = secretsFile;
            Restart = "on-failure";
            RestartSec = "5";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [ "/var/lib/grok-oauth-proxy" ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };

        # One-time browser login. The OAuth callback always lands on
        # 127.0.0.1:56121, so tunnel it from the machine with the browser:
        #   ssh -L 56121:127.0.0.1:56121 surya@homelab.home.arpa
        #   sudo systemctl stop grok-oauth-proxy
        #   sudo systemctl start grok-oauth-proxy-login
        # then open http://127.0.0.1:56121/login there and finish the flow.
        # Tokens land in /var/lib/grok-oauth-proxy/.config/grok-oauth-proxy/.
        # Start grok-oauth-proxy again once the login unit exits.
        systemd.services.grok-oauth-proxy-login = {
          description = "grok-oauth-proxy one-time OAuth login (needs the SSH tunnel)";
          after = [ "grok-oauth-proxy-secrets.service" ];
          conflicts = [ "grok-oauth-proxy.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "grok-oauth-proxy";
            Group = "grok-oauth-proxy";
            ExecStart = "${grokOauthProxy}/bin/grok-oauth-proxy auth";
            Environment = [ "HOME=/var/lib/grok-oauth-proxy" ];
            EnvironmentFile = secretsFile;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };
      };
  };
}
