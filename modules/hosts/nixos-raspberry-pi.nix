# Host: Raspberry Pi 4 (aarch64-linux)
{ inputs, ... }:
{
  flake.nixosConfigurations.raspberry-pi = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = {
      inherit inputs;
      system = "aarch64-linux";
    };
    modules = [
      # Raspberry Pi SD-card image support
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

      ({ pkgs, lib, ... }: {
        boot.loader.generic-extlinux-compatible.enable = true;
        boot.kernel.sysctl."vm.swappiness" = 100;
        hardware.enableRedistributableFirmware = true;

        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 50;
        };

        fileSystems."/mnt/media" = {
          device = "/dev/disk/by-uuid/a37619e1-b6dd-44f0-b07c-5f94698ba69b";
          fsType = "ext4";
        };
        fileSystems."/var/lib/AdGuardHome" = {
          device = "/mnt/media/adguard-home/native";
          fsType = "none";
          options = [ "bind" ];
        };
        fileSystems."/var/lib/redis-unbound" = {
          device = "/mnt/media/unbound/redis";
          fsType = "none";
          options = [ "bind" ];
        };
        networking.hostName = "pi";
        networking.networkmanager.enable = true;
        # LAN-facing services; native Nginx owns port 80.
        networking.firewall.allowedTCPPorts = [ 22 53 80 82 8090 8096 ];
        networking.firewall.allowedUDPPorts = [ 53 7359 ];

        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "prohibit-password";
        };

        services.tailscale = {
          enable = true;
          openFirewall = true;
          useRoutingFeatures = "none";
        };

        virtualisation.docker.enable = false;
        virtualisation.podman.enable = true;
        virtualisation.podman.dockerSocket.enable = true;
        virtualisation.oci-containers.backend = "podman";
        virtualisation.oci-containers.containers = {
          mariadb = {
            image = "lscr.io/linuxserver/mariadb:11.4.5";
            environmentFiles = [ "/home/suryavamsi/services/booklore/.env" ];
            volumes = [ "/mnt/media/booklore/mariadb/config:/config" ];
            extraOptions = [ "--network=pi_net" ];
          };

          booklore = {
            image = "ghcr.io/grimmory-tools/grimmory:latest";
            labels."io.containers.autoupdate" = "registry";
            environmentFiles = [ "/home/suryavamsi/services/booklore/.env" ];
            volumes = [
              "/mnt/media/booklore/data:/app/data"
              "/mnt/media/booklore/books:/books"
              "/mnt/media/booklore/bookdrop:/bookdrop"
            ];
            ports = [ "6060:6060" ];
            dependsOn = [ "mariadb" ];
            extraOptions = [ "--network=pi_net" ];
          };


          homeassistant = {
            image = "ghcr.io/home-assistant/home-assistant:stable";
            labels."io.containers.autoupdate" = "registry";
            volumes = [
              "/mnt/media/homeassistant/config:/config"
              "/etc/localtime:/etc/localtime:ro"
              "/run/dbus:/run/dbus:ro"
            ];
            ports = [ "8123:8123" ];
            environment = { TZ = "Asia/Calcutta"; };
            privileged = true;
            extraOptions = [ "--network=pi_net" ];
          };

          jellyfin = {
            image = "docker.io/jellyfin/jellyfin:latest";
            labels."io.containers.autoupdate" = "registry";
            volumes = [
              "/mnt/media/jellyfin/config:/config"
              "/mnt/media/jellyfin/cache:/cache"
              "/mnt/media/media:/media:ro"
            ];
            # Host networking preserves LAN broadcast discovery (UDP 7359).
            extraOptions = [ "--network=host" "--device=/dev/dri:/dev/dri" ];
          };

          redis-paperless = {
            image = "docker.io/library/redis:alpine";
            cmd = [ "redis-server" "--save" "" "--appendonly" "no" ];
            extraOptions = [ "--network=pi_net" ];
          };

          paperless = {
            image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
            labels."io.containers.autoupdate" = "registry";
            environmentFiles = [ "/mnt/media/paperless/paperless.env" ];
            environment = {
              PAPERLESS_REDIS = "redis://redis-paperless:6379";
              PAPERLESS_URL = "http://paperless.home.arpa";
              PAPERLESS_TIME_ZONE = "Asia/Kolkata";
              PAPERLESS_OCR_LANGUAGE = "eng";
            };
            volumes = [
              "/mnt/media/paperless/data:/usr/src/paperless/data"
              "/mnt/media/paperless/media:/usr/src/paperless/media"
              "/mnt/media/paperless/consume:/usr/src/paperless/consume"
              "/mnt/media/paperless/export:/usr/src/paperless/export"
            ];
            ports = [ "127.0.0.1:8000:8000" ];
            dependsOn = [ "redis-paperless" ];
            extraOptions = [ "--network=pi_net" ];
          };
          speedtest-tracker = {
            image = "lscr.io/linuxserver/speedtest-tracker:latest";
            labels."io.containers.autoupdate" = "registry";
            environmentFiles = [ "/mnt/media/speedtest-tracker/speedtest.env" ];
            environment = {
              PUID = "1000";
              PGID = "100";
              TZ = "Asia/Kolkata";
              DB_CONNECTION = "sqlite";
              CACHE_STORE = "file";
              APP_URL = "http://speedtest.home.arpa";
              SPEEDTEST_SCHEDULE = "0 */6 * * *";
            };
            volumes = [
              "/mnt/media/speedtest-tracker/config:/config"
            ];
            ports = [ "127.0.0.1:8081:80" ];
            extraOptions = [ "--network=pi_net" ];
          };
        };

        # Pull and restart application images daily; MariaDB stays pinned/manual.
        systemd.services.podman-auto-update = {
          description = "Update Podman application containers";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.podman}/bin/podman auto-update";
          };
        };
        systemd.timers.podman-auto-update = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 04:00:00";
            Persistent = true;
          };
        };
        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          virtualHosts = lib.mapAttrs (_: upstream: {
            listen = [{ addr = "0.0.0.0"; port = 80; }];
            locations."/" = {
              proxyPass = upstream;
              proxyWebsockets = true;
            };
          }) {
            "booklore.local" = "http://127.0.0.1:6060";
            "booklore.home.arpa" = "http://127.0.0.1:6060";
            "homeassistant.local" = "http://127.0.0.1:8123";
            "homeassistant.home.arpa" = "http://127.0.0.1:8123";
            "beszel.local" = "http://127.0.0.1:8090";
            "beszel.home.arpa" = "http://127.0.0.1:8090";
            "adguard.local" = "http://127.0.0.1:82";
            "adguard.home.arpa" = "http://127.0.0.1:82";
            "jellyfin.local" = "http://127.0.0.1:8096";
            "jellyfin.home.arpa" = "http://127.0.0.1:8096";
            "paperless.home.arpa" = "http://127.0.0.1:8000";
            "speedtest.home.arpa" = "http://127.0.0.1:8081";
          };
        };
        # Beszel Hub and agent use the native nixpkgs package/module.
        services.beszel.hub = {
          enable = true;
          host = "0.0.0.0";
          port = 8090;
        };

        # Pair this agent from the local Hub; secrets stay outside the flake.
        services.beszel.agent = {
          enable = true;
          environmentFile = "/home/suryavamsi/.config/beszel-agent.env";
          environment.LISTEN = "0.0.0.0:45876";
          openFirewall = true;
          smartmon.enable = false;
        };

        systemd.services.beszel-agent.unitConfig.ConditionFileNotEmpty =
          "/home/suryavamsi/.config/beszel-agent.env";

        services.journald.extraConfig = ''
          SystemMaxUse=100M
          RuntimeMaxUse=50M
        '';
        # Persist the cache with low-frequency RDB snapshots, not per-query AOF writes.
        services.redis.servers.unbound = {
          enable = true;
          bind = "127.0.0.1";
          port = 6379;
          unixSocket = null;
          appendOnly = false;
          save = [
            [ 900 1 ]
            [ 300 10 ]
            [ 60 10000 ]
          ];
          settings = {
            maxmemory = "128mb";
            maxmemory-policy = "allkeys-lru";
          };
        };

        services.unbound = {
          enable = true;
          package = pkgs.unbound.override {
            withSystemd = true;
            withRedis = true;
          };
          settings = {
            server.module-config = ''"validator cachedb iterator"'';
            cachedb = {
              backend = "redis";
              redis-server-host = "127.0.0.1";
              redis-server-port = 6379;
              redis-expire-records = true;
              redis-command-timeout = 20;
              redis-connect-timeout = 200;
            };
          };
        };
        systemd.services.unbound = {
          after = [ "redis-unbound.service" ];
          requires = [ "redis-unbound.service" ];
        };

        services.adguardhome = {
          enable = true;
          host = "0.0.0.0";
          port = 82;
          mutableSettings = true;
          settings = {
            # Listen on LAN and Tailscale; firewall still controls access.
            dns.bind_hosts = [ "192.168.0.105" "100.118.149.0" ];
            dns.upstream_dns = [ "127.0.0.1:53" ];
            filtering.rewrites = map (domain: {
              inherit domain;
              answer = "192.168.0.105";
              enabled = true;
            }) [
              "booklore.home.arpa"
              "homeassistant.home.arpa"
              "beszel.home.arpa"
              "adguard.home.arpa"
              "jellyfin.home.arpa"
              "paperless.home.arpa"
              "speedtest.home.arpa"
            ];
          };
        };

        systemd.tmpfiles.rules = [
          "d /mnt/media/jellyfin 0755 root root -"
          "d /mnt/media/jellyfin/config 0755 1000 1000 -"
          "d /mnt/media/jellyfin/cache 0755 1000 1000 -"
          "d /mnt/media/media 0755 root root -"
          "d /mnt/media/media/Anime 0755 suryavamsi users -"
          "d /mnt/media/paperless 0755 root root -"
          "d /mnt/media/paperless/data 0755 1000 1000 -"
          "d /mnt/media/paperless/media 0755 1000 1000 -"
          "d /mnt/media/paperless/consume 0775 1000 1000 -"
          "d /mnt/media/paperless/export 0755 1000 1000 -"
          "d /mnt/media/speedtest-tracker 0755 root root -"
          "d /mnt/media/speedtest-tracker/config 0755 1000 1000 -"
          "d /mnt/media/unbound/redis 0700 redis-unbound redis-unbound -"
          "Z /mnt/media/unbound/redis 0700 redis-unbound redis-unbound -"
        ];
        systemd.services.paperless-secret = {
          description = "Create the persistent Paperless secret key";
          wantedBy = [ "multi-user.target" ];
          after = [ "mnt-media.mount" ];
          requires = [ "mnt-media.mount" ];
          before = [ "podman-paperless.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.coreutils}/bin/mkdir -p /mnt/media/paperless
            if ! ${pkgs.coreutils}/bin/test -s /mnt/media/paperless/paperless.env; then
              printf 'PAPERLESS_SECRET_KEY=%s\\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" > /mnt/media/paperless/paperless.env
            fi
            ${pkgs.coreutils}/bin/chown root:root /mnt/media/paperless/paperless.env
            ${pkgs.coreutils}/bin/chmod 600 /mnt/media/paperless/paperless.env
          '';
        };
        systemd.services.speedtest-tracker-secret = {
          description = "Create the persistent Speedtest Tracker app key";
          wantedBy = [ "multi-user.target" ];
          after = [ "mnt-media.mount" ];
          requires = [ "mnt-media.mount" ];
          before = [ "podman-speedtest-tracker.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.coreutils}/bin/mkdir -p /mnt/media/speedtest-tracker
            if ! ${pkgs.coreutils}/bin/test -s /mnt/media/speedtest-tracker/speedtest.env; then
              printf 'APP_KEY=base64:%s\\n' "$(${pkgs.openssl}/bin/openssl rand -base64 32 | ${pkgs.coreutils}/bin/tr -d '\\n')" > /mnt/media/speedtest-tracker/speedtest.env
            fi
            ${pkgs.coreutils}/bin/chown root:root /mnt/media/speedtest-tracker/speedtest.env
            ${pkgs.coreutils}/bin/chmod 600 /mnt/media/speedtest-tracker/speedtest.env
          '';
        };
        systemd.services.adguardhome-data = {
          description = "Prepare persistent AdGuard Home data";
          wantedBy = [ "multi-user.target" ];
          after = [ "mnt-media.mount" ];
          requires = [ "mnt-media.mount" ];
          before = [ "adguardhome.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.coreutils}/bin/mkdir -p /mnt/media/adguard-home/native
            if ! ${pkgs.coreutils}/bin/test -s /mnt/media/adguard-home/native/AdGuardHome.yaml; then
              ${pkgs.coreutils}/bin/cp /mnt/media/adguard-home/config/AdGuardHome.yaml /mnt/media/adguard-home/native/AdGuardHome.yaml
              ${pkgs.coreutils}/bin/cp -a /mnt/media/adguard-home/work/. /mnt/media/adguard-home/native/
            fi
            ${pkgs.coreutils}/bin/chown -R adguardhome:adguardhome /mnt/media/adguard-home/native
          '';
        };

        systemd.services.adguardhome.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "adguardhome";
          Group = "adguardhome";
          StateDirectory = lib.mkForce null;
          Environment = "STATE_DIRECTORY=/var/lib/AdGuardHome";
          ReadWritePaths = [ "/var/lib/AdGuardHome" ];
        };
        systemd.services.pi-podman-network = {
          description = "Create the shared Podman network for Pi services";
          wantedBy = [ "multi-user.target" ];
          before = [
            "podman-mariadb.service"
            "podman-booklore.service"
            "podman-homeassistant.service"
            "podman-jellyfin.service"
            "podman-redis-paperless.service"
            "podman-paperless.service"
            "podman-speedtest-tracker.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.podman}/bin/podman network inspect pi_net >/dev/null 2>&1 || \
              ${pkgs.podman}/bin/podman network create --subnet 172.18.0.0/16 --gateway 172.18.0.1 pi_net
          '';
        };

        users.users.suryavamsi = {
          isNormalUser = true;
          description = "Surya Vamsi";
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwDnZy6d9YyrDiuySUorML1iFnmeqy1Lwq0qqQaIJ4+ surya@nixos"
          ];
        };
        users.groups.adguardhome = {};
        users.users.adguardhome = {
          isSystemUser = true;
          group = "adguardhome";
        };

        environment.systemPackages = with pkgs; [
          curl
          git
          htop
          tailscale
        ];

        system.stateVersion = "24.11";
      })
    ];
  };
}
