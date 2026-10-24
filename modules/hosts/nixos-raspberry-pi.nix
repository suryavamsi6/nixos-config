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
        # This Seagate bridge repeatedly wedges under UAS and takes the media
        # filesystem offline. Force the device-specific Bulk-Only fallback.
        boot.kernelParams = [ "usb-storage.quirks=0bc2:ab24:u" ];
        boot.kernel.sysctl."vm.swappiness" = 100;
        # NixOS pulls the ZFS kernel module, the zfs-zed daemon and the zfs
        # userspace tools into the closure unconditionally. This host boots
        # from an ext4 SD card and has no ZFS pools, so drop ZFS support.
        # boot.zfs.enabled itself is read-only; the supported-filesystem set
        # is the lever (see the example in nixos/modules/tasks/filesystems.nix).
        boot.supportedFilesystems.zfs = lib.mkForce false;

        # enableRedistributableFirmware installs the whole linux-firmware tree
        # (808 MB, dominated by qcom/intel/nvidia/mellanox blobs a Pi 4 can
        # never load). Keep only what the BCM43455 WiFi/BT combo chip and the
        # wireless regulatory database actually need (~25 MB).
        # lib.mkForce is required: the sd-card profile pulls in
        # nixos/modules/hardware/all-hardware.nix, which sets this to true.
        hardware.enableRedistributableFirmware = lib.mkForce false;
        hardware.wirelessRegulatoryDatabase = true;
        hardware.firmware = [
          # NVRAM/CLM blobs shipped by the Raspberry Pi firmware tree.
          pkgs.raspberrypiWirelessFirmware
          # brcmfmac blobs plus the CLM blob. linux-firmware's brcm/ tree is
          # full of symlinks into ../cypress/ (e.g. brcmfmac43455-sdio.bin ->
          # ../cypress/cyfmac43455-sdio.bin), so both directories must be
          # copied together or the links dangle and the firmware fixup aborts.
          (pkgs.runCommandLocal "linux-firmware-brcm" { } ''
            mkdir -p $out/lib/firmware
            cp -a ${pkgs.linux-firmware}/lib/firmware/brcm $out/lib/firmware/brcm
            cp -a ${pkgs.linux-firmware}/lib/firmware/cypress $out/lib/firmware/cypress
          '')
        ];

        zramSwap = {
          enable = true;
          algorithm = "zstd";
          memoryPercent = 75;
        };

        fileSystems."/mnt/media" = {
          device = "/dev/disk/by-uuid/a37619e1-b6dd-44f0-b07c-5f94698ba69b";
          fsType = "ext4";
          # DNS lives on the root filesystem, so a missing media disk must not
          # block the Pi from booting. Media-backed services require the mount.
          # x-systemd.automount keeps a re-plug self-healing: without it the
          # mount unit stays dead and an attached-but-unmounted disk sits unused
          # until someone starts the unit by hand (which is exactly what happened
          # between 2026-09-15 and today).
          options = [
            "nofail"
            "x-systemd.device-timeout=10s"
            "x-systemd.automount"
          ];
        };
        networking.hostName = "pi";

        # Permit the administrator to upload locally built, unsigned closures.
        # This is required for desktop-build/remote-activation deployments.
        nix.settings.trusted-users = [ "suryavamsi" ];

        # NixOS pins the evaluated nixpkgs flake in /etc/nix/registry.json by
        # default, which drags the entire ~485 MB nixpkgs source tree into the
        # system closure. This host is deployed from the desktop against a
        # path flake, so it needs no registry.
        nix.registry = lib.mkForce { };

        # Allow on-Pi flake commands (nixos-rebuild --flake, nix shell, ...).
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];

        # Nothing was collecting garbage: the store had reached 18 GB against
        # a 1.9 GB live closure.
        nix.gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 30d";
        };

        # Hermes and other tools stage prebuilt generic-Linux binaries (their
        # uv/Python/Node toolchain pieces, browser helpers, etc.). NixOS
        # ships only a stub loader at /lib/ld-linux-aarch64.so.1, which
        # refuses them with exit 127. nix-ld supplies a real loader plus the
        # shared libraries those prebuilt tools expect. The default library
        # set already covers uv (zlib, zstd, libgcc/libstdc++, openssl, xz);
        # the additions below cover a prebuilt CPython.
        programs.nix-ld = {
          enable = true;
          libraries = with pkgs; [
            libffi
            sqlite
            ncurses
            readline
            expat
            libxcrypt
          ];
        };

        # Generic-Linux prebuilt binaries (Hermes's staged CPython among
        # them) resolve the OpenSSL default CA file at /etc/ssl/cert.pem,
        # which NixOS does not ship. Point it at the system bundle so
        # certificate verification works out of the box for such tools.
        environment.etc."ssl/cert.pem".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

        networking.networkmanager.enable = true;
        # LAN-facing services; native Nginx owns port 80.
        networking.firewall.allowedTCPPorts = [
          22
          53
          80
          82
        ];
        networking.firewall.allowedUDPPorts = [ 53 ];

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
          nextcloud = {
            image = "docker.io/library/nextcloud:latest";
            labels."io.containers.autoupdate" = "registry";
            environment = {
              MYSQL_HOST = "mariadb";
              NEXTCLOUD_TRUSTED_DOMAINS = "nextcloud.home.arpa";
              OVERWRITEHOST = "nextcloud.home.arpa";
              OVERWRITEPROTOCOL = "http";
            };
            volumes = [
              "/mnt/media/nextcloud/html:/var/www/html"
              "/mnt/media/nextcloud/data:/var/www/html/data"
            ];
            ports = [ "127.0.0.1:8082:80" ];
            dependsOn = [ "mariadb" ];
            extraOptions = [ "--network=pi_net" ];
          };
          booklore = {
            image = "ghcr.io/grimmory-tools/grimmory:latest";
            labels."io.containers.autoupdate" = "registry";
            environmentFiles = [ "/home/suryavamsi/services/booklore/.env" ];
            environment = {
              JAVA_TOOL_OPTIONS = "-XX:MaxRAMPercentage=60 -XX:+UseSerialGC";
            };
            volumes = [
              "/mnt/media/booklore/data:/app/data"
              "/mnt/media/booklore/books:/books"
              "/mnt/media/booklore/bookdrop:/bookdrop"
            ];
            ports = [ "6060:6060" ];
            dependsOn = [ "mariadb" ];
            # Cap the container so the JVM sizes its heap against the cap,
            # not the Pi's total RAM. SerialGC has the smallest footprint.
            extraOptions = [
              "--network=pi_net"
              "--memory=320m"
            ];
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
          virtualHosts =
            lib.mapAttrs
              (_: upstream: {
                listen = [
                  {
                    addr = "0.0.0.0";
                    port = 80;
                  }
                ];
                locations."/" = {
                  proxyPass = upstream;
                  proxyWebsockets = true;
                };
              })
              {
                "booklore.local" = "http://127.0.0.1:6060";
                "booklore.home.arpa" = "http://127.0.0.1:6060";
                "adguard.local" = "http://127.0.0.1:82";
                "adguard.home.arpa" = "http://127.0.0.1:82";
                "speedtest.home.arpa" = "http://127.0.0.1:8081";
                "nextcloud.home.arpa" = "http://127.0.0.1:8082";
                # Dashboard binds 127.0.0.1:9119. Hermes Desktop on the Mac uses this name.
                "hermes.home.arpa" = "http://127.0.0.1:9119";
              };
        };
        services.cockpit = {
          enable = true;
          openFirewall = true;
          allowed-origins = [
            "https://192.168.0.105:9090"
            "https://cockpit.home.arpa:9090"
          ];
          plugins = [ pkgs.cockpit-podman ];
        };

        # Nix store builds do not include /etc in XDG_CONFIG_DIRS by default.
        # Add it so Cockpit serves the site-local branding below.
        systemd.services.cockpit.environment.XDG_CONFIG_DIRS = "/etc";
        systemd.services.cockpit-wsinstance-http.environment.XDG_CONFIG_DIRS = "/etc";
        systemd.services."cockpit-wsinstance-https@".environment.XDG_CONFIG_DIRS = "/etc";

        environment.etc."cockpit/branding/branding.css".text = ''
          :root {
            --ct-color-host-accent: #7c3aed !important;
            --pf-t--global--color--brand--default: #7c3aed;
            --pf-t--global--color--brand--hover: #6d28d9;
            --pf-t--global--border--radius--small: 8px;
            --pf-t--global--border--radius--medium: 12px;
            --pf-t--global--border--radius--large: 16px;
          }

          html body.login-pf {
            background:
              radial-gradient(circle at 15% 20%, rgb(124 58 237 / 38%), transparent 36%),
              radial-gradient(circle at 85% 80%, rgb(6 182 212 / 28%), transparent 38%),
              #0b1020;
          }

          .login-pf .card-pf {
            border: 1px solid rgb(148 163 184 / 25%);
            border-radius: 16px;
            box-shadow: 0 24px 70px rgb(2 6 23 / 45%);
          }

          #brand::before {
            content: "NixOS Pi";
            font-size: 1.5rem;
            font-weight: 700;
            letter-spacing: 0.04em;
          }
        '';

        services.journald.settings.Journal = {
          SystemMaxUse = "100M";
          RuntimeMaxUse = "50M";
        };

        services.redis.servers.unbound = {
          enable = true;
          bind = "127.0.0.1";
          port = 6379;
          unixSocket = null;
          appendOnly = false;
          # Unbound's Redis cache is disposable. Avoid periodic writes to disk
          # and let systemd keep its small state directory on the Pi root.
          save = [ ];
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
              # Avoid transient EAGAIN failures under DNS bursts.
              redis-command-timeout = 1000;
              redis-connect-timeout = 1000;
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
            dns.bind_hosts = [
              "192.168.0.105"
              "100.118.149.0"
            ];
            dns.upstream_dns = [ "127.0.0.1:53" ];
            filtering.rewrites =
              map
                (domain: {
                  inherit domain;
                  answer =
                    if domain == "homelab.home.arpa" then
                      "192.168.0.160"
                    else if domain == "homeassistant.home.arpa" then
                      "192.168.0.160"
                    else if domain == "litellm.home.arpa" then
                      "192.168.0.160"
                    else if domain == "mcp.home.arpa" then
                      "192.168.0.160"
                    else
                      "192.168.0.105";
                  enabled = true;
                })
                [
                  "booklore.home.arpa"
                  "adguard.home.arpa"
                  "speedtest.home.arpa"
                  "nextcloud.home.arpa"
                  "cockpit.home.arpa"
                  "hermes.home.arpa"
                  # homelab laptop (192.168.0.160), proxied by its nginx
                  "homelab.home.arpa"
                  "homeassistant.home.arpa"
                  "litellm.home.arpa"
                  "mcp.home.arpa"
                ];
          };
        };

        # Only create media paths after the external filesystem is mounted.
        # tmpfiles would otherwise create them on the SD card when it is absent.
        systemd.services.media-directories = {
          description = "Prepare external media directories";
          wantedBy = [ "multi-user.target" ];
          requires = [ "mnt-media.mount" ];
          after = [ "mnt-media.mount" ];
          before = [
            "speedtest-tracker-secret.service"
            "podman-mariadb.service"
            "podman-nextcloud.service"
            "podman-booklore.service"
            "podman-speedtest-tracker.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.coreutils}/bin/install -d -m 0755 -o root -g root \
              /mnt/media/media /mnt/media/nextcloud /mnt/media/speedtest-tracker
            ${pkgs.coreutils}/bin/install -d -m 0755 -o 1000 -g 1000 \
              /mnt/media/speedtest-tracker/config
            ${pkgs.coreutils}/bin/install -d -m 0755 -o suryavamsi -g users \
              /mnt/media/media/Anime
            ${pkgs.coreutils}/bin/install -d -m 0755 -o 33 -g 33 \
              /mnt/media/nextcloud/html
            ${pkgs.coreutils}/bin/install -d -m 0750 -o 33 -g 33 \
              /mnt/media/nextcloud/data
          '';
        };
        # Shrink MariaDB's RAM caches in the mutable custom.cnf on the media
        # disk: a personal Nextcloud + book catalog never touches the 256M
        # InnoDB pool or 64M query cache the stock template ships with. Only
        # the exact shipped values are rewritten, so later hand tuning is
        # respected; the container bounces once so the new sizes take effect.
        systemd.services.mariadb-tuning = {
          description = "Tune MariaDB buffer pools for a small instance";
          wantedBy = [ "multi-user.target" ];
          after = [ "media-directories.service" ];
          requires = [ "media-directories.service" ];
          before = [ "podman-mariadb.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            cfg=/mnt/media/booklore/mariadb/config/custom.cnf
            if [ -f "$cfg" ]; then
              changed=no
              if grep -q '^innodb_buffer_pool_size[[:space:]]*= 256M$' "$cfg"; then
                sed -i 's/^innodb_buffer_pool_size[[:space:]]*= 256M$/innodb_buffer_pool_size = 64M/' "$cfg"
                changed=yes
              fi
              if grep -q '^query_cache_size[[:space:]]*= 64M$' "$cfg"; then
                sed -i 's/^query_cache_size[[:space:]]*= 64M$/query_cache_size = 16M/' "$cfg"
                changed=yes
              fi
              if [ "$changed" = yes ]; then
                chown 911:911 "$cfg"
                systemctl try-restart podman-mariadb.service || true
              fi
            fi
          '';
        };
        systemd.services.speedtest-tracker-secret = {
          description = "Create the persistent Speedtest Tracker app key";
          wantedBy = [ "multi-user.target" ];
          after = [ "media-directories.service" ];
          requires = [ "media-directories.service" ];
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
        # On the first reboot after this change, migrate AdGuard while it is
        # stopped. The media mount is optional after that initial copy.
        systemd.services.adguardhome-data = {
          description = "Prepare root-backed AdGuard Home data";
          wantedBy = [ "multi-user.target" ];
          after = [
            "local-fs.target"
            "mnt-media.mount"
          ];
          before = [ "adguardhome.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            target=/var/lib/AdGuardHome
            media=/mnt/media/adguard-home/native
            ${pkgs.coreutils}/bin/install -d -m 0750 -o adguardhome -g adguardhome "$target"
            if ! ${pkgs.coreutils}/bin/test -s "$target/AdGuardHome.yaml"; then
              if ${pkgs.coreutils}/bin/test -s "$media/AdGuardHome.yaml"; then
                ${pkgs.coreutils}/bin/cp -a "$media/." "$target/"
              else
                echo "No AdGuard Home state is available to migrate" >&2
                exit 1
              fi
            fi
            ${pkgs.coreutils}/bin/chown -R adguardhome:adguardhome "$target"
          '';
        };

        systemd.services.adguardhome = {
          after = [ "adguardhome-data.service" ];
          requires = [ "adguardhome-data.service" ];
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "adguardhome";
            Group = "adguardhome";
            StateDirectory = lib.mkForce null;
            Environment = "STATE_DIRECTORY=/var/lib/AdGuardHome";
            ReadWritePaths = [ "/var/lib/AdGuardHome" ];
          };
        };
        systemd.services.pi-podman-network = {
          description = "Create the shared Podman network for Pi services";
          wantedBy = [ "multi-user.target" ];
          before = [
            "podman-mariadb.service"
            "podman-nextcloud.service"
            "podman-booklore.service"
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

        # Never let media-backed containers start against an empty /mnt/media
        # directory on the Pi's SD card.
        systemd.services.podman-mariadb = {
          requires = [ "media-directories.service" ];
          after = [ "media-directories.service" ];
        };
        systemd.services.podman-nextcloud = {
          requires = [ "media-directories.service" ];
          after = [ "media-directories.service" ];
        };
        systemd.services.podman-booklore = {
          requires = [ "media-directories.service" ];
          after = [ "media-directories.service" ];
        };
        systemd.services.podman-speedtest-tracker = {
          requires = [ "media-directories.service" ];
          after = [ "media-directories.service" ];
        };

        users.users.suryavamsi = {
          isNormalUser = true;
          linger = true;
          description = "Surya Vamsi";
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwDnZy6d9YyrDiuySUorML1iFnmeqy1Lwq0qqQaIJ4+ surya@nixos"
            # MacBook Air, so this machine can deploy #raspberry-pi.
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdi9zBb7cch8s8Gc6167hd8fkccFFHLg+j1IoJnnFrw suryavamsi6@users.noreply.github.com"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMusYxP9HC82z/wagX2SQFMFkAC8K0gvjLQK5Q3KVcZN d.suryavamsi@gmail.com"
          ];
        };
        users.groups.adguardhome = { };
        users.users.adguardhome = {
          isSystemUser = true;
          group = "adguardhome";
        };

        environment.systemPackages = with pkgs; [
          curl
          gh
          git
          htop
          tailscale
          # Node for Hermes tooling on the Pi (gateway PATH + skills).
          nodejs
          # General-purpose Python/uv tooling for agent-managed venvs and
          # ad-hoc scripts.
          uv
        ];

        system.stateVersion = "24.11";
      })
    ];
  };
}
