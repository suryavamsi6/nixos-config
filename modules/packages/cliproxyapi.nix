# CLIProxyAPI (router-for-me/CLIProxyAPI): puts OAuth subscription logins —
# Codex/ChatGPT, Claude Code, Grok, Antigravity, Kimi, Devin — behind an
# OpenAI/Anthropic/Gemini-compatible HTTP API.
#
# Uses the nixpkgs module (services.cliproxyapi) rather than an Incus OCI
# container: the module is already upstream, keeps state in
# /var/lib/cliproxyapi, and its hardening (PrivateUsers, ProtectSystem=strict,
# empty capability set) comes for free.
#
# The API listens on 0.0.0.0:8317 so the Bifrost container can reach it over
# incusbr0; 8317 is still absent from allowedTCPPorts, so it is not a LAN
# service. Caddy serves cliproxy.home.arpa for everything outside incusbr0
# (searx, gatus, netdata and grok-oauth-proxy stay loopback-only).
#
# Where the two secrets live — deliberately NOT in the flake:
#   /var/lib/cliproxyapi/access-key   client API key, sent as
#                                     `Authorization: Bearer <key>`
#   /var/lib/cliproxyapi/mgmt-key     management key for /v8/management
# Both are minted once by cliproxyapi-secrets on first boot. Read them with:
#   sudo cat /var/lib/cliproxyapi/access-key
#   sudo cat /var/lib/cliproxyapi/mgmt-key
#
# `settings` is re-rendered into config.yaml on every start, so anything
# written through the management API is overwritten — edit this file instead.
# `oauth.auth-dir` deliberately stays at the module default (/var/lib/cliproxyapi)
# because the CLI login flow writes token JSON there as the service user.
{ lib, ... }:
{
  options.flake.modules.nixos.cliproxyapi = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        config,
        pkgs,
        ...
      }:
      let
        domain = "home.arpa";
        stateDir = "/var/lib/cliproxyapi";
      in
      {
        services.cliproxyapi = {
          enable = true;
          settings = {
            # Binds every interface on purpose. 127.0.0.1 is wrong here: the
            # Bifrost container (10.110.0.100) reaches this across incusbr0,
            # where the only usable address is the bridge gateway
            # (10.110.0.1) — it cannot see the host's loopback and dnsmasq on
            # incusbr0 does not serve the home.arpa name. The LAN still cannot
            # reach 8317: the port is absent from
            # networking.firewall.allowedTCPPorts, and incusbr0 is a trusted
            # interface. Management stays localhost-only regardless
            # (management.allow-remote = false), so the 0.0.0.0 bind only
            # widens the API surface, not the admin surface.
            server = {
              host = "0.0.0.0";
              port = 8317;
            };
            access.api-keys = [ { _secret = "${stateDir}/access-key"; } ];
            management = {
              # The management API and its control panel stay loopback-only.
              # Caddy is the LAN door and never proxies /v8/management.
              allow-remote = false;
              secret-key._secret = "${stateDir}/mgmt-key";
            };
            # One account is enough to start; round-robin costs nothing and
            # lets a second Codex login be added later with no config change.
            routing.strategy = "round-robin";
            oauth.providers.codex = {
              # Upstream identifies itself instead of impersonating another
              # Codex client.
              signin-with-chatgpt-identifier = "CLIProxyAPI";
            };
            # Request/response logging off: prompts would otherwise land in
            # the journal. Flip to true temporarily when debugging a call.
            observability.logs.debug = false;
          };
        };

        # Mint the two key files before the service starts, idempotently: an
        # existing key is never rotated, because that would silently break
        # every client already configured against it. Not tmpfiles `w+`
        # because that rewrites per-boot secrets; not the module's own
        # preStart because it only renders config.yaml.
        systemd.services.cliproxyapi-secrets = {
          description = "Seed CLIProxyAPI access and management keys";
          wantedBy = [ "multi-user.target" ];
          requiredBy = [ "cliproxyapi.service" ];
          before = [ "cliproxyapi.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          path = [
            pkgs.coreutils
            pkgs.openssl
          ];
          script = ''
            install -d -m 0700 -o cliproxyapi -g cliproxyapi ${stateDir}
            for pair in "access-key:cliproxy-access" "mgmt-key:cliproxy-mgmt"; do
              f=${stateDir}/''${pair%%:*}
              if [ ! -s "$f" ]; then
                # The prefix is cosmetic: it makes the key recognisable in a
                # log or client config without changing what the server
                # compares.
                printf '%s-%s\n' "''${pair##*:}" "$(openssl rand -hex 24)" > "$f"
                chown cliproxyapi:cliproxyapi "$f"
                chmod 0600 "$f"
              fi
            done
          '';
        };

        # LoadCredential resolves the two key files before the unit starts, so
        # ordering alone is not enough: `requires` makes systemd pull the
        # seeder into the transaction even when the service is restarted
        # outside a boot (the seeder is RemainAfterExit, so a plain restart
        # would otherwise find it inactive and fail on the missing files).
        systemd.services.cliproxyapi = {
          requires = [ "cliproxyapi-secrets.service" ];
          after = [ "cliproxyapi-secrets.service" ];
        };

        # Loopback-only by design, so no firewall port and no self-registered
        # /etc/hosts entry: the LAN reaches this through Caddy like every
        # other native service here, and the host's networking.hosts list
        # (plus the pi's AdGuard rewrites) already carries cliproxy.home.arpa.
        services.caddy.virtualHosts."http://cliproxy.${domain}" = {
          extraConfig = ''
            encode gzip
            # The client key is checked by CLIProxyAPI itself (access.api-keys)
            # rather than by a Caddy matcher, so there is no second header to
            # keep in sync; `Authorization: Bearer <access-key>` passes
            # through. flush_interval -1 keeps SSE deltas unbuffered, exactly
            # as the bifrost and grok vhosts do.
            reverse_proxy http://127.0.0.1:8317 {
              flush_interval -1
            }
          '';
        };

        # The login flags (--codex-login and friends) need the binary on PATH
        # and must run as the service user so the token lands in auth-dir with
        # the right ownership.
        environment.systemPackages = [ config.services.cliproxyapi.package ];
      };
  };
}
