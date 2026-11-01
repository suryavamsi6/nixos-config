# Homepage dashboard + the homelab-stats feed that powers its tiles.
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 4 of
# plans/clan-deploy-rs-migration.md). Two things travel together here, because
# one is the other's data source:
#   services.homepage-dashboard - the board itself, served by Caddy at
#                                 homelab.home.arpa; binds 0.0.0.0:8082 but the
#                                 firewall keeps that port closed.
#   homelabStats                - homelab-stats, the loopback JSON feed on
#                                 :8793 that the tiles poll. It reports Incus
#                                 memory per instance, top units/processes by
#                                 RSS, hwmon temperatures and the AdGuard query
#                                 log. AdGuard's API 401s without a
#                                 WWW-Authenticate header, so basic auth is sent
#                                 up front from the same env file the dashboard
#                                 reads.
#
# Coordinates are homelab-specific by construction: the Incus instances, the
# 10.110.0.0/24 guest network and the pi's AdGuard are all named literally. Use
# it on this host, not as a generic dashboard module.
{ lib, ... }:
{
  options.flake.modules.nixos.homepage = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        # The one human-supplied secret in the fleet. `homepage-vars/secrets`
        # is a persisted prompt (never generated), so filling it in once at
        # `clan vars generate homelab` is what replaces the old "edit the file
        # then restart" workflow below.
        secretsFile = config.clan.core.vars.generators.homepage-vars.files.secrets-env.path;

        homelabStats = pkgs.writeShellApplication {
          name = "homelab-stats";
          runtimeInputs = [
            pkgs.python3
            pkgs.incus
            pkgs.procps
            pkgs.systemd
            pkgs.coreutils
          ];
          text = ''
            exec python3 ${../hosts/homelab-stats/homelab_stats.py} "$@"
          '';
        };
      in
      {
        # hrefs use the pi's AdGuard home.arpa rewrites for other LAN
        # clients; this host resolves the same names itself via
        # networking.hosts, so widgets and siteMonitors can use either
        # names or raw IP:port. Cockpit carries no monitor (its
        # self-signed TLS breaks the probe). Tiles with live stats
        # (AdGuard, Home Assistant, Nextcloud, Booklore, Speedtest) read
        # credentials from the env file seeded below and show an error
        # badge until it is filled in.
        services.homepage-dashboard = {
          enable = true;
          listenPort = 8082;
          # Host-header allowlist: homepage v2 rejects other Host values,
          # so it must know the names Caddy forwards (it preserves the
          # original Host header).
          allowedHosts =
            "homelab.home.arpa,homelab.192.168.0.160.nip.io,192.168.0.160," + "localhost:8082,127.0.0.1:8082";
          # Widget credentials come from the `homepage-vars` Clan var
          # ({{HOMEPAGE_VAR_*}}). See the migration bridge below.
          environmentFiles = [ secretsFile ];
          settings = {
            title = "homelab";
            description = "LAN services";
            theme = "dark";
            color = "slate";
            headerStyle = "boxed";
            # basic = textual status + response time per site monitor.
            statusStyle = "basic";
            hideVersion = true;
            layout = {
              Homelab = { };
              "Raspberry Pi" = { };
              AdGuard = { };
              "Homelab memory" = { };
              Infrastructure = { };
            };
          };
          widgets = [
            {
              datetime = {
                text_size = "xl";
                format = {
                  dateStyle = "long";
                  timeStyle = "medium";
                  hourCycle = "h23";
                };
              };
            }
            {
              # /proc stats of this host (the module opens ProcSubset for
              # the cpu widget).
              resources = {
                label = "Homelab";
                cpu = true;
                memory = true;
                disk = "/";
                # CPU package temperature straight from hwmon (no lm_sensors
                # on this host).
                cputemp = true;
                uptime = true;
              };
            }
            {
              # SearXNG's autocomplete JSON is not Homepage's suggestion
              # shape, so suggestions stay off. The box still opens results
              # on this instance.
              search = {
                provider = "custom";
                url = "http://search.home.arpa/search?q=";
                target = "_blank";
              };
            }
          ];
          services = [
            {
              Homelab = [
                {
                  "Home Assistant" = {
                    href = "http://homeassistant.home.arpa/";
                    icon = "mdi-home-assistant";
                    description = "House control. Incus VM on this laptop.";
                    siteMonitor = "http://homeassistant.home.arpa/";
                  };
                }
                {
                  Hermes = {
                    href = "http://hermes.home.arpa/";
                    icon = "mdi-face-agent";
                    description = "Agent dashboard. Incus container on this laptop.";
                    siteMonitor = "http://hermes.home.arpa/";
                  };
                }
                {
                  SearXNG = {
                    href = "http://search.home.arpa/";
                    icon = "mdi-magnify";
                    description = "Private metasearch. Native service on this laptop.";
                    siteMonitor = "http://search.home.arpa/";
                  };
                }
                {
                  Booklore = {
                    href = "http://booklore.home.arpa/";
                    icon = "mdi-bookshelf";
                    description = "E-book library (Grimmory). Incus container on this laptop.";
                    siteMonitor = "http://booklore.home.arpa/";
                  };
                }
                {
                  "Reactive Resume" = {
                    href = "http://resume.home.arpa/";
                    icon = "mdi-file-account-outline";
                    description = "Resume builder. Incus container, Postgres on this laptop.";
                    siteMonitor = "http://resume.home.arpa/api/health";
                  };
                }
                {
                  Netdata = {
                    href = "http://netdata.home.arpa/";
                    icon = "mdi-chart-timeline-variant";
                    description = "Live metrics for this laptop. No login; LAN only.";
                    siteMonitor = "http://127.0.0.1:19999/api/v1/info";
                  };
                }
                {
                  Gatus = {
                    href = "http://status.home.arpa/";
                    icon = "mdi-heart-pulse";
                    description = "Status page. Checks are declared in the flake, not clicked in.";
                    siteMonitor = "http://127.0.0.1:3001/health";
                  };
                }
                {
                  Grok = {
                    href = "http://grok.home.arpa/";
                    icon = "mdi-robot-outline";
                    description = "SuperGrok as an OpenAI-compatible API (/v1) and MCP. No siteMonitor: every endpoint wants the admin key; Gatus holds the authenticated check.";
                  };
                }
                {
                  Homelable = {
                    href = "http://map.home.arpa/";
                    icon = "mdi-graph-outline";
                    description = "Visual map of the LAN. First login is admin / admin; change it.";
                    siteMonitor = "http://10.110.0.91/";
                  };
                }
                {
                  Bifrost = {
                    href = "http://bifrost.home.arpa/";
                    icon = "mdi-transit-connection-variant";
                    description = "AI gateway for providers and virtual keys. Its own MCP gateway lives at bifrost.home.arpa/mcp, not at mcp.home.arpa.";
                    siteMonitor = "http://10.110.0.100:8080/health";
                  };
                }
                {
                  MCPHub = {
                    href = "http://mcp.home.arpa/";
                    icon = "mdi-hubspot";
                    description = "MCP gateway and dashboard. Point MCP clients at mcp.home.arpa/mcp; upstreams are managed in the UI.";
                    siteMonitor = "http://10.110.0.30:3000/";
                  };
                }
                {
                  # No siteMonitor: Qdrant wants the API key on every route,
                  # so a plain GET shows red. Read collections from the host:
                  #   sudo incus exec qdrant -- curl -s \
                  #     -H "api-key: $(sudo sed -n 's/^QDRANT_API_KEY=//p' /var/lib/qdrant-secrets/api-key)" \
                  #     http://127.0.0.1:6333/collections
                  Qdrant = {
                    href = "http://10.110.0.102:6334";
                    icon = "mdi-database";
                    description = "Vector store for Bifrost's semantic cache. Incus container on this laptop, gRPC 6334 on the bridge only.";
                  };
                }
                {
                  Nutify = {
                    href = "http://nutify.home.arpa/";
                    icon = "mdi-battery-charging-80";
                    description = "UPS monitoring (NUT + Flask). Incus container on this laptop; no NUT server configured yet.";
                    siteMonitor = "http://nutify.home.arpa/";
                  };
                }
              ];
            }
            {
              "Raspberry Pi" = [
                {
                  "AdGuard Home" = {
                    href = "http://adguard.home.arpa/";
                    icon = "si-adguard";
                    description = "LAN DNS and filtering on the Pi.";
                    # /control/* answers 401 to an unauthenticated probe, so
                    # the monitor watches the login page instead.
                    siteMonitor = "http://adguard.home.arpa/login.html";
                    widget = {
                      type = "adguard";
                      url = "http://adguard.home.arpa";
                      username = "{{HOMEPAGE_VAR_ADGUARD_USERNAME}}";
                      password = "{{HOMEPAGE_VAR_ADGUARD_PASSWORD}}";
                    };
                  };
                }
                {
                  Nextcloud = {
                    href = "http://nextcloud.home.arpa/";
                    icon = "si-nextcloud";
                    description = "Files and sync. Podman on the Pi.";
                    siteMonitor = "http://nextcloud.home.arpa/";
                  };
                }
                {
                  "Speedtest Tracker" = {
                    href = "http://speedtest.home.arpa/";
                    icon = "mdi-speedometer";
                    description = "LAN speed history. Podman on the Pi.";
                    siteMonitor = "http://speedtest.home.arpa/";
                  };
                }
                {
                  Cockpit = {
                    href = "https://cockpit.home.arpa:9090/";
                    icon = "mdi-server";
                    description = "Pi admin. The certificate is self-signed.";
                  };
                }
              ];
            }
            {
              Infrastructure = [
                {
                  "Incus UI" = {
                    href = "https://192.168.0.160:8443/";
                    icon = "mdi-console";
                    description = "Containers and VMs. Client certificate, so it stays off the proxy.";
                  };
                }
                {
                  OpenBot = {
                    href = "https://openbot.run/app";
                    icon = "mdi-robot";
                    description = "Account app. The container is on this laptop and has no LAN page.";
                  };
                }
                {
                  Tailscale = {
                    href = "https://login.tailscale.com/admin/machines";
                    icon = "si-tailscale";
                    description = "Pi mesh. This opens the admin site, not a page on the Pi.";
                  };
                }
                {
                  PostgreSQL = {
                    icon = "mdi-database";
                    description = "Bifrost and Reactive Resume. Loopback only, no page.";
                  };
                }
                {
                  MariaDB = {
                    icon = "mdi-database-outline";
                    description = "Nextcloud (Pi) and Grimmory (Incus) databases. No host ports.";
                  };
                }
                {
                  "Unbound + Redis" = {
                    icon = "mdi-dns";
                    description = "Recursive DNS on the Pi, cached by Redis. Both stay on loopback.";
                  };
                }
                {
                  Caddy = {
                    icon = "mdi-swap-horizontal";
                    description = "Names on this laptop. Not a separate page.";
                  };
                }
                {
                  Nginx = {
                    icon = "mdi-web";
                    description = "Names on the Pi. Not a separate page.";
                  };
                }
              ];
            }
            {
              # AdGuard log views. AdGuard's own UI is not embedded: its
              # SPA renders the login form unless the request already
              # carries an `agh_session` cookie, and that cookie is
              # HttpOnly + SameSite=Lax and issued on another origin, so an
              # iframe here has no session of its own and showed only a
              # login box (the state it was in). Both tiles read the
              # loopback collector instead, which logs in server-side and
              # reports "auth needed" while the seeded credentials are
              # still placeholders, so the log renders with no per-browser
              # login at all.
              AdGuard = [
                {
                  "Query log" = {
                    href = "http://adguard.home.arpa/#/logs";
                    icon = "mdi-text-box-search-outline";
                    description = "Last 10 DNS queries, newest first.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/adguard/queries.json";
                      display = "dynamic-list";
                      refreshInterval = 15000;
                      mappings = {
                        name = "name";
                        label = "label";
                        limit = 10;
                        target = "http://adguard.home.arpa/#/logs";
                      };
                    };
                  };
                }
                {
                  "Top blocked" = {
                    icon = "mdi-shield-alert-outline";
                    description = "Most blocked domains this period.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/adguard/top.json";
                      display = "dynamic-list";
                      refreshInterval = 30000;
                      mappings = {
                        name = "name";
                        label = "label";
                        limit = 6;
                        target = "http://adguard.home.arpa/#/logs";
                      };
                    };
                  };
                }
              ];
            }
            {
              # Memory and thermals for this host. The collector runs as
              # root, so Incus memory and every cgroup are visible; it
              # binds 127.0.0.1 only and nothing outside this host can
              # read it (the query log carries client names).
              "Homelab memory" = [
                {
                  Apps = {
                    icon = "mdi-cube-outline";
                    description = "Incus containers and VMs by memory.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/apps.json";
                      display = "dynamic-list";
                      refreshInterval = 10000;
                      mappings = {
                        name = "name";
                        label = "mem";
                        limit = 6;
                      };
                    };
                  };
                }
                {
                  Services = {
                    icon = "mdi-cog-outline";
                    description = "Top systemd units by cgroup memory.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/services.json";
                      display = "dynamic-list";
                      refreshInterval = 10000;
                      mappings = {
                        name = "name";
                        label = "mem";
                        limit = 6;
                      };
                    };
                  };
                }
                {
                  Processes = {
                    icon = "mdi-format-list-numbered";
                    description = "Top processes by RSS, merged per app.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/procs.json";
                      display = "dynamic-list";
                      refreshInterval = 10000;
                      mappings = {
                        name = "name";
                        label = "mem";
                        limit = 6;
                      };
                    };
                  };
                }
                {
                  Temperatures = {
                    icon = "mdi-thermometer";
                    description = "CPU package, NVMe, board and Wi-Fi sensors.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/temps.json";
                      display = "dynamic-list";
                      refreshInterval = 10000;
                      mappings = {
                        name = "name";
                        label = "temp";
                        limit = 6;
                      };
                    };
                  };
                }
                {
                  "Disk health" = {
                    icon = "mdi-harddisk";
                    description = "SMART verdict and temperature per drive.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/disk.json";
                      display = "dynamic-list";
                      refreshInterval = 60000;
                      mappings = {
                        name = "name";
                        label = "label";
                        limit = 6;
                      };
                    };
                  };
                }
                {
                  Backups = {
                    icon = "mdi-backup-restore";
                    description = "Last restic run per host.";
                    widget = {
                      type = "customapi";
                      url = "http://127.0.0.1:8793/backups.json";
                      display = "dynamic-list";
                      refreshInterval = 60000;
                      mappings = {
                        name = "name";
                        label = "label";
                        limit = 6;
                      };
                    };
                  };
                }
              ];
            }
          ];
        };

        # ── Migration bridge (plans/clan-deploy-rs-migration.md §6.3) ──────
        # Widget credentials moved to the `homepage-vars` Clan var. The old
        # workflow ("edit /var/lib/homepage-dashboard-env/secrets.env, then
        # restart the dashboard") is replaced by:
        #
        #   clan vars set homelab homepage-vars/secrets   # paste, Ctrl-D
        #   clan vars upload homelab
        #   systemctl restart homepage-dashboard
        #
        # This unit keeps the 0755 directory — homelab-stats and the AdGuard
        # hint path still reference it — and records the move. It never writes
        # the file again; the old one stays as the rollback path.
        systemd.services.homepage-dashboard-secrets = {
          description = "Record that Homepage widget credentials moved to Clan vars";
          before = [ "homepage-dashboard.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.coreutils ];
          script = ''
            set -euo pipefail
            install -d -m 755 /var/lib/homepage-dashboard-env
            if [ -s /var/lib/homepage-dashboard-env/secrets.env ]; then
              : > /var/lib/homepage-dashboard-env/.migrated-to-clan
            fi
            # Until the prompt is answered, say so instead of silently serving
            # blank widget placeholders.
            if [ ! -s ${secretsFile} ] && [ -s /var/lib/homepage-dashboard-env/secrets.env ]; then
              echo "homepage-vars is unset; adopt the old file with:" >&2
              echo "  clan vars set homelab homepage-vars/secrets < /var/lib/homepage-dashboard-env/secrets.env" >&2
            fi
          '';
        };

        systemd.services.homepage-dashboard = {
          after = [ "homepage-dashboard-secrets.service" ];
          requires = [ "homepage-dashboard-secrets.service" ];
        };

        # JSON feed the dashboard tiles above read. Runs as root so Incus
        # and every cgroup are visible; it binds 127.0.0.1 only, and the
        # firewall keeps that port closed, so the AdGuard query log it
        # serves never reaches the LAN. The env file is the same one
        # Homepage substitutes {{HOMEPAGE_VAR_*}} from; while the seeded
        # values are placeholders the AdGuard tiles show a hint instead of
        # an error.
        systemd.services.homelab-stats = {
          description = "Loopback stats feed for the Homepage dashboard";
          wantedBy = [ "multi-user.target" ];
          after = [
            "incus.service"
            "homepage-dashboard-secrets.service"
          ];
          serviceConfig = {
            ExecStart = "${homelabStats}/bin/homelab-stats";
            Restart = "on-failure";
            RestartSec = "5s";
            # Tolerate a missing file: the AdGuard endpoints degrade to a
            # hint row and the rest of the feed works without credentials.
            EnvironmentFile = "-${secretsFile}";
          };
        };
      };
  };
}
