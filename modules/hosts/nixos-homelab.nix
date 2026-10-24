# Host: Homelab laptop server (x86_64-linux, hostname "homelab", user surya)
# MSI GP66 Leopard 11UG: i7-11800H (Intel Xe iGPU) + RTX 3070 mobile.
# Ported from the machine's own /etc/nixos (non-flake install, stateVersion 26.05).
# Originals kept verbatim in homelab-original/ for reference.
#
# GPU policy: everything runs on the Intel iGPU (00:02.0, i915). The NVIDIA
# dGPU is deliberately unused: nouveau is blacklisted and the card is left to
# runtime power management. To switch to NVIDIA later, drop the blacklist and
# wire the nvidia driver modules instead.
{
  config,
  inputs,
  ...
}:
{
  flake.nixosConfigurations.homelab = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      system = "x86_64-linux";
    };
    modules = with config.flake.modules; [
      nixos.nixSettings
      nixos.users
      nixos.locale # sets time.timeZone = "Asia/Kolkata"

      # Hardware scan from the laptop (ext4 root + ESP, Intel CPU, kvm-intel)
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          haosVersion = "18.3";
          # Pinned sha256 (hex) of haos_ova-18.3.qcow2.xz. Downloaded at
          # runtime ON the homelab by incus-haos-vm.service (not via fetchurl)
          # so the 510 MB image never enters the build closure or gets copied
          # over the LAN on every deploy.
          haosSha256 = "fae6a728768cc10aff60d4820bfcd40d64cd77fab82c8bd92af13b3d9d414090";
          # incus image import requires a metadata tarball next to the rootfs.
          haosMetadata =
            pkgs.runCommand "haos-${haosVersion}-metadata"
              {
                nativeBuildInputs = [ pkgs.gnutar ];
              }
              ''
                mkdir -p $out
                cat > metadata.yaml <<EOF
                architecture: x86_64
                creation_date: 1761180000
                properties:
                  description: Home Assistant OS ${haosVersion} (ova)
                  os: Home Assistant
                  release: ${haosVersion}
                EOF
                tar -cf $out/metadata.tar metadata.yaml
              '';

          # Power/RAPL sampler: real watts without extra tooling.
          powerDraw = pkgs.writeShellApplication {
            name = "power-draw";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gawk
              pkgs.bc
            ];
            text = ''
              set -euo pipefail
              interval="''${1:-5}"

              # Battery instantaneous draw (on AC this is the charge rate)
              for bat in /sys/class/power_supply/BAT*; do
                [ -d "$bat" ] || continue
                status=$(cat "$bat/status")
                if [ -f "$bat/power_now" ]; then
                  uw=$(cat "$bat/power_now")
                elif [ -f "$bat/current_now" ] && [ -f "$bat/voltage_now" ]; then
                  uw=$(( $(cat "$bat/current_now") * $(cat "$bat/voltage_now") / 1000000 ))
                else
                  continue
                fi
                printf 'battery: %s (%.2f W)\n' "$status" "$(echo "scale=2; $uw / 1000000" | bc)"
              done

              # RAPL: CPU package energy over the interval (package domain
              # only — nested domains double-count)
              for pkg in /sys/class/powercap/intel-rapl:*; do
                [ -f "$pkg/energy_uj" ] || continue
                name=$(cat "$pkg/name")
                e1=$(cat "$pkg/energy_uj")
                sleep "$interval"
                e2=$(cat "$pkg/energy_uj")
                [ "$e2" -ge "$e1" ] || e2=$((e2 + 4294967295)) # u32 counter wrap
                printf 'rapl %s: %.2f W (over %ss)\n' "$name" \
                  "$(echo "scale=2; ($e2 - $e1) / 1000000 / $interval" | bc)" "$interval"
                break
              done

              f=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')
              printf 'cpu median freq: %s MHz\n' "$((f / 1000))"
            '';
          };
        in
        {
          imports = [ ./homelab-hardware-configuration.nix ];

          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;

          networking.hostName = "homelab";
          networking.networkmanager.enable = true;
          # WiFi power-save adds tens of ms latency jitter; off until ethernet
          # takes over as the primary link (and harmless after).
          networking.networkmanager.wifi.powersave = false;
          # Incus on NixOS requires nftables (assertion in the module).
          networking.nftables.enable = true;
          # Incus API + web UI from the desktop.
          networking.firewall.allowedTCPPorts = [
            80
            443 # nginx reverse proxy
            8443
            8123 # Home Assistant (proxied to the HAOS VM)
            4000 # LiteLLM UI + API (OCI container)
            3000 # MCPHub dashboard + MCP endpoints
          ];
          # The VMs/containers DHCP against dnsmasq on incusbr0; without
          # trusting the bridge the firewall drops their discover packets.
          networking.firewall.trustedInterfaces = [ "incusbr0" ];
          # Allow pushing closures from the desktop (`nixos-rebuild
          # --target-host surya@…`) without root on the target.
          nix.settings.trusted-users = [
            "root"
            "@wheel"
          ];

          services.openssh.enable = true;
          # Headless server: keep running with the lid closed.
          services.logind.settings.Login.HandleLidSwitch = "ignore";

          # NOTE: battery 80% cap is enforced BY THE EC — set once via MSI
          # Center on Windows and it persists across reboots/wipes (verified:
          # capacity 80, "Not charging" under NixOS). The msi_ec kernel module
          # cannot load on this firmware ('1543EMS1.115' not whitelisted); do
          # NOT re-add it to boot.kernelModules. The battery-charge-limit
          # service stays as a no-op detector in case a future kernel adds
          # support and an explicit sysfs write is ever wanted.
          boot.kernelModules = [ "kvm-intel" ];

          # Keep the battery between charges capped at 80%.
          systemd.services.battery-charge-limit = {
            description = "Cap battery charge at 80% (msi-ec)";
            wantedBy = [ "multi-user.target" ];
            after = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              for bat in /sys/class/power_supply/BAT*; do
                if [ -w "$bat/charge_control_end_threshold" ]; then
                  echo 80 > "$bat/charge_control_end_threshold"
                else
                  echo "battery-charge-limit: no charge_control_end_threshold on $bat" >&2
                fi
              done
            '';
          };

          # --- GPU policy: Intel iGPU only ---
          # nouveau: keep the dGPU unbound so nothing wakes it; runtime PM (below)
          # lets it drop to D3cold. snd_hda_intel: the NVIDIA HDMI audio function
          # is an idle power waker and this server has no audio use at all.
          boot.blacklistedKernelModules = [
            "nouveau"
            "snd_hda_intel"
          ];
          hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
          # Let the idle dGPU drop to runtime suspend (D3) when nothing binds it.
          services.udev.extraRules = ''
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{power/control}="auto"
          '';

          # --- Low-power server tuning ---
          # Base clock (no turbo): an 11800H at 2.3 GHz is ample for HA + Incus
          # and is the single biggest heat reduction. Remove this param to
          # re-enable turbo.
          boot.kernelParams = [
            "intel_pstate=no_turbo"
            # Headless: turn the internal eDP panel output off entirely.
            "video=eDP-1:d"
          ];
          powerManagement.cpuFreqGovernor = "powersave";
          powerManagement.powertop.enable = true; # USB / PCIe ASPM / SATA autosuspend
          services.thermald.enable = true; # Intel thermal protection
          services.fstrim.enable = true; # weekly SSD trim

          # intel_pstate energy-performance preference: favour efficiency.
          systemd.services.cpu-epp = {
            description = "Set CPU energy_performance_preference to balance_power";
            wantedBy = [ "multi-user.target" ];
            after = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                echo balance_power > "$cpu" 2>/dev/null || true
              done
            '';
          };

          # Soft-block Bluetooth at boot (rfkill, not a driver blacklist, so a
          # future USB BLE dongle for Home Assistant still works).
          systemd.services.rfkill-bluetooth = {
            description = "Soft-block Bluetooth radio";
            wantedBy = [ "multi-user.target" ];
            after = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [ pkgs.util-linux ];
            script = ''
              rfkill block bluetooth 2>/dev/null || true
            '';
          };

          users.users.surya = {
            isNormalUser = true;
            extraGroups = [
              "wheel"
              "networkmanager"
              "incus-admin"
            ];
            packages = [ ];
          };

          programs.gnupg.agent = {
            enable = true;
            enableSSHSupport = true;
          };

          environment.systemPackages = [
            pkgs.tree
            pkgs.powertop # interactive: sudo powertop (estimates + tunables)
            powerDraw # power-draw [seconds]: battery W + RAPL CPU watts
            pkgs.skopeo # required by incus for OCI (docker/ghcr) images
          ];

          # --- Incus (OCI + system containers + VMs) ---
          virtualisation.incus = {
            enable = true;
            ui.enable = true; # web UI on https://homelab:8443
            preseed = {
              # NOTE: keys with dots must stay quoted or Nix nests them into
              # maps and the YAML becomes invalid for Incus.
              config = {
                "core.https_address" = ":8443";
              };
              networks = [
                {
                  name = "incusbr0";
                  type = "bridge";
                  config = {
                    "ipv4.address" = "10.110.0.1/24";
                    "ipv4.nat" = "true";
                    "ipv6.address" = "none";
                  };
                }
              ];
              storage_pools = [
                {
                  name = "default";
                  driver = "dir";
                }
              ];
              profiles = [
                {
                  name = "default";
                  devices = {
                    eth0 = {
                      name = "eth0";
                      nictype = "bridged";
                      parent = "incusbr0";
                      type = "nic";
                    };
                    root = {
                      path = "/";
                      pool = "default";
                      type = "disk";
                    };
                  };
                }
              ];
            };
          };

          # --- Home Assistant OS as an Incus VM (idempotent, runs once) ---
          systemd.services.incus-haos-vm = {
            description = "Provision Home Assistant OS ${haosVersion} Incus VM";
            wantedBy = [ "multi-user.target" ];
            after = [
              "incus.service"
              "network-online.target"
            ];
            wants = [ "network-online.target" ];
            requires = [ "incus.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [
              pkgs.xz
              pkgs.incus
              pkgs.curl
              pkgs.coreutils
            ];
            script = ''
              set -euo pipefail
              vm=home-assistant
              if incus list --format csv -c n | grep -qx "$vm"; then
                echo "$vm already exists, nothing to do"
                exit 0
              fi

              # Download directly on this host (single stream from GitHub,
              # verified against the pinned hash) instead of pushing the
              # image through the build closure.
              url="https://github.com/home-assistant/operating-system/releases/download/${haosVersion}/haos_ova-${haosVersion}.qcow2.xz"
              archive=/var/lib/incus/haos_${haosVersion}.qcow2.xz
              img=/var/lib/incus/haos_${haosVersion}.qcow2
              if [ ! -f "$archive" ]; then
                curl -fL --retry 3 -o "$archive.tmp" "$url"
                echo "${haosSha256}  $archive.tmp" | sha256sum -c -
                mv "$archive.tmp" "$archive"
              fi

              xz -dc "$archive" > "$img"
              incus image import ${haosMetadata}/metadata.tar "$img" --alias "haos-${haosVersion}"

              # HAOS is not secure-boot signed; disable SB for this VM only.
              incus init --vm "haos-${haosVersion}" "$vm" \
                -c security.secureboot=false \
                -c limits.memory=3GiB \
                -c limits.cpu=2
              incus config device override "$vm" root size=32GiB
              # Stable VM IP (DHCP reservation) + host port-forward so HA is
              # reachable at http://192.168.0.160:8123 from the LAN.
              incus config device set "$vm" eth0 ipv4.address=10.110.0.10 ||
                incus config device override "$vm" eth0 ipv4.address=10.110.0.10
              incus config device add "$vm" ha-ui proxy \
                listen=tcp:0.0.0.0:8123 connect=tcp:10.110.0.10:8123
              incus config set "$vm" boot.autostart=true
              incus start "$vm"

              rm -f "$img"
            '';
          };

          # --- LiteLLM UI needs Postgres ---
          # The nixpkgs build cannot run Prisma migrations (no engine binaries),
          # so the gateway is the official OCI image. It reaches Postgres on the
          # host via the Incus bridge. Login is admin / LITELLM_MASTER_KEY from
          # /var/lib/litellm/secrets.env (generated on first boot, not in git).
          services.postgresql = {
            enable = true;
            # The Incus container reaches Postgres at 10.110.0.1 (incusbr0).
            enableTCPIP = true;
            ensureDatabases = [ "litellm" ];
            ensureUsers = [
              {
                name = "litellm";
                ensureDBOwnership = true;
              }
            ];
            authentication = ''
              local all all peer
              host litellm litellm 10.110.0.0/24 scram-sha-256
              host all all 127.0.0.1/32 scram-sha-256
              host all all ::1/128 scram-sha-256
            '';
          };

          systemd.services.litellm-db-init = {
            description = "Create LiteLLM database credentials";
            wantedBy = [ "multi-user.target" ];
            after = [ "postgresql.service" ];
            requires = [ "postgresql.service" ];
            serviceConfig.Type = "oneshot";
            path = [
              config.services.postgresql.package
              pkgs.openssl
              pkgs.gnused
              pkgs.coreutils
              pkgs.util-linux # runuser
            ];
            script = ''
              set -euo pipefail
              install -d -m 700 /var/lib/litellm
              secrets=/var/lib/litellm/secrets.env
              if [ ! -f "$secrets" ]; then
                dbpass=$(openssl rand -hex 24)
                master=$(openssl rand -hex 24)
                umask 077
                printf 'DATABASE_URL=postgresql://litellm:%s@10.110.0.1:5432/litellm\nLITELLM_MASTER_KEY=sk-%s\n' \
                  "$dbpass" "$master" > "$secrets"
              fi
              dbpass=$(sed -n 's|^DATABASE_URL=postgresql://litellm:\([^@]*\)@.*|\1|p' "$secrets")
              runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c \
                "ALTER ROLE litellm WITH LOGIN PASSWORD '$dbpass'"
            '';
          };

          # Official image. No host config mount: a bind mount made the
          # container exit immediately. Models are added in the UI (stored in
          # Postgres). UI: http://192.168.0.160:4000/ui
          systemd.services.incus-litellm = {
            description = "Provision LiteLLM Incus container";
            wantedBy = [ "multi-user.target" ];
            after = [
              "incus.service"
              "litellm-db-init.service"
              "network-online.target"
            ];
            wants = [ "network-online.target" ];
            requires = [
              "incus.service"
              "litellm-db-init.service"
            ];
            serviceConfig = {
              Type = "simple";
              Restart = "on-failure";
              RestartSec = "10s";
            };
            path = [
              pkgs.incus
              pkgs.gnugrep
              pkgs.coreutils
            ];
            script = ''
              set -euo pipefail
              incus remote list --format csv | cut -d, -f1 | grep -qx ghcr ||
                incus remote add ghcr https://ghcr.io --protocol=oci

              secrets=/var/lib/litellm/secrets.env
              set -a
              # shellcheck disable=SC1090
              . "$secrets"
              set +a

              if ! incus list --format csv -c n | grep -qx litellm; then
                incus init ghcr:berriai/litellm:main-stable litellm \
                  -c boot.autostart=true \
                  -c limits.memory=2GiB \
                  -c limits.cpu=2 \
                  -c environment.DATABASE_URL="$DATABASE_URL" \
                  -c environment.LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
                  -c environment.STORE_MODEL_IN_DB=True
                incus config device add litellm api proxy \
                  listen=tcp:0.0.0.0:4000 connect=tcp:10.110.0.20:4000 nat=true
                incus config device override litellm eth0 ipv4.address=10.110.0.20
              fi

              state=$(incus list litellm --format csv -c s)
              if [ "$state" != RUNNING ]; then
                incus start litellm
              fi
              while ! incus list litellm --format csv -c s | grep -qx RUNNING; do
                sleep 3
              done
            '';
          };

          # --- MCPHub gateway as an Incus OCI container (idempotent) ---
          # Official image is Docker-only and not in nixpkgs. Data (users,
          # settings, credential key) lives on the host at
          # /var/lib/incus/mcphub/data. First boot prints a random admin
          # password: `incus exec mcphub -- cat /proc/1/fd/1` or the Incus UI
          # console. Dashboard: http://192.168.0.160:3000
          # Not a oneshot: image pull must not block nixos-rebuild.
          systemd.services.incus-mcphub = {
            description = "Provision MCPHub Incus container";
            wantedBy = [ "multi-user.target" ];
            after = [
              "incus.service"
              "network-online.target"
            ];
            wants = [ "network-online.target" ];
            requires = [ "incus.service" ];
            serviceConfig = {
              Type = "simple";
              Restart = "on-failure";
              RestartSec = "15s";
            };
            path = [
              pkgs.incus
              pkgs.gnugrep
              pkgs.coreutils
              pkgs.openssl
            ];
            script = ''
              set -euo pipefail
              incus remote list --format csv | cut -d, -f1 | grep -qx docker ||
                incus remote add docker https://docker.io --protocol=oci

              mkdir -p /var/lib/incus/mcphub/data
              # shift=true: container root can write a root-owned host dir.
              # A plain bind mount is EACCES (idmapped UIDs) and the app exits.

              # JWT_SECRET is random per process unless pinned. A restart then
              # rejects every saved browser token and the UI shows
              # "Failed to retrieve server data".
              install -d -m 700 /var/lib/incus/mcphub
              jwt=/var/lib/incus/mcphub/jwt-secret
              if [ ! -s "$jwt" ]; then
                umask 077
                openssl rand -hex 32 > "$jwt"
              fi

              if ! incus list --format csv -c n | grep -qx mcphub; then
                incus init docker:samanhappy/mcphub:latest mcphub \
                  -c boot.autostart=true \
                  -c limits.memory=1GiB \
                  -c limits.cpu=1
                incus config device add mcphub data disk \
                  source=/var/lib/incus/mcphub/data path=/app/data shift=true
                incus config device add mcphub ui proxy \
                  listen=tcp:0.0.0.0:3000 connect=tcp:10.110.0.30:3000 nat=true
                incus config device override mcphub eth0 ipv4.address=10.110.0.30
              fi

              if incus list --format csv -c n | grep -qx mcphub; then
                current=$(incus config get mcphub environment.JWT_SECRET || true)
                if [ -z "$current" ]; then
                  incus config set mcphub environment.JWT_SECRET="$(tr -d '\n' < "$jwt")"
                fi
                unset current
              fi

              state=$(incus list mcphub --format csv -c s)
              if [ "$state" != RUNNING ]; then
                incus start mcphub
              fi
              # Stay up so activation does not wait on the image pull, but
              # exit once the container is running so Restart does not loop.
              while ! incus list mcphub --format csv -c s | grep -qx RUNNING; do
                sleep 5
              done
            '';
          };

          # --- nginx reverse proxy: one hostname per service ---
          # Naming follows the pi's convention: <service>.home.arpa (RFC 8375),
          # with AdGuard rewrites on the pi (192.168.0.105) resolving them to
          # this host. nip.io aliases answer the same vhosts for clients not
          # using the pi for DNS:
          #   homeassistant.home.arpa -> Home Assistant
          #   litellm.home.arpa       -> LiteLLM
          #   mcp.home.arpa           -> MCPHub
          #   homelab.home.arpa       -> landing page (also http://192.168.0.160/)
          # Future services: add one entry to `proxyHosts` below, add the same
          # name to the pi's adguardhome rewrites, and switch both hosts.
          # The Incus UI deliberately stays direct on https://192.168.0.160:8443
          # — its client-certificate TLS cannot pass through an HTTP proxy.
          # TLS uses a self-signed wildcard cert generated on first boot
          # (browser warning expected; trust it or keep using port 80).
          services.nginx =
            let
              domain = "home.arpa";
              # Public-DNS aliases that embed the IP; no setup needed.
              nip = "192.168.0.160.nip.io";
              cert = "/var/lib/nginx-certs/cert.pem";
              key = "/var/lib/nginx-certs/key.pem";
              tls = {
                sslCertificate = cert;
                sslCertificateKey = key;
              };
              proxyHosts = {
                homeassistant = {
                  port = 8123;
                  websockets = true;
                };
                litellm = {
                  port = 4000;
                };
                mcp = {
                  port = 3000;
                };
              };
              landing = pkgs.writeTextDir "index.html" ''
                <!DOCTYPE html>
                <html><head><meta charset="utf-8"><title>homelab</title>
                <style>body{font-family:sans-serif;max-width:40rem;margin:4rem auto}
                a{display:block;padding:.6rem 0;font-size:1.2rem}</style></head>
                <body><h1>homelab services</h1>
                <a href="http://homeassistant.${domain}">Home Assistant</a>
                <a href="http://litellm.${domain}">LiteLLM</a>
                <a href="http://mcp.${domain}">MCPHub</a>
                <a href="https://192.168.0.160:8443">Incus UI (direct, client cert)</a>
                </body></html>
              '';
            in
            {
              enable = true;
              recommendedProxySettings = true;
              recommendedGzipSettings = true;
              virtualHosts =
                (lib.mapAttrs (
                  name: cfg:
                  {
                    serverName = "${name}.${domain}";
                    serverAliases = [ "${name}.${nip}" ];
                    addSSL = true;
                    locations."/" = {
                      proxyPass = "http://127.0.0.1:${toString cfg.port}";
                      proxyWebsockets = cfg.websockets or false;
                    };
                  }
                  // tls
                ) proxyHosts)
                // {
                  "homelab.${domain}" = {
                    default = true;
                    serverAliases = [ "homelab.${nip}" ];
                    addSSL = true;
                    root = "${landing}";
                  }
                  // tls;
                };
            };

          systemd.services.nginx-wildcard-cert = {
            description = "Self-signed wildcard cert for the reverse proxy";
            before = [ "nginx.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              StateDirectory = "nginx-certs";
              UMask = "0077";
            };
            path = [ pkgs.openssl ];
            script = ''
              dir=/var/lib/nginx-certs
              gen() {
                umask 077
                openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
                  -keyout "$dir/key.pem" -out "$dir/cert.pem" \
                  -subj "/CN=homelab.home.arpa" \
                  -addext "subjectAltName=DNS:home.arpa,DNS:*.home.arpa,DNS:192.168.0.160.nip.io,DNS:*.192.168.0.160.nip.io"
              }
              if [ ! -s "$dir/key.pem" ]; then
                gen
              elif ! openssl x509 -in "$dir/cert.pem" -noout -ext subjectAltName 2>/dev/null | grep -q "home.arpa"; then
                # earlier cert generation lacked the home.arpa names
                gen
              fi
            '';
          };
          systemd.services.nginx = {
            after = [ "nginx-wildcard-cert.service" ];
            requires = [ "nginx-wildcard-cert.service" ];
          };

          # --- OpenBot server in an Ubuntu 24.04 Incus container (idempotent) ---
          # The upstream installer is Ubuntu-only (apt-get + in-image setup
          # script), so it runs inside the container. Agents are reached via
          # your OpenBot account (desktop/mobile app or openbot.run/app);
          # finish with:  incus exec openbot -- sudo openbot login
          systemd.services.incus-openbot = {
            description = "Provision OpenBot server Incus container";
            wantedBy = [ "multi-user.target" ];
            after = [
              "incus.service"
              "network-online.target"
            ];
            wants = [ "network-online.target" ];
            requires = [ "incus.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [
              pkgs.incus
              pkgs.gnugrep
            ];
            script = ''
              set -euo pipefail
              if incus list --format csv -c n | grep -qx openbot; then
                echo "openbot already exists, nothing to do"
                exit 0
              fi

              incus launch images:ubuntu/24.04 openbot -c boot.autostart=true
              # Wait for container network + apt to be ready.
              sleep 15
              incus exec openbot -- cloud-init status --wait >/dev/null 2>&1 || true
              incus exec openbot -- bash -c \
                'curl -fsSL https://raw.githubusercontent.com/nightly-labs/openbot/main/scripts/install-server.sh | sudo bash -s -- --user openbot'
            '';
          };

          # Installed with NixOS 26.05; do not change.
          system.stateVersion = "26.05";
        }
      )
    ];
  };
}
