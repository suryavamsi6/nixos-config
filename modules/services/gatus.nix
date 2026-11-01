# Gatus uptime/health checks (loopback-only; Caddy is the door).
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 2 of
# plans/clan-deploy-rs-migration.md). Replaces Uptime Kuma. Checks live here,
# history in SQLite under the module's StateDirectory. No notifier is
# configured: ntfy/email tokens do not belong in the flake. Add one later with
# services.gatus.environmentFile.
#
# Caddy keeps the old name: status.home.arpa -> 127.0.0.1:3001. Every URL is a
# loopback address or a LAN address, so this host is the only thing that can
# meaningfully run the probe.
#
# Which checks are here, and why:
#   homelab group - homepage, home-assistant, hermes, booklore, searxng,
#                   reactive-resume, netdata, homelable, bifrost, nutify;
#                   the two /disk/health.json + restic state probes come from
#                   homelab-stats (:8793), which reads the snapshots written by
#                   disk-health.timer and the nightly restic status files, so a
#                   missing snapshot or a failed run is red here;
#                   grok-oauth-proxy is probed on /mcp (POST tools/list) rather
#                   than /v1/models, because the MCP path answers locally: it
#                   proves the process is up and the admin key is accepted
#                   without forwarding to api.x.ai, which would flap red
#                   whenever the SuperGrok weekly quota is exhausted.
#                   Qdrant is deliberately absent: it exposes no
#                   unauthenticated liveness route (see the comment inline).
#   hosts group   - ICMP for homelab + pi.
#   pi group      - nextcloud, speedtest, cockpit, ssh. Both pi web apps are
#                   probed through their own names, not 127.0.0.1:PORT: those
#                   loopback URLs only exist on the pi, so from this host they
#                   always failed and Gatus showed false reds.
#   dns group     - adguard answers DNS on the LAN address, so query a name it
#                   rewrites; a dead resolver fails here, not only in a browser.
{ lib, ... }:
{
  options.flake.modules.nixos.gatus = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { ... }:
      {
        services.gatus = {
          enable = true;
          settings = {
            web.address = "127.0.0.1";
            web.port = 3001;
            ui = {
              title = "homelab";
              header = "LAN checks";
              default-sort-by = "group";
            };
            storage = {
              type = "sqlite";
              path = "/var/lib/gatus/data.db";
              caching = true;
            };
            endpoints =
              let
                http = group: name: url: extra: {
                  inherit name group url;
                  interval = "1m";
                  conditions = [
                    "[STATUS] == 200"
                    "[RESPONSE_TIME] < 3000"
                  ]
                  ++ extra;
                  client.timeout = "10s";
                };
                tcp = group: name: url: {
                  inherit name group url;
                  interval = "1m";
                  conditions = [ "[CONNECTED] == true" ];
                  client.timeout = "5s";
                };
              in
              [
                (http "homelab" "homepage" "http://127.0.0.1:8082" [ ])
                (http "homelab" "home-assistant" "http://10.110.0.10/" [ ])
                (http "homelab" "hermes" "http://10.110.0.50:9119/" [ ])
                (http "homelab" "booklore" "http://10.110.0.61:6060/" [ ])
                (http "homelab" "searxng" "http://127.0.0.1:8888/" [ ])
                (http "homelab" "reactive-resume" "http://10.110.0.80:3000/api/health" [ ])
                (http "homelab" "netdata" "http://127.0.0.1:19999/api/v1/info" [ ])
                (http "homelab" "homelable" "http://10.110.0.91/" [ ])
                (http "homelab" "bifrost" "http://10.110.0.100:8080/health" [ ])
                # Nutify answers 302 (login) until an admin is configured and
                # 200 afterwards, so both count as up. No NUT server is
                # configured yet, so this only proves the container serves.
                #   sudo incus exec nutify -- env | grep NUT
                {
                  name = "nutify";
                  group = "homelab";
                  url = "http://nutify.home.arpa/";
                  interval = "1m";
                  conditions = [ "[STATUS] == 200 || [STATUS] == 302" ];
                  client.timeout = "10s";
                }
                # SMART and backup state come from homelab-stats, which reads
                # the snapshots written by disk-health.timer and the restic
                # status files. Both probes answer 200 with an `ok` field, so
                # a missing snapshot or a failed nightly run is red here.
                (http "homelab" "smart-disks" "http://127.0.0.1:8793/disk/health.json" [
                  "[BODY].ok == true"
                ])
                # Qdrant exposes no unauthenticated liveness route: with an
                # API key set, /healthz and / are 401. /readyz would be the
                # right probe but it also needs the key, and Gatus cannot
                # read /var/lib/qdrant-secrets. Incus's own container health
                # is the check here; inspect collections with `incus exec`.
                #   sudo incus exec qdrant -- curl -s -H "api-key: $(sudo sed -n 's/^QDRANT_API_KEY=//p' /var/lib/qdrant-secrets/api-key)" localhost:6333/collections
                # Authenticated check; see grok-oauth-proxy-secrets.
                # Probe /mcp (POST tools/list) rather than /v1/models: the
                # MCP path answers locally, so this proves the process is up
                # and the admin key is accepted without touching api.x.ai.
                # /v1/models forwards upstream and would flap red whenever
                # the SuperGrok weekly quota is exhausted.
                {
                  name = "grok-oauth-proxy";
                  group = "homelab";
                  url = "http://127.0.0.1:56121/mcp";
                  interval = "1m";
                  method = "POST";
                  body = ''{"jsonrpc":"2.0","id":1,"method":"tools/list"}'';
                  headers = {
                    Authorization = "Bearer \${GROK_ADMIN_KEY}";
                    Content-Type = "application/json";
                    Accept = "application/json, text/event-stream";
                  };
                  conditions = [ "[STATUS] == 200" ];
                }
                (tcp "homelab" "postgres" "tcp://127.0.0.1:5432")
                (tcp "homelab" "booklore-db" "tcp://10.110.0.60:3306")
                (tcp "homelab" "incus" "tcp://127.0.0.1:8443")
                {
                  name = "homelab";
                  group = "hosts";
                  url = "icmp://192.168.0.160";
                  interval = "1m";
                  conditions = [ "[CONNECTED] == true" ];
                }
                # Both pi web apps are probed through their own names, not
                # `127.0.0.1:PORT`: those loopback URLs only exist on the pi
                # itself, so from this host they always failed and Gatus showed
                # false reds. Each URL is a page that really returns 200 (a
                # status endpoint / the login form) rather than a redirect, so
                # the strict `[STATUS] == 200` condition still means "app
                # works" instead of "app redirected somewhere".
                (http "pi" "nextcloud" "http://nextcloud.home.arpa/status.php" [ ])
                (http "pi" "speedtest" "http://speedtest.home.arpa/admin/login" [ ])
                (tcp "pi" "cockpit" "tcp://192.168.0.105:9090")
                (tcp "pi" "ssh" "tcp://192.168.0.105:22")
                {
                  name = "pi";
                  group = "hosts";
                  url = "icmp://192.168.0.105";
                  interval = "1m";
                  conditions = [ "[CONNECTED] == true" ];
                }
                # AdGuard answers DNS on the LAN address, not on the
                # web port. Query a name it rewrites so a dead
                # resolver fails here instead of only in a browser.
                {
                  name = "adguard";
                  group = "dns";
                  url = "192.168.0.105";
                  interval = "1m";
                  dns = {
                    query-name = "homelab.home.arpa";
                    query-type = "A";
                  };
                  conditions = [
                    "[CONNECTED] == true"
                    "[DNS_RCODE] == NOERROR"
                    "[BODY] == 192.168.0.160"
                  ];
                }
              ];
          };
        };
        systemd.services.gatus.serviceConfig = {
          WorkingDirectory = "/var/lib/gatus";
          # The module already grants CAP_NET_RAW. The state dir is
          # created by StateDirectory before ExecStart.
          ReadWritePaths = [ "/var/lib/gatus" ];
        };
      };
  };
}
