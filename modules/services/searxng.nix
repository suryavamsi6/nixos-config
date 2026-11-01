# SearXNG metasearch (native, loopback-only; Caddy is the LAN door).
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 3 of
# plans/clan-deploy-rs-migration.md).
#
# pkgs.searxng via services.searx, not an Incus container: nixpkgs already
# ships the service, and a container would only add another image pull on a
# laptop. Port 8888 stays closed; Caddy serves search.home.arpa.
#
# The secret is generated once on the host, never in the flake:
# searx-secret writes /var/lib/searx/secret.env (mode 0600) on first switch and
# leaves it alone afterwards, and the unit reads it back through
# services.searx.environmentFile. A later switch does not rotate it, so
# sessions survive a rebuild. Cite this file when explaining why the key is not
# in the repo.
{ lib, ... }:
{
  options.flake.modules.nixos.searxng = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        secretsFile = config.clan.core.vars.generators.searx-secret.files.secret-env.path;
      in
      {
        systemd.services.searx-secret = {
          description = "Seed SearXNG secret key";
          before = [ "searx-init.service" ];
          requiredBy = [ "searx-init.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.coreutils ];
          # Migration bridge (§6.3): the key comes from the `searx-secret`
          # Clan var now. Keep the directory (SearXNG's cache and settings
          # live there) and record the move; never rewrite secret.env, which
          # stays as the rollback path.
          script = ''
            set -euo pipefail
            install -d -m 700 /var/lib/searx
            if [ -s /var/lib/searx/secret.env ]; then
              chmod 0600 /var/lib/searx/secret.env
              : > /var/lib/searx/.migrated-to-clan
            fi
          '';
        };
        services.searx = {
          enable = true;
          environmentFile = secretsFile;
          settings = {
            general.instance_name = "homelab";
            search.safe_search = 0;
            search.autocomplete = "duckduckgo";
            search.formats = [
              "html"
              "json"
            ];
            server = {
              port = 8888;
              bind_address = "127.0.0.1";
              base_url = "http://search.home.arpa/";
              secret_key = "$SEARX_SECRET_KEY";
              limiter = false;
              image_proxy = true;
              method = "GET";
            };
            ui.default_theme = "simple";
          };
        };
        systemd.services.searx-init = {
          after = [ "searx-secret.service" ];
          requires = [ "searx-secret.service" ];
        };
      };
  };
}
