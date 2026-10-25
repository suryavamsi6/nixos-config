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
      ./hermes-bridge # services.hermesBridge: management API for the Hermes phone app

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

          # Dev Lens (built from source; no published image) returns
          # public_contract. LiteLLM v1.106.2's ServiceStatus model rejects
          # that extra field, so the sidebar stays "not connected" until this
          # one field is accepted. Idempotent; skipped if the image already
          # has the field or the class shape moved.
          litellmLensStatusPatch = pkgs.writeText "litellm-lens-status-patch.py" ''
            import glob
            import pathlib
            import sys

            matches = sorted(
                glob.glob("/app/.venv/lib/python*/site-packages/litellm/proxy/lens/ingestion.py")
            )
            if len(matches) != 1:
                print(f"lens patch: expected 1 ingestion.py, found {matches}", file=sys.stderr)
                sys.exit(0)
            path = pathlib.Path(matches[0])
            src = path.read_text()
            marker = "class ServiceStatus(Record):"
            start = src.find(marker)
            if start < 0:
                print("lens patch: ServiceStatus missing, skipped", file=sys.stderr)
                sys.exit(0)
            nxt = src.find("\nclass ", start + len(marker))
            body = src[start:nxt if nxt > 0 else None]
            if "public_contract:" in body:
                print("lens patch: already applied")
                sys.exit(0)
            needle = "    protocol_version: int = 0\n"
            at = body.find(needle)
            if at < 0:
                print("lens patch: ServiceStatus shape changed, skipped", file=sys.stderr)
                sys.exit(0)
            insert_at = start + at + len(needle)
            path.write_text(src[:insert_at] + "    public_contract: int = 0\n" + src[insert_at:])
            print("lens patch: applied")
          '';
          # LiteLLM proxy config. Models live in Postgres, not here.
          # drop_params: the harness (and other OpenAI-shaped clients) sends
          # `store`, which xai-based routes reject with
          # UnsupportedParamsError → HTTP 400. Dropping unsupported params
          # keeps one client body working across grok, openai and local
          # routes instead of pinning per-provider allowlists.
          litellmLensTracingConfig = pkgs.writeText "litellm-lens-tracing.yaml" ''
            general_settings:
              tracing:
                store:
                  type: lens
            litellm_settings:
              drop_params: true
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
          # systemd user unit for the Hermes dashboard inside the incus-hermes
          # container below. Upstream does not start the dashboard with its
          # gateway service (NousResearch/hermes-agent#16702), so it gets its
          # own unit; %h expands to /home/hermes under the user manager.
          hermesDashboardUnit = pkgs.writeText "hermes-dashboard.service" ''
            [Unit]
            Description=Hermes web dashboard (port 9119)

            [Service]
            EnvironmentFile=%h/.hermes/.env
            ExecStart=%h/.local/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open
            Restart=on-failure
            RestartSec=5

            [Install]
            WantedBy=default.target
          '';
          # Tailscale Funnel that puts the Hermes API server (not the
          # dashboard) on the internet for the Hermes phone app, at
          # https://homelab.<tailnet>.ts.net. Off until this host is logged in
          # to Tailscale and the tailnet allows Funnel (docs/hermes-funnel.md);
          # while false only the Funnel job is absent (tailscaled itself is
          # always on, see services.tailscale below), so this file deploys
          # as-is.
          hermesFunnel = {
            enable = true; # TODO(surya): true once the runbook's admin-console steps are done
            target = "http://10.110.0.50:8642"; # API server in the Incus container
            # Extra path mounts on the same :443 Funnel; "/" (target) always comes first.
            mounts = lib.optional config.services.hermesBridge.enable {
              path = config.services.hermesBridge.funnelPath;
              target = config.services.hermesBridge.funnelTarget;
            };
          };
          # Loopback feed for the Homepage dashboard tiles: Incus memory per
          # instance, top units/processes by RSS, hwmon temperatures, and the
          # AdGuard query log. AdGuard's API 401s without a WWW-Authenticate
          # header, so challenge-response cannot work and the collector sends
          # basic auth up front from the same env file the dashboard reads.
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
              exec python3 ${./homelab-stats/homelab_stats.py} "$@"
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
            80 # Caddy reverse proxy (HTTP only; TLS is not required on the LAN)
            8443
            8123 # Home Assistant (proxied to the HAOS VM)
            4000 # LiteLLM UI + API (OCI container)
            3000 # MCPHub dashboard + MCP endpoints
            4318 # LiteLLM Lens UI (standalone; also embedded in the LiteLLM sidebar)
            8283 # Matterbridge web UI (QR pairing for SmartThings commissioning)
            5540 # Matterbridge commissioning/session port (phone connects here)
          ];
          # The VMs/containers DHCP against dnsmasq on incusbr0; without
          # trusting the bridge the firewall drops their discover packets.
          networking.firewall.trustedInterfaces = [ "incusbr0" ];
          # Static home.arpa pins: outbound calls from this host (Homepage
          # widgets and site monitors) must resolve the LAN service names
          # no matter which DNS the LAN hands out. Other LAN clients get
          # the same names from the pi's AdGuard rewrites.
          networking.hosts = {
            "192.168.0.160" = [
              "homelab.home.arpa"
              "homeassistant.home.arpa"
              "litellm.home.arpa"
              "lens.home.arpa"
              "mcp.home.arpa"
              "hermes.home.arpa"
              "board.home.arpa"
              "search.home.arpa"
              "booklore.home.arpa"
            ];
            "192.168.0.105" = [
              "adguard.home.arpa"
              "nextcloud.home.arpa"
              "speedtest.home.arpa"
              "cockpit.home.arpa"
              "glances.home.arpa"
            ];
          };
          # Allow pushing closures from the desktop (`nixos-rebuild
          # --target-host surya@…`) without root on the target.
          nix.settings.trusted-users = [
            "root"
            "@wheel"
          ];

          services.openssh.enable = true;
          # Headless server: keep running with the lid closed.
          services.logind.settings.Login.HandleLidSwitch = "ignore";

          # Reflect mDNS between the LAN (WiFi uplink) and the Incus bridge:
          # lets the HAOS VM see LAN zeroconf/mDNS devices (ESPHome etc.) and
          # lets its Matter-hub announcements reach LAN clients for
          # commissioning from phone apps. The host uplink is WiFi, which
          # rules out a macvlan NIC for the VM (APs drop foreign source
          # MACs), so a reflector is the only viable bridge.
          services.avahi = {
            enable = true;
            reflector = true;
            # Opens UDP 5353 so LAN clients (phone Matter commissioning,
            # discovery queries) can reach mDNS on this host at all.
            openFirewall = true;
            allowInterfaces = [
              "wlp5s0"
              "incusbr0"
            ];
          };

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

          # Compressed RAM swap. 16 GB laptop, ~10 GB of containers and
          # no disk swap: a burst goes straight to the OOM killer (it
          # killed litellm's Prisma query engine on 2026-10-25). zram
          # gives cold anonymous pages a compressible place to go
          # without wearing the NVMe.
          zramSwap = {
            enable = true;
            algorithm = "zstd";
            memoryPercent = 50; # ~8 GiB
          };

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

          # raw.idmap for the hermes work mount (incus-hermes below):
          # newuidmap enforces /etc/subuid + /etc/subgid even for the
          # root daemon, and the incus module grants root only the
          # 1000000+ container range. Mapping host surya (1000) and
          # group users (100) into the container needs exactly these
          # two ids granted as well; module list merging appends them
          # to the incus module's range.
          users.users.root.subUidRanges = [
            {
              startUid = 1000;
              count = 1;
            }
          ];
          users.users.root.subGidRanges = [
            {
              startGid = 100;
              count = 1;
            }
          ];

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
          # Lens env is applied when /var/lib/litellm/lens.env exists (or can
          # be snapshotted from the running container). The unit never rotates
          # those secrets and never deletes the container.
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
                  -c limits.memory=3GiB \
                  -c limits.cpu=2 \
                  -c environment.DATABASE_URL="$DATABASE_URL" \
                  -c environment.LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
                  -c environment.STORE_MODEL_IN_DB=True
                incus config device add litellm api proxy \
                  listen=tcp:0.0.0.0:4000 connect=tcp:10.110.0.20:4000 nat=true
                incus config device override litellm eth0 ipv4.address=10.110.0.20
              fi

              # `init` sets limits only at creation; reconcile the cap
              # here (a memory raise applies live, no restart). The 2GiB
              # cap OOM-killed the Prisma query engine on 2026-10-25.
              if [ "$(incus config get litellm limits.memory)" != "3GiB" ]; then
                incus config set litellm limits.memory=3GiB
              fi

              # Point the gateway at the Lens container. Secrets stay in
              # lens.env (mode 600), never in the flake. Snapshot them from
              # the container the first time this unit runs after a hand setup.
              lens_env=/var/lib/litellm/lens.env
              if [ ! -s "$lens_env" ]; then
                svc=$(incus config get litellm environment.LITELLM_LENS_SERVICE_TOKEN || true)
                gw=$(incus config get litellm environment.LENS_GATEWAY_SECRET || true)
                if [ -n "$svc" ] && [ -n "$gw" ]; then
                  umask 077
                  printf 'LITELLM_LENS_SERVICE_TOKEN=%s\nLENS_GATEWAY_SECRET=%s\n' \
                    "$svc" "$gw" > "$lens_env"
                fi
                unset svc gw
              fi
              if [ -s "$lens_env" ]; then
                set -a
                # shellcheck disable=SC1090
                . "$lens_env"
                set +a
                incus config set litellm environment.LITELLM_LENS_URL=http://10.110.0.40:4318
                incus config set litellm environment.LITELLM_LENS_PUBLIC_URL=http://192.168.0.160:4318
                incus config set litellm environment.LITELLM_LENS_SERVICE_TOKEN="$LITELLM_LENS_SERVICE_TOKEN"
                incus config set litellm environment.LENS_GATEWAY_SECRET="$LENS_GATEWAY_SECRET"
                incus config set litellm environment.CONFIG_FILE_PATH=/app/config.yaml
                # Push only on a real content change (checksum, not the old
                # "is lens tracing present" test, which never updated a config
                # that already had the tracing block). A changed config needs
                # a restart: the proxy reads it once at startup.
                config_changed=0
                want=$(sha256sum ${litellmLensTracingConfig} | cut -d' ' -f1)
                have=$(incus file pull litellm/app/config.yaml - 2>/dev/null | sha256sum | cut -d' ' -f1)
                if [ "$want" != "$have" ]; then
                  incus file push ${litellmLensTracingConfig} litellm/app/config.yaml
                  config_changed=1
                fi
              fi

              state=$(incus list litellm --format csv -c s)
              if [ "$state" != RUNNING ]; then
                incus start litellm
              fi
              if [ "''${config_changed:-0}" = 1 ]; then
                incus restart litellm
              fi
              while ! incus list litellm --format csv -c s | grep -qx RUNNING; do
                sleep 3
              done

              # Re-apply the ServiceStatus compatibility patch. A container
              # recreate drops it; a restart does not. Restart only when the
              # file actually changed, so a normal boot does not bounce the API.
              incus file push ${litellmLensStatusPatch} litellm/app/lens-status-patch.py
              if incus exec litellm -- python3 /app/lens-status-patch.py | grep -qx 'lens patch: applied'; then
                incus restart litellm
              fi
            '';
          };

          # Lens has no published image. The running `lens` container is a
          # one-time source build (BerriAI/lens + ClickHouse via Docker
          # Compose inside an Ubuntu system container). This unit only keeps
          # that container's address, port forward, and autostart. It does
          # not clone or compile Lens.
          systemd.services.incus-lens = {
            description = "Keep the Lens observability container addressable";
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
              pkgs.coreutils
            ];
            script = ''
              set -euo pipefail
              if ! incus list --format csv -c n | grep -qx lens; then
                echo "lens container is absent; it is a one-time source build, not provisioned here"
                exit 0
              fi
              incus config set lens boot.autostart=true
              incus config set lens limits.memory=3GiB
              incus config set lens limits.cpu=2
              ip=$(incus config device get lens eth0 ipv4.address || true)
              if [ "$ip" != 10.110.0.40 ]; then
                incus config device override lens eth0 ipv4.address=10.110.0.40
              fi
              if ! incus config device show lens | grep -q '^ui:'; then
                incus config device add lens ui proxy \
                  listen=tcp:0.0.0.0:4318 connect=tcp:10.110.0.40:4318 nat=true
              fi
              state=$(incus list lens --format csv -c s)
              if [ "$state" != RUNNING ]; then
                incus start lens
              fi
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

          # --- Hermes agent in an Ubuntu 24.04 Incus container (idempotent) ---
          # Migrated off the pi, where it ran as user state under ~/.hermes
          # plus host-side nix-ld/cert.pem workarounds. Hermes publishes no
          # OCI image and self-manages a floating git checkout with a prebuilt
          # uv/Node toolchain, so it wants a plain FHS userspace; a system
          # container provides that without touching this NixOS host, keeps
          # the agent off this host's wheel/incus-admin user, and puts an
          # `incus snapshot` rollback boundary around `hermes update`.
          # Dashboard: http://hermes.home.arpa (Caddy -> 10.110.0.50:9119,
          # plain HTTP like the other vhosts, so Hermes Desktop's Electron
          # client can attach). The dashboard binds 0.0.0.0 inside the
          # container (bridge-only reachability); that engages Hermes's auth
          # gate, so basic-auth credentials are generated once and appended
          # to ~/.hermes/.env. Read them with:
          #   sudo cat /var/lib/incus/hermes/dashboard.env
          #
          # Computer use: the gateway is headless, so computer_use drives a
          # Bot Screen — a per-profile Xvnc + Xfce desktop this unit installs
          # — through cua-driver, which the Hermes installer already stages
          # into ~/.hermes/tools. Three pieces keep it working:
          #   * limits.memory 8GiB. The bot_desktop gate measures free memory
          #     as min(host MemAvailable, cgroup headroom) and refuses below
          #     bot_desktop.min_free_memory_mb (1536). At 2GiB the idle
          #     gateway (~1.2GiB) left ~0.8GiB of headroom, so the screen
          #     could never start.
          #   * TigerVNC + Xfce plus at-spi2-core (its org.a11y.Bus D-Bus
          #     activation is what makes cua-driver's ax_capability pass).
          #   * bot_desktop.auto_start, so the first computer_use call brings
          #     the screen up instead of waiting for someone to press Start.
          # There is no port to open: the RFB socket is a 0600 Unix socket in
          # the container and the dashboard streams it over its own auth.
          # One-time state migration from the pi, run on this host before the
          # first deploy of this unit (stop the pi's hermes gateway first so
          # sessions are consistent; keep the pi copy until this runs):
          #   sudo install -d -m 700 /var/lib/incus/hermes/state
          #   sudo rsync -a --exclude hermes-agent --exclude tools \
          #     --exclude logs --exclude telemetry pi:.hermes/ \
          #     /var/lib/incus/hermes/state/
          # The aarch64 toolchain pieces are excluded on purpose: the
          # installer restages them for x86_64; only architecture-neutral
          # state (config.yaml, .env, sessions, memories, skills, pairing,
          # cron, hooks) moves over.
          # Management API for the Hermes phone app (profiles, MCP, routines,
          # skills, plugins, memory), next to Hermes in this container and
          # published at /bridge by the Funnel job. ./hermes-bridge,
          # docs/hermes-bridge.md.
          services.hermesBridge.enable = true;

          systemd.services.incus-hermes = {
            description = "Provision Hermes agent Incus container";
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
              pkgs.coreutils
              pkgs.gnutar
              pkgs.openssl
            ];
            script = ''
              set -euo pipefail
              exists=no
              if incus list --format csv -c n | grep -qx hermes; then
                exists=yes
              fi

              if [ "$exists" = no ]; then
                incus launch images:ubuntu/24.04 hermes \
                  -c boot.autostart=true \
                  -c limits.memory=8GiB \
                  -c limits.cpu=6
                incus config device override hermes eth0 ipv4.address=10.110.0.50
                sleep 15
                incus exec hermes -- cloud-init status --wait >/dev/null 2>&1 || true
                incus exec hermes -- apt-get update -qq
                # libX*/xkb: the prebuilt cua-driver (computer-use helper)
                # links against them; without the libs its staged
                # verification exits 127 and the tool is skipped.
                incus exec hermes -- apt-get install -y -qq git curl ca-certificates \
                  libxi6 libxrandr2 libxrender1 libx11-6 libxext6 \
                  libxkbcommon0 libxkbcommon-x11-0

                # Dedicated user; the agent's whole world is its $HOME.
                incus exec hermes -- useradd -m -s /bin/bash hermes
                incus exec hermes -- bash -c \
                  'echo "hermes ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/hermes && chmod 440 /etc/sudoers.d/hermes'
              fi

              # `launch` only sets limits at creation, so a container that
              # predates these caps keeps its old ones until reconciled
              # here. Raising memory or cpu takes effect live (cgroup),
              # no restart.
              if [ "$(incus config get hermes limits.memory)" != "8GiB" ]; then
                incus config set hermes limits.memory=8GiB
              fi
              if [ "$(incus config get hermes limits.cpu)" != "6" ]; then
                incus config set hermes limits.cpu=6
              fi

              # Bot Screen display stack: Xvnc + Xfce give the bot its own X
              # display, and at-spi2-core is what cua-driver's ax_capability
              # probes for (org.a11y.Bus activation); libatspi2 alone is not
              # enough. Deliberately not upstream's xfce4 metapackage — it
              # pulls the screensaver, power manager and polkit agent that
              # lock or prompt a headless session. Gated on Xvnc so an
              # existing container picks this up on the next switch without
              # re-running apt on every activation.
              if ! incus exec hermes -- test -x /usr/bin/Xvnc; then
                incus exec hermes -- apt-get update -qq
                incus exec hermes -- env DEBIAN_FRONTEND=noninteractive \
                  apt-get install -y -qq --no-install-recommends \
                  tigervnc-standalone-server xfce4-panel xfwm4 xfdesktop4 \
                  xfce4-settings xfce4-terminal dbus-x11 x11-xserver-utils \
                  x11-utils x11-xkb-utils xauth fonts-dejavu-core \
                  at-spi2-core
              fi

              # Must exist before either the state import or the auth append
              # writes into it: on a fresh install the tree only appears at
              # the installer's config stage, and `>> ~/.hermes/.env` fails
              # with ENOENT when the parent is missing.
              incus exec hermes -- install -d -o hermes -g hermes -m 700 /home/hermes/.hermes

              # Import migrated state before the first install; the installer
              # keeps an existing config.yaml/.env and only fills gaps.
              state=/var/lib/incus/hermes/state
              if [ -d "$state" ] && [ -n "$(ls -A "$state")" ]; then
                incus exec hermes -- install -d -o hermes -g hermes /home/hermes/.hermes
                tar -C "$state" -cf - . | incus exec hermes -- tar -C /home/hermes/.hermes --no-same-owner -xf -
                incus exec hermes -- chown -R hermes:hermes /home/hermes/.hermes
              fi

              # Generate once, never rotate (rotation would lock out saved
              # Hermes Desktop logins) and never print.
              install -d -m 700 /var/lib/incus/hermes
              auth=/var/lib/incus/hermes/dashboard.env
              if [ ! -s "$auth" ]; then
                umask 077
                printf 'HERMES_DASHBOARD_BASIC_AUTH_USERNAME=surya\nHERMES_DASHBOARD_BASIC_AUTH_PASSWORD=%s\nHERMES_DASHBOARD_BASIC_AUTH_SECRET=%s\n' \
                  "$(openssl rand -hex 12)" "$(openssl rand -hex 24)" > "$auth"
              fi
              incus exec hermes -- sudo -u hermes -- bash -c \
                'grep -q "^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=" ~/.hermes/.env 2>/dev/null || { printf "\n# dashboard auth for hermes.home.arpa\n"; cat; } >> ~/.hermes/.env' < "$auth"
              incus exec hermes -- sudo -u hermes -- chmod 600 /home/hermes/.hermes/.env

              # --non-interactive skips the TTY setup/gateway stages; on a
              # fresh (non-migrated) install run `hermes setup` inside the
              # container afterwards for provider keys. Install once: the
              # update path afterwards is `hermes update` in the container
              # (same as the pi setup), not a rerun of this unit.
              if ! incus exec hermes -- sudo -u hermes -- test -x /home/hermes/.local/bin/hermes; then
                incus exec hermes -- sudo -iu hermes -- \
                  bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive'
              fi

              # Gateway: upstream-managed systemd service. Linger keeps the
              # user services alive without a login session.
              incus exec hermes -- loginctl enable-linger hermes
              uid=$(incus exec hermes -- id -u hermes | tr -d '\r\n ')
              incus exec hermes -- systemctl start "user@$uid.service" 2>/dev/null || true
              incus exec hermes -- sudo -iu hermes -- hermes gateway install --if-missing </dev/null

              # Dashboard: its own user unit, pushed from the Nix store so
              # the definition stays in this file.
              incus exec hermes -- install -d -o hermes -g hermes /home/hermes/.config/systemd/user
              incus file push ${hermesDashboardUnit} \
                hermes/home/hermes/.config/systemd/user/hermes-dashboard.service
              incus exec hermes -- chown hermes:hermes /home/hermes/.config/systemd/user/hermes-dashboard.service
              incus exec hermes -- sudo -u hermes -- \
                env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user daemon-reload
              incus exec hermes -- sudo -u hermes -- \
                env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user enable --now hermes-dashboard.service

              # Computer use on a chat-only bot: auto_start brings the Bot
              # Screen up on the first computer_use call instead of waiting
              # for someone to press Start in the dashboard. `hermes config
              # set` merges YAML, so this is idempotent and leaves the rest of
              # config.yaml (models, platforms, dashboard auth) untouched. The
              # gateway reads config at startup, so restart it when the value
              # actually changed.
              gateway_restarted=no
              restart_reasons=""
              if [ "$(incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes \
                        config get bot_desktop.auto_start 2>/dev/null | tr -d '\r\n')" != "true" ]; then
                incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes \
                  config set bot_desktop.auto_start true
                restart_reasons="$restart_reasons bot_desktop.auto_start"
              fi

              # API server for the Hermes phone app, reached through Tailscale
              # Funnel (tailscaled on this host -> 10.110.0.50:8642).
              # It binds 0.0.0.0 inside the container (bridge-only, like the
              # dashboard) and always requires the bearer key. Same pattern as
              # the dashboard auth: generated once, never rotated (rotation
              # would sign the phone out), never printed. Each variable is
              # appended only if ~/.hermes/.env lacks it, so a key migrated
              # from the pi wins. Read the key the phone needs with:
              #   sudo cat /var/lib/incus/hermes/api-server.env
              # (if ~/.hermes/.env already had API_SERVER_KEY, that one is live).
              api=/var/lib/incus/hermes/api-server.env
              if [ ! -s "$api" ]; then
                umask 077
                printf 'API_SERVER_ENABLED=true\nAPI_SERVER_HOST=0.0.0.0\nAPI_SERVER_PORT=8642\nAPI_SERVER_KEY=%s\n' \
                  "$(openssl rand -hex 32)" > "$api"
              fi
              api_added=$(incus exec hermes -- sudo -u hermes -- bash -c '
                env=~/.hermes/.env; touch "$env"; added=0
                while IFS= read -r line; do
                  [ -n "$line" ] || continue
                  if ! grep -q "^''${line%%=*}=" "$env"; then
                    [ "$added" = 1 ] || printf "\n# API server for the Hermes phone app (Tailscale Funnel)\n" >> "$env"
                    printf "%s\n" "$line" >> "$env"; added=1
                  fi
                done
                chmod 600 "$env"; echo "$added"' < "$api" | tr -d '\r\n')
              if [ "$api_added" = 1 ]; then
                restart_reasons="$restart_reasons api_server"
              fi
              # One listener serves every profile under /p/<profile>/...; each
              # named profile then needs its own API_SERVER_KEY in
              # ~/.hermes/profiles/<name>/.env or its prefix fails closed.
              if [ "$(incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes \
                        config get gateway.multiplex_profiles 2>/dev/null | tr -d '\r\n')" != "true" ]; then
                incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes \
                  config set gateway.multiplex_profiles true
                restart_reasons="$restart_reasons gateway.multiplex_profiles"
              fi

              # The gateway reads .env and config.yaml at startup: restart once
              # for everything that changed above.
              if [ -n "$restart_reasons" ]; then
                incus exec hermes -- sudo -u hermes -- \
                  env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user restart hermes-gateway.service
                gateway_restarted=yes
              fi

              echo "Hermes container ready; dashboard at http://hermes.home.arpa"
              if [ "$gateway_restarted" = yes ]; then
                echo "hermes-gateway restarted for:$restart_reasons"
              fi

              # Host code workspace: ~/hermes-work bind-mounted at
              # /home/hermes/work, no shift. hermes is 1001:1001 inside
              # (uid 1000 is taken by the Ubuntu image) while surya is
              # 1000:100 on the host, so raw.idmap aligns the ids
              # instead: hermes's writes land as surya:users and vice
              # versa (see also the root subUid/subGid grants above).
              # Deliberately last: a restart must not precede the
              # systemctl --user calls above — seconds after a
              # container restart the user manager's bus socket is
              # not up yet and they fail with "Failed to connect to
              # bus" (seen 2026-10-25, switch gen 34). The map
              # applies at container start, so restart only when it
              # actually changed. Never widen this to all of
              # ~surya: it holds SSH keys and other credentials.
              install -d -o surya -g users -m 700 /home/surya/hermes-work
              idmap=$(incus config get hermes raw.idmap 2>/dev/null || true)
              case "$idmap" in
                *"uid 1000 1001"*"gid 100 1001"*) : ;;
                *)
                  printf 'uid 1000 1001\ngid 100 1001\n' |
                    incus config set hermes raw.idmap -
                  incus restart hermes
                  ;;
              esac
              if ! incus config device show hermes | grep -q '^work:'; then
                incus config device add hermes work disk \
                  source=/home/surya/hermes-work path=/home/hermes/work
              fi
            '';
          };

          # --- Grimmory (Booklore) library in Incus, migrated off the pi ---
          # The pi's `booklore` podman container ran ghcr.io/grimmory-tools/
          # grimmory (the Booklore-derived library server; the "booklore"
          # container/tile/env names are historical). Two Incus OCI containers
          # replace it: `booklore` (the app, 10.110.0.61) and `booklore-db`
          # (linuxserver MariaDB pinned at exactly the pi's 11.4.5 so the
          # imported SQL matches the engine it was dumped from; the datadir
          # files themselves are root-only on the pi, which is why the
          # database moves as a mariadb-dump instead of a file copy). The
          # pi keeps its MariaDB for Nextcloud; only the booklore database
          # moved. Host data: /var/lib/incus/booklore/{db,data,books,
          # bookdrop}, bind-mounted shift=true like mcphub's. One-time
          # migration: the books/data/bookdrop trees and env were staged
          # (as surya, no root) in ~/booklore-migration/ by streaming from
          # the pi; the dump lands there as import.sql. The unit adopts all
          # of it on first run (fresh db -> dump import -> the app's DB
          # user, then import.sql is renamed .done) and never touches live
          # data afterwards. The pi's copy under /mnt/media/booklore stays
          # as the rollback. Port 6060 is not
          # published to the LAN (Caddy is the door, as booklore.home.arpa),
          # which also drops the pi's old 0.0.0.0:6060 publish. Updates and
          # env-file changes: `incus delete -f booklore && sudo systemctl
          # restart incus-booklore` re-creates the container from the
          # current :latest and re-reads the env; host data survives.
          #
          # Grimmory's real env contract is USER_ID/GROUP_ID (entrypoint
          # su-exec), SERVER_PORT, DATABASE_URL/DATABASE_USERNAME/
          # DATABASE_PASSWORD. The pi .env's APP_USER_ID/BOOKLORE_PORT/
          # DB_USER-style keys are compose-interpolation names the image
          # never read; on the pi they worked by accident because
          # DB_PASSWORD equals MYSQL_ROOT_PASSWORD, so the app's root
          # fallback could authenticate. This unit maps the .env inputs to
          # the real names. Root SQL goes through unix_socket: linuxserver
          # MariaDB 11.4.5's root refuses password auth entirely, and
          # `incus exec` runs as the container's root, so `mariadb -uroot`
          # without -p just works — while `mariadb-admin ping` lies (it
          # reports success even on access-denied), hence -uroot there too.
          systemd.services.incus-booklore = {
            description = "Provision Grimmory library + MariaDB Incus containers";
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
              pkgs.gnused
              pkgs.openssl
            ];
            script = ''
              set -euo pipefail
              incus remote list --format csv | cut -d, -f1 | grep -qx ghcr ||
                incus remote add ghcr https://ghcr.io --protocol=oci
              incus remote list --format csv | cut -d, -f1 | grep -qx lscr ||
                incus remote add lscr https://lscr.io --protocol=oci

              state=/var/lib/incus/booklore
              staging=/home/surya/booklore-migration
              install -d -m 700 "$state"

              install -d "$state/db"
              # One-time adoption of the staged pi copy (first run only:
              # later runs see non-empty live dirs and never overwrite).
              for d in data books bookdrop; do
                install -d "$state/$d"
                if [ -z "$(ls -A "$state/$d")" ] && [ -d "$staging/$d" ] && [ -n "$(ls -A "$staging/$d")" ]; then
                  cp -a "$staging/$d/." "$state/$d/"
                fi
              done
              # Seed dump for the first-run import below (.done is the
              # "already imported" marker).
              if [ -s "$staging/import.sql" ] && [ ! -e "$state/db/import.sql.done" ]; then
                install -m 600 "$staging/import.sql" "$state/db/import.sql"
              fi

              # Same env-file contract as the pi: one file holding the app
              # keys and the MariaDB keys together. Adopt the migrated file,
              # or seed a fresh one for an empty install. Generated once,
              # never rotated, never printed.
              env=$state/booklore.env
              if [ ! -s "$env" ]; then
                if [ -s "$staging/booklore.env" ]; then
                  install -m 600 "$staging/booklore.env" "$env"
                else
                  umask 077
                  {
                    printf 'TZ=Etc/UTC\n'
                    printf 'BOOKLORE_PORT=6060\n'
                    printf 'DATABASE_URL=jdbc:mariadb://10.110.0.60:3306/booklore\n'
                    printf 'DB_USER=grimmory\n'
                    printf 'DB_PASSWORD=%s\n' "$(openssl rand -hex 16)"
                    printf 'MYSQL_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 24)"
                    printf 'MYSQL_DATABASE=booklore\n'
                  } > "$env"
                fi
              fi
              chmod 600 "$env"

              set -a
              # shellcheck disable=SC1090
              . "$env"
              set +a
              # The migrated DATABASE_URL names the pi's podman alias
              # ("mariadb"); point it at the db container's static address,
              # keeping port, database and any query params intact.
              appurl=$(printf '%s' "$DATABASE_URL" | sed -E 's#(://[^/:]+)#://10.110.0.60#')

              if ! incus list --format csv -c n | grep -qx booklore-db; then
                incus init lscr:linuxserver/mariadb:11.4.5 booklore-db \
                  -c boot.autostart=true \
                  -c limits.memory=1GiB \
                  -c limits.cpu=1 \
                  -c environment.TZ="$TZ" \
                  -c environment.MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
                  -c environment.MYSQL_DATABASE="$MYSQL_DATABASE"
                incus config device add booklore-db db disk \
                  source=$state/db path=/config shift=true
                incus config device override booklore-db eth0 ipv4.address=10.110.0.60
              fi

              if [ "$(incus list '^booklore-db$' --format csv -c s)" != RUNNING ]; then
                incus start booklore-db
              fi
              # MariaDB must accept connections before the JVM starts, or
              # Spring Boot exits and an Incus container stays down until
              # the next reconcile (Restart=on-failure here is the retry).
              i=0
              until incus exec booklore-db -- mariadb-admin -uroot ping >/dev/null 2>&1; do
                i=$((i + 1))
                if [ "$i" -ge 60 ]; then
                  echo "booklore-db: mariadb not answering after 60 tries" >&2
                  exit 1
                fi
                sleep 5
              done

              # First-run import: load the pi dump and create the app's
              # database user (a mariadb-dump carries neither users nor
              # grants; DB_USER here is "booklore", not root). Runs before
              # the app starts so Spring Boot sees a complete schema.
              # Single quotes in values are doubled for SQL. mariadb runs
              # as container root over unix_socket (no -p; see header).
              if [ -f "$state/db/import.sql" ]; then
                incus exec booklore-db -- mariadb -uroot \
                  < "$state/db/import.sql"
                if [ "$DB_USER" != "root" ]; then
                  q() { printf '%s' "$1" | sed "s/'/'''/g"; }
                  dbuser=$(q "$DB_USER")
                  dbpass=$(q "$DB_PASSWORD")
                  grants=$state/grants.sql
                  printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\n" "$dbuser" "$dbpass" > "$grants"
                  printf "GRANT ALL PRIVILEGES ON %s.* TO '%s'@'%%';\n" "$MYSQL_DATABASE" "$dbuser" >> "$grants"
                  printf "FLUSH PRIVILEGES;\n" >> "$grants"
                  chmod 600 "$grants"
                  incus exec booklore-db -- mariadb -uroot \
                    < "$grants"
                  rm -f "$grants"
                fi
                mv "$state/db/import.sql" "$state/db/import.sql.done"
              fi

              if ! incus list --format csv -c n | grep -qx booklore; then
                incus init ghcr:grimmory-tools/grimmory:latest booklore \
                  -c boot.autostart=true \
                  -c limits.memory=1GiB \
                  -c limits.cpu=1 \
                  -c environment.USER_ID=1000 \
                  -c environment.GROUP_ID=1000 \
                  -c environment.TZ="$TZ" \
                  -c environment.SERVER_PORT="$BOOKLORE_PORT" \
                  -c environment.DATABASE_URL="$appurl" \
                  -c environment.DATABASE_USERNAME="$DB_USER" \
                  -c environment.DATABASE_PASSWORD="$DB_PASSWORD"
                incus config device add booklore data disk \
                  source=$state/data path=/app/data shift=true
                incus config device add booklore books disk \
                  source=$state/books path=/books shift=true
                incus config device add booklore bookdrop disk \
                  source=$state/bookdrop path=/bookdrop shift=true
                incus config device override booklore eth0 ipv4.address=10.110.0.61
              fi

              if [ "$(incus list '^booklore$' --format csv -c s)" != RUNNING ]; then
                incus start booklore
              fi
              # Exit once running so Restart does not loop (mcphub pattern).
              while ! incus list '^booklore$' --format csv -c s | grep -qx RUNNING; do
                sleep 3
              done
            '';
          };

          # --- Tailscale (same as the pi) ---
          # Joins homelab to the tailnet once `sudo tailscale up` has been run;
          # until then tailscaled idles in NeedsLogin. No exit node or subnet
          # routes, so tailnet peers reach only this host, and the NixOS
          # firewall still applies on tailscale0 (it is not a trusted
          # interface). openFirewall stays off (the pi has it on): it only
          # opens UDP 41641 for inbound direct connections. Without it, NAT
          # traversal still makes direct peer-to-peer links in most cases
          # (both sides punch out through the LAN router); only when that fails
          # does traffic fall back to the slower DERP relays. Turn it on if
          # `tailscale ping <peer>` from here keeps reporting "via DERP".
          services.tailscale = {
            enable = true;
            openFirewall = false;
            useRoutingFeatures = "none";
          };
          # Incus already forces nftables here; keep tailscaled's own rules in
          # nftables too instead of letting it guess between backends.
          systemd.services.tailscaled.environment.TS_DEBUG_FIREWALL_MODE = "nftables";

          # --- Tailscale Funnel: Hermes API for the phone app ---
          # Outbound-only (tailscaled dials Tailscale's relays), so no firewall
          # port opens. Only the API server (8642, at /) and hermes-bridge (at
          # /bridge, docs/hermes-bridge.md) are published; the dashboard
          # (9119) stays LAN-only behind Caddy. The API still demands its
          # bearer key. Funnel's proxy flushes text/event-stream as it is
          # written, so chat replies stream. Setup and test steps:
          # docs/hermes-funnel.md.

          # Reconciles the Funnel: publishes hermesFunnel.target at / and each
          # of hermesFunnel.mounts at its path on :443 when the node is logged
          # in, and leaves mounts that already match alone. It
          # runs on every deploy and then every 2 min, and always exits 0, so
          # a deploy before `sudo tailscale up` (or before the tailnet policy
          # allows Funnel) still switches cleanly; it just logs why it waited
          # (journalctl -u hermes-funnel) and picks itself up afterwards. The
          # enable call is wrapped in a timeout because the CLI can block
          # waiting for an admin to approve Funnel. Setting enable = false
          # only removes this job; tailscaled keeps the Funnel it already set
          # up, so run `sudo tailscale funnel reset` too (docs/hermes-funnel.md).
          systemd.services.hermes-funnel = lib.mkIf hermesFunnel.enable {
            description = "Tailscale Funnel for the Hermes API (phone app)";
            after = [
              "tailscaled.service"
              "network-online.target"
            ];
            wants = [
              "tailscaled.service"
              "network-online.target"
            ];
            wantedBy = [ "multi-user.target" ];
            path = [
              config.services.tailscale.package
              pkgs.jq
              pkgs.coreutils
            ];
            serviceConfig.Type = "oneshot";
            script = ''
              state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "Unknown"' || true)
              state=''${state:-unreachable}
              if [ "$state" != Running ]; then
                echo "tailscale is $state, not Running; run 'sudo tailscale up' (docs/hermes-funnel.md). Retrying in 2 min." >&2
                exit 0
              fi
              # One "path target" pair per line; "/" first so the API server keeps the root.
              while read -r mount target; do
                if tailscale funnel status --json | jq -e --arg m "$mount" --arg t "$target" '
                      ([.Web // {} | to_entries[] | select(.key | endswith(":443")) | .value.Handlers[$m].Proxy] | index($t)) != null
                      and ([.AllowFunnel // {} | to_entries[] | select(.key | endswith(":443")) | .value] | any)' >/dev/null; then
                  echo "Funnel already serves $target at $mount on :443"
                elif timeout 60 tailscale funnel --bg --yes --https=443 --set-path "$mount" "$target" </dev/null; then
                  echo "Funnel enabled for $target at $mount on :443"
                else
                  echo "Funnel not enabled yet for $mount (is HTTPS on and the funnel nodeAttr in the tailnet policy? docs/hermes-funnel.md). Retrying in 2 min." >&2
                fi
              done <<'MOUNTS'
              ${lib.concatMapStringsSep "\n" (m: "${m.path} ${m.target}") (
                [
                  {
                    path = "/";
                    target = hermesFunnel.target;
                  }
                ]
                ++ hermesFunnel.mounts
              )}
              MOUNTS
              tailscale funnel status || true
            '';
          };
          systemd.timers.hermes-funnel = lib.mkIf hermesFunnel.enable {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "1min";
              OnUnitInactiveSec = "2min";
            };
          };

          # --- Homepage dashboard (https://gethomepage.dev/) ---
          # Replaces the old static landing page: one dashboard listing this
          # host's Incus services and the pi's, served by Caddy at
          # homelab.home.arpa (also http://192.168.0.160/). It binds
          # 0.0.0.0:8082 but the firewall keeps that port closed — Caddy on
          # this host is the only intended client.
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
            # Widget credentials come from the env file seeded by the
            # homepage-dashboard-secrets unit below ({{HOMEPAGE_VAR_*}}).
            environmentFiles = [ "/var/lib/homepage-dashboard-env/secrets.env" ];
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
                # the cpu widget). Pi host stats come from glances below.
                resources = {
                  label = "Homelab";
                  cpu = true;
                  memory = true;
                  disk = "/";
                  # CPU package temperature straight from hwmon (no lm_sensors
                  # on this host); Pi temperature comes from glances below.
                  cputemp = true;
                  uptime = true;
                };
              }
              {
                # Pi host feed: glances in webserver mode on the pi (see
                # its host file), proxied by its nginx at glances.home.arpa
                # and pinned in networking.hosts.
                glances = {
                  url = "http://glances.home.arpa";
                  version = 4;
                  label = "Raspberry Pi";
                  cpu = true;
                  mem = true;
                  cputemp = true;
                  uptime = true;
                  disk = [
                    "/"
                    "/mnt/media"
                  ];
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
                      siteMonitor = "http://192.168.0.160:8123";
                    };
                  }
                  {
                    LiteLLM = {
                      href = "http://litellm.home.arpa/";
                      icon = "mdi-robot-outline";
                      description = "Model gateway. Incus container. The UI is at /ui.";
                      siteMonitor = "http://192.168.0.160:4000";
                    };
                  }
                  {
                    "LiteLLM Lens" = {
                      href = "http://lens.home.arpa/";
                      icon = "mdi-telescope";
                      description = "Traces for the model gateway. Incus container.";
                      siteMonitor = "http://192.168.0.160:4318";
                    };
                  }
                  {
                    MCPHub = {
                      href = "http://mcp.home.arpa/";
                      icon = "mdi-hub";
                      description = "MCP server gateway. Incus container.";
                      siteMonitor = "http://192.168.0.160:3000";
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
                      description = "LiteLLM database. Loopback only, no page.";
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
                ];
              }
            ];
          };

          # One-time seed of widget credentials for the dashboard. Homepage
          # reads it via environmentFiles and substitutes
          # {{HOMEPAGE_VAR_*}} placeholders in its YAML configs. Fill it in
          # on the homelab once, then:
          #   systemctl restart homepage-dashboard
          # Mode 0644 because the dashboard runs as a DynamicUser with no
          # stable uid (only root and surya have accounts on this host).
          systemd.services.homepage-dashboard-secrets = {
            description = "Seed Homepage dashboard widget credentials";
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
              secrets=/var/lib/homepage-dashboard-env/secrets.env
              if [ ! -f "$secrets" ]; then
                {
                  echo "# Homepage dashboard widget credentials - edit me, then:"
                  echo "#   systemctl restart homepage-dashboard"
                  echo "# AdGuard Home web login (http://adguard.home.arpa)"
                  echo "HOMEPAGE_VAR_ADGUARD_USERNAME=changeme"
                  echo "HOMEPAGE_VAR_ADGUARD_PASSWORD=changeme"
                  echo "# Home Assistant long-lived access token:"
                  echo "# profile (bottom-left) > Security > Long-lived access tokens"
                  echo "HOMEPAGE_VAR_HA_TOKEN=changeme"
                  echo "# Nextcloud NC-Token: Settings > Administration > System"
                  echo "HOMEPAGE_VAR_NEXTCLOUD_TOKEN=changeme"
                  echo "# Booklore account (same as the web login)"
                  echo "HOMEPAGE_VAR_BOOKLORE_USERNAME=changeme"
                  echo "HOMEPAGE_VAR_BOOKLORE_PASSWORD=changeme"
                } > "$secrets"
              fi
              chmod 0644 "$secrets"
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
              EnvironmentFile = "-/var/lib/homepage-dashboard-env/secrets.env";
            };
          };

          # --- Caddy reverse proxy: one hostname per service ---
          # Naming follows the pi's convention: <service>.home.arpa (RFC 8375),
          # with AdGuard rewrites on the pi (192.168.0.105) resolving them to
          # this host. nip.io aliases answer the same vhosts for clients not
          # using the pi for DNS:
          #   homeassistant.home.arpa -> Home Assistant
          #   litellm.home.arpa       -> LiteLLM
          #   mcp.home.arpa           -> MCPHub
          #   lens.home.arpa          -> LiteLLM Lens
          #   hermes.home.arpa        -> Hermes agent (Ubuntu Incus container)
          #   booklore.home.arpa      -> Grimmory/Booklore library (Incus container)
          #   board.home.arpa         -> this host's own board (127.0.0.1:8765)
          #   search.home.arpa        -> SearXNG (127.0.0.1:8888)
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
          services.nginx.enable = false;
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
                litellm = {
                  host = "10.110.0.20";
                  port = 4000;
                };
                mcp = {
                  host = "10.110.0.30";
                  port = 3000;
                };
                lens = {
                  host = "10.110.0.40";
                  port = 4318;
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
              };
              site = name: upstream: {
                serverAliases = [ "http://${name}.${nip}" ];
                extraConfig = ''
                  encode gzip
                  reverse_proxy ${upstream}
                '';
              };
            in
            {
              enable = true;
              globalConfig = ''
                auto_https disable_redirects
              '';
              httpsPort = null;
              virtualHosts =
                (lib.mapAttrs' (
                  name: cfg:
                  lib.nameValuePair "http://${name}.${domain}" (site name "http://${cfg.host}:${toString cfg.port}")
                ) proxyHosts)
                // {
                  # Homepage dashboard (services.homepage-dashboard).
                  "http://homelab.${domain}" = site "homelab" "http://127.0.0.1:8082";
                  # This host's board. The port stays closed; Caddy is the door.
                  "http://board.${domain}" = site "board" "http://127.0.0.1:8765";
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

          # --- SearXNG (native, loopback; Caddy is the LAN door) ---
          # pkgs.searxng via services.searx. Not an Incus container: the
          # upstream image is unnecessary when nixpkgs already ships the
          # service, and a container would add another image pull on a laptop.
          # Port 8888 stays closed. secret_key is generated once on the host
          # and substituted from the env file; it never enters the flake.
          # First switch prints nothing secret — the file is mode 0600 under
          # /var/lib/searx. A later switch does not rotate it.
          systemd.services.searx-secret = {
            description = "Seed SearXNG secret key";
            before = [ "searx-init.service" ];
            requiredBy = [ "searx-init.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [
              pkgs.coreutils
              pkgs.openssl
            ];
            script = ''
              set -euo pipefail
              install -d -m 700 /var/lib/searx
              secrets=/var/lib/searx/secret.env
              if [ ! -s "$secrets" ]; then
                umask 077
                printf 'SEARX_SECRET_KEY=%s\n' "$(openssl rand -hex 32)" > "$secrets"
              fi
              chmod 0600 "$secrets"
            '';
          };
          services.searx = {
            enable = true;
            environmentFile = "/var/lib/searx/secret.env";
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

          # The page and probe live in ~surya/homelab-board and run as a user
          # service. Caddy above is the only LAN door, so 8765 stays closed.
          # The probe reads this host directly and reaches the Pi with
          # ~/.ssh/homelab-board, whose public half is on #raspberry-pi.
          users.users.surya.linger = true;
          systemd.user.services.homelab-board = {
            description = "Homelab board";
            wantedBy = [ "default.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              WorkingDirectory = "%h/homelab-board";
              ExecStart = "${pkgs.nodejs}/bin/node %h/homelab-board/server.mjs";
              Restart = "on-failure";
              RestartSec = 3;
            };
            environment = {
              PORT = "8765";
              BIND = "127.0.0.1";
              LOCAL_HOMELAB = "1";
              PI_IDENTITY = "%h/.ssh/homelab-board";
            };
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
              exists=no
              if incus list --format csv -c n | grep -qx openbot; then
                exists=yes
              fi

              if [ "$exists" = no ]; then
                incus launch images:ubuntu/24.04 openbot \
                  -c boot.autostart=true \
                  -c limits.memory=2GiB \
                  -c limits.cpu=1
                # Wait for container network + apt to be ready.
                sleep 15
                incus exec openbot -- cloud-init status --wait >/dev/null 2>&1 || true
                incus exec openbot -- bash -c \
                  'curl -fsSL https://raw.githubusercontent.com/nightly-labs/openbot/main/scripts/install-server.sh | sudo bash -s -- --user openbot'
              fi

              # Reconcile caps and address on containers that predate
              # them; launch sets config only at creation (hermes
              # pattern). Memory raises apply live; the static address
              # lands on the container's next DHCP renew or reboot.
              if [ "$(incus config get openbot limits.memory)" != "2GiB" ]; then
                incus config set openbot limits.memory=2GiB
              fi
              if [ "$(incus config get openbot limits.cpu)" != "1" ]; then
                incus config set openbot limits.cpu=1
              fi
              # Static bridge address like the other instances (DHCP
              # .241 drifts). `device set` fails while eth0 exists only
              # in the profile, hence the override fallback (HAOS
              # pattern).
              incus config device set openbot eth0 ipv4.address=10.110.0.70 ||
                incus config device override openbot eth0 ipv4.address=10.110.0.70
            '';
          };

          # Installed with NixOS 26.05; do not change.
          system.stateVersion = "26.05";
        }
      )
    ];
  };
}
