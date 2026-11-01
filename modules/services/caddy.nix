# Caddy reverse proxy: one home.arpa hostname per service.
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 6 of
# plans/clan-deploy-rs-migration.md). This is the LAN door: nearly everything
# else in this host binds the loopback or incusbr0, and a browser reaches it
# through a name served here.
#
# Naming follows the pi's convention: <service>.home.arpa (RFC 8375), with
# AdGuard rewrites on the pi (192.168.0.105) pointing them at this host, plus
# nip.io aliases for clients that do not use the pi for DNS. The vhost table
# lists which port each name fronts — read it rather than guessing, because the
# upstreams are a mix of loopback (search, status, netdata, grok, homepage,
# board), incusbr0 guests (10.110.0.0/24) and one bound LAN address.
#
# Two details that look odd and are not:
#   - The unit waits for grok-oauth-proxy-secrets: caddy injects GROK_ADMIN_KEY
#     into the /grok/* leg Bifrost calls, and it must not start before the key
#     exists.
#   - Restart/StartLimit settings are mkForce'd because the bifrost vhost pins
#     `bind 192.168.0.160`, the Wi-Fi DHCP lease. During activation the address
#     disappears for ~15s and one EADDRNOTAVAIL would otherwise leave the proxy
#     dead for hours.
#
# The host imports this module and keeps only the caddy secrets
# environmentFile, which is a deployment detail rather than a vhost.
{ lib, ... }:
{
  options.flake.modules.nixos.caddy = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { ... }:
      {
        #   homeassistant.home.arpa -> Home Assistant
        #   mcp.home.arpa           -> MCPHub dashboard + /mcp
        #   hermes.home.arpa        -> Hermes agent (Ubuntu Incus container)
        #   booklore.home.arpa      -> Grimmory/Booklore library (Incus container)
        #   board.home.arpa         -> this host's own board (127.0.0.1:8765)
        #   search.home.arpa        -> SearXNG (127.0.0.1:8888)
        #   resume.home.arpa        -> Reactive Resume (10.110.0.80:3000)
        #   netdata.home.arpa       -> Netdata (127.0.0.1:19999, also :19999)
        #   netdata.home.arpa       -> Netdata (127.0.0.1:19999, also :19999)
        #   status.home.arpa        -> Gatus (127.0.0.1:3001)
        #   map.home.arpa           -> Homelable (10.110.0.91:80)
        #   bifrost.home.arpa       -> Bifrost (10.110.0.100:8080)
        #   grok.home.arpa          -> grok-oauth-proxy (127.0.0.1:56121);
        #                              /grok/* is the key-injecting leg Bifrost
        #                              uses, everything else needs the real
        #                              admin key
        #   homelab.home.arpa       -> Homepage dashboard (also http://192.168.0.160/)
        # Future services: add one entry to `proxyHosts` below, add the same
        # name to the pi's adguardhome rewrites, and switch both hosts.
        # The Incus UI deliberately stays direct on https://192.168.0.160:8443
        # — its client-certificate TLS cannot pass through an HTTP proxy.
        # HTTP only. home.arpa cannot get a publicly trusted cert, and the
        # previous self-signed wildcard made every browser warn. Site
        # addresses are explicit `http://` so Caddy does not turn automatic
        # HTTPS back on. `auto_https disable_redirects` stops the catch-all
        # :443 redirect for any other name (including the bare IP).
        #
        # Caddy resolves {$VAR} placeholders in the Caddyfile at
        # adapt time. That is what lets the grok vhost below inject the
        # real ADMIN_API_KEY as GROK_ADMIN_KEY without the key ever
        # entering the flake or the rendered /etc/caddy/caddy_config:
        # systemd reads the env file (mode 0600, owned by the
        # grok-oauth-proxy service user) as root, then passes the values
        # to the caddy process through its environment.
        # The unit also waits for that file: caddy cannot start ahead of
        # the unit that mints the key it needs to inject.
        systemd.services.caddy = {
          requires = [ "grok-oauth-proxy-secrets.service" ];
          after = [ "grok-oauth-proxy-secrets.service" ];
          # The bifrost vhost pins `bind 192.168.0.160`, the Wi-Fi DHCP
          # lease on wlp5s0. During activation NetworkManager (and every
          # unit with a nixos-upgrade/switch reload trigger) is restarted,
          # so wpa_supplicant drops the AP and the address disappears for
          # ~15s. Caddy owns a StartLimitBurst=10/4h from the module and
          # RestartPreventExitStatus=1, so one EADDRNOTAVAIL during that
          # window used to leave the proxy dead for the rest of the 4h
          # interval and the switch reported caddy.service as failed.
          # Retry with backoff long enough to outlive the reconnect, and
          # never consume the module's restart budget while waiting.
          unitConfig = {
            StartLimitBurst = lib.mkForce 40;
            StartLimitIntervalSec = lib.mkForce 600;
          };
          serviceConfig = {
            Restart = lib.mkForce "always";
            RestartSec = lib.mkForce "15s";
            # Retry on the exit code that means "address not assigned yet";
            # the module normally drops it (RestartPreventExitStatus=1).
            RestartPreventExitStatus = lib.mkForce [ ];
          };
        };
        services.caddy =
          let
            domain = "home.arpa";
            # Public-DNS aliases that embed the IP; no setup needed.
            nip = "192.168.0.160.nip.io";
            # nat=true proxy devices only DNAT traffic arriving from the
            # LAN — they never bind host localhost, so Caddy must target
            # the container IPs on incusbr0 directly.
            proxyHosts = {
              homeassistant = {
                host = "10.110.0.10";
                # HAOS serves on port 80 inside the VM (8123 is dead there;
                # the incus ha-ui proxy device DNATs host :8123 -> VM :80).
                port = 80;
              };
              # MCPHub dashboard and its own /mcp endpoint, on the same
              # origin so client configs keep working. Bifrost's gateway
              # stays reachable at bifrost.home.arpa; this name points
              # here, not there. flush_interval keeps SSE unbuffered.
              mcp = {
                host = "10.110.0.30";
                port = 3000;
                extraConfig = ''
                  flush_interval -1
                '';
              };
              hermes = {
                host = "10.110.0.50";
                port = 9119;
              };
              # Grimmory (Booklore) library; its MariaDB container
              # stays bridge-only (10.110.0.60), like the pi's.
              booklore = {
                host = "10.110.0.61";
                port = 6060;
              };
              # Native SearXNG, not an Incus container. Loopback only.
              search = {
                host = "127.0.0.1";
                port = 8888;
              };
              # Reactive Resume in the Incus container. No host port.
              resume = {
                host = "10.110.0.80";
                port = 3000;
              };
              # Native. Netdata also answers on :19999; this name is
              # the one the dashboard and other LAN clients should use.
              netdata = {
                host = "127.0.0.1";
                port = 19999;
              };
              # Native Gatus. Loopback only. The name stayed when
              # Uptime Kuma left, so existing bookmarks still work.
              status = {
                host = "127.0.0.1";
                port = 3001;
              };
              map = {
                host = "10.110.0.91";
                port = 80;
              };
              # Nutify UPS monitoring (Incus OCI). Plain HTTP on 5050
              # inside the container; Socket.IO rides the same origin.
              nutify = {
                host = "10.110.0.103";
                port = 5050;
                extraConfig = ''
                  flush_interval -1
                '';
              };
              # Bifrost. One listener for the UI, the API, /health, and
              # /mcp (MCP clients use JSON-RPC + SSE there).
              # flush_interval keeps streamed completions and the SSE
              # stream unbuffered.
              bifrost = {
                host = "10.110.0.100";
                port = 8080;
                extraConfig = ''
                  flush_interval -1
                '';
              };
              # Grok OAuth proxy (native, loopback). flush_interval -1
              # keeps streamed completions and SSE unbuffered, like
              # bifrost above.
              #
              # Bifrost reaches this same proxy through /grok/*, bearing
              # only the gate credential GROK_CLIENT_KEY. Bifrost cannot
              # hold the real ADMIN_API_KEY (secrets.env is 0600 and owned
              # by the grok-oauth-proxy service user), so Caddy swaps in
              # the real key on that one route. Both values come from
              # services.caddy.environmentFile below.
              #
              # The matcher constrains the path as well as the credential.
              # With only the credential constrained, a request bearing the
              # right gate credential on ANY other path would enter the
              # handle block, match nothing inside it, and be answered with
              # a bare 200 -- silently breaking the WebUI and the rest of
              # this vhost.
              grok = {
                host = "127.0.0.1";
                port = 56121;
                extraConfig = ''
                  flush_interval -1
                '';
                siteExtra = ''
                  @bifrost {
                    header Authorization "Bearer {$GROK_CLIENT_KEY}"
                    path /grok/*
                  }
                  handle @bifrost {
                    handle_path /grok/* {
                      reverse_proxy http://127.0.0.1:56121 {
                        header_up Authorization "Bearer {$GROK_ADMIN_KEY}"
                        flush_interval -1
                      }
                    }
                  }
                '';
              };
            };
            site = name: upstream: proxyExtra: siteExtra: {
              serverAliases = [ "http://${name}.${nip}" ];
              extraConfig = ''
                encode gzip
                ${siteExtra}
                reverse_proxy ${upstream} {
                  ${proxyExtra}
                }
              '';
            };
          in
          {
            enable = true;
            # Caddy expands {$GROK_ADMIN_KEY} / {$GROK_CLIENT_KEY} from this
            # file at adapt time (see the grok vhost). Read by systemd as
            # root; the file stays 0600 grok-oauth-proxy:grok-oauth-proxy.
            environmentFile = "/var/lib/grok-oauth-proxy/secrets.env";
            globalConfig = ''
              auto_https disable_redirects
            '';
            httpsPort = 443;
            virtualHosts =
              (lib.mapAttrs' (
                name: cfg:
                lib.nameValuePair "http://${name}.${domain}" (
                  site name "http://${cfg.host}:${toString cfg.port}" (cfg.extraConfig or "") (cfg.siteExtra or "")
                )
              ) proxyHosts)
              // {
                # Homepage dashboard (services.homepage-dashboard).
                "http://homelab.${domain}" = site "homelab" "http://127.0.0.1:8082" "" "";
                # This host's board. The port stays closed; Caddy is the door.
                "http://board.${domain}" = site "board" "http://127.0.0.1:8765" "" "";
                # The one HTTPS vhost. MCP servers that use OAuth refuse a
                # cleartext redirect_uri on anything but loopback, so Bifrost
                # cannot complete their authorization over plain http. Caddy's
                # internal CA signs bifrost.home.arpa (and nothing else), which
                # keeps the rest of the LAN on HTTP as before. The CA root is
                # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt;
                # copy it to the desktop's caddy-local-ca.crt to trust it.
                #
                # `bind` is required, not cosmetic: a site addressed as
                # https://host listens on *:443, and tailscaled already holds
                # 100.110.46.116%tailscale0:443 for `tailscale funnel` (hermes).
                # Binding *:443 therefore fails with `listen tcp :443: bind:
                # address already in use` and takes the whole Caddy service —
                # including every HTTP dashboard — down with it. Pinning the
                # listener to the LAN address leaves the funnel's tailnet
                # :443 untouched. If the LAN address ever changes, change it
                # here too.
                "https://bifrost.${domain}" = {
                  extraConfig = ''
                    bind 192.168.0.160
                    tls internal
                    encode gzip
                    reverse_proxy http://10.110.0.100:8080 {
                      flush_interval -1
                    }
                  '';
                };
                # Everything else (http://192.168.0.160/, a short name, a
                # mistyped host) would otherwise fall through to Caddy's
                # hostless default and answer 200 with an empty body — a
                # blank page that looks like "the dashboard is down". Bounce
                # those to the canonical dashboard address instead.
                ":80" = {
                  extraConfig = ''
                    redir http://homelab.${domain}{uri} permanent
                  '';
                };
              };
          };
      };
  };
}
