# hermes-bridge for the Hermes phone app, homelab glue only. The bridge itself is a generic,
# dependency-free Python package (vendored unchanged in ./hermes_bridge from the hermes-bridge
# project; swap this for a flake input once it is published). See docs/hermes-bridge.md.
#
# Runs inside the incus-hermes container as user `hermes`, next to Hermes:
#   hermes-bridge-backend  `hermes serve --isolated` on 127.0.0.1:9120, fixed session token, its
#                          own loopback HERMES_DASHBOARD_PUBLIC_URL (token mode, not browser login),
#                          started only after the browser dashboard (:9119, Caddy, basic auth)
#                          is up so it never becomes Hermes's "host backend". Not reachable from
#                          outside the container.
#   hermes-bridge          the bridge on <container IP>:8765 (Incus bridge only); Tailscale Funnel
#                          publishes it at https://<host>.<tailnet>.ts.net/bridge.
# Secrets are generated once on the host (root-only, /var/lib/incus/hermes), never printed:
#   bridge-key              the key the phone app sends   (sudo cat /var/lib/incus/hermes/bridge-key)
#   bridge-dashboard-token  shared by the bridge and its private Hermes backend
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hermesBridge;
  # Python package dir (`hermes_bridge/`) in a store path whose name changes with the code, so a
  # code change gives the container a new directory, a new unit file and therefore a restart.
  bridgeSrc = pkgs.runCommand "hermes-bridge-src" { } ''
    mkdir -p $out/hermes_bridge
    cp ${./hermes_bridge}/*.py $out/hermes_bridge/
  '';
  codeDir = "/home/hermes/.local/share/hermes-bridge/${builtins.baseNameOf bridgeSrc}";

  backendUnit = pkgs.writeText "hermes-bridge-backend.service" ''
    [Unit]
    Description=Hermes management backend for hermes-bridge (loopback only, port ${toString cfg.backendPort})
    After=hermes-dashboard.service
    Wants=hermes-dashboard.service

    [Service]
    # HERMES_DASHBOARD_SESSION_TOKEN only. Process env on purpose: Hermes ignores this variable in ~/.hermes/.env.
    EnvironmentFile=%h/.config/hermes-bridge/backend.env
    # Token mode, not browser login. Hermes gates a dashboard process behind browser login when it
    # binds a non-loopback address OR when dashboard.public_url / HERMES_DASHBOARD_PUBLIC_URL names a
    # non-loopback host, even on 127.0.0.1 (hermes_cli/web_server_boundary.py,
    # public_hosts_engage_gate). The LAN dashboard's public_url would therefore gate this backend
    # too. The env var takes precedence over config.yaml, so this process declares its own loopback
    # address and stays in session-token mode. The :9119 dashboard keeps its own setting.
    Environment=HERMES_DASHBOARD_PUBLIC_URL=http://127.0.0.1:${toString cfg.backendPort}
    # Refuses to start if ~/.hermes/.env sets HERMES_DASHBOARD_PUBLIC_URL (it would override the line
    # above), then waits for the :9119 dashboard to claim the host-backend record first.
    ExecStartPre=%h/.config/hermes-bridge/backend-preflight.sh
    ExecStart=%h/.local/bin/hermes serve --isolated --host 127.0.0.1 --port ${toString cfg.backendPort}
    Restart=on-failure
    RestartSec=15

    [Install]
    WantedBy=default.target
  '';
  bridgeUnit = pkgs.writeText "hermes-bridge.service" ''
    [Unit]
    Description=hermes-bridge (management API for the Hermes phone app)
    After=hermes-bridge-backend.service
    Wants=hermes-bridge-backend.service

    [Service]
    Environment=PYTHONPATH=${codeDir}
    Environment=HERMES_BRIDGE_LISTEN=${cfg.address}:${toString cfg.port}
    Environment=HERMES_BRIDGE_DASHBOARD_URL=http://127.0.0.1:${toString cfg.backendPort}
    Environment=HERMES_BRIDGE_KEY_FILE=%h/.config/hermes-bridge/bridge-key
    Environment=HERMES_BRIDGE_DASHBOARD_TOKEN_FILE=%h/.config/hermes-bridge/dashboard-token
    Environment=HERMES_BRIDGE_BASE_PATH=${cfg.funnelPath}
    ExecStart=/usr/bin/python3 -m hermes_bridge serve
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=default.target
  '';
in
{
  options.services.hermesBridge = {
    enable = lib.mkEnableOption "hermes-bridge in the incus-hermes container";
    address = lib.mkOption {
      type = lib.types.str;
      default = "10.110.0.50";
      description = "Address the bridge binds inside the container (its Incus bridge IP).";
    };
    port = lib.mkOption { type = lib.types.port; default = 8765; };
    backendPort = lib.mkOption { type = lib.types.port; default = 9120; };
    funnelPath = lib.mkOption {
      type = lib.types.str;
      default = "/bridge";
      description = "Path the Tailscale Funnel job mounts the bridge at.";
    };
    funnelTarget = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://${cfg.address}:${toString cfg.port}";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.incus-hermes-bridge = {
      description = "Provision hermes-bridge in the Hermes Incus container";
      wantedBy = [ "multi-user.target" ];
      after = [ "incus-hermes.service" ];
      requires = [ "incus-hermes.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.incus pkgs.coreutils pkgs.gnutar pkgs.openssl ];
      script = ''
        set -euo pipefail
        state=/var/lib/incus/hermes
        install -d -m 700 "$state"
        # Generated once, never rotated by this unit, never printed.
        for f in bridge-key bridge-dashboard-token; do
          if [ ! -s "$state/$f" ]; then (umask 077; openssl rand -hex 32 > "$state/$f"); fi
        done
        (umask 077; printf 'HERMES_DASHBOARD_SESSION_TOKEN=%s\n' "$(cat "$state/bridge-dashboard-token")" > "$state/bridge-backend.env")

        in_c() { incus exec hermes -- "$@"; }
        uid=$(in_c id -u hermes | tr -d '\r\n ')
        gid=$(in_c id -g hermes | tr -d '\r\n ')
        as_hermes() { in_c sudo -u hermes -- env XDG_RUNTIME_DIR=/run/user/$uid "$@"; }
        changed=0
        # push SRC DEST MODE: copy into the container only when the content differs.
        push() {
          local have want
          have=$(in_c sh -c "sha256sum '$2' 2>/dev/null | cut -d' ' -f1" | tr -d '\r\n')
          want=$(sha256sum < "$1" | cut -d' ' -f1)
          if [ "$have" != "$want" ]; then
            incus file push --uid "$uid" --gid "$gid" --mode "$3" "$1" "hermes$2"
            changed=1
          fi
        }

        in_c test -x /usr/bin/python3 || { in_c apt-get update -qq; in_c env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3; }

        in_c install -d -o hermes -g hermes -m 700 /home/hermes/.config/hermes-bridge
        in_c install -d -o hermes -g hermes /home/hermes/.local/share/hermes-bridge /home/hermes/.config/systemd/user
        if ! in_c test -d ${codeDir}; then
          in_c install -d -o hermes -g hermes ${codeDir}
          tar -C ${bridgeSrc} -cf - . | in_c sudo -u hermes -- tar -C ${codeDir} -xf -
        fi
        # Drop code from earlier generations.
        in_c find /home/hermes/.local/share/hermes-bridge -mindepth 1 -maxdepth 1 -type d ! -path ${codeDir} -exec rm -rf {} +

        push "$state/bridge-key" /home/hermes/.config/hermes-bridge/bridge-key 0600
        push "$state/bridge-dashboard-token" /home/hermes/.config/hermes-bridge/dashboard-token 0600
        push "$state/bridge-backend.env" /home/hermes/.config/hermes-bridge/backend.env 0600
        push ${./backend-preflight.sh} /home/hermes/.config/hermes-bridge/backend-preflight.sh 0755
        push ${backendUnit} /home/hermes/.config/systemd/user/hermes-bridge-backend.service 0644
        push ${bridgeUnit} /home/hermes/.config/systemd/user/hermes-bridge.service 0644

        as_hermes systemctl --user daemon-reload
        as_hermes systemctl --user enable hermes-bridge-backend.service hermes-bridge.service
        if [ "$changed" = 1 ]; then
          # --no-block: the backend waits for the dashboard in ExecStartPre; don't hold up the switch.
          as_hermes systemctl --user --no-block restart hermes-bridge-backend.service hermes-bridge.service
        else
          as_hermes systemctl --user --no-block start hermes-bridge-backend.service hermes-bridge.service
        fi
      '';
    };
  };
}
