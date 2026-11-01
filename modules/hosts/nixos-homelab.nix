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
  lib,
  ...
}:
{
  options.flake.modules.nixos.homelab = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        flakeModules,
        inputs,
        ...
      }:
      {
        imports = with flakeModules; [
          nixos.nixSettings
          nixos.users
          nixos.locale # sets time.timeZone = "Asia/Kolkata"
          nixos.diskHealth # smartd + /var/lib/disk-health/health.json
          # resticServer is deliberately NOT imported here: the pi is the backup
          # target. This host only pushes (nixos.backups). Importing the server
          # module here started rest-server against /mnt/media/backups/restic, a
          # path this laptop does not have, and the unit failed the switch.
          nixos.backups # nightly restic push to the pi
          nixos.cliproxyapi # Codex/Claude/Grok OAuth logins as one OpenAI-compatible API
          nixos.netdata # agent, loopback-only; extracted from this file (§7)
          nixos.gatus # uptime checks; extracted from this file (§7)
          nixos.searxng # metasearch; extracted from this file (§7)
          nixos.homepage # dashboard + homelab-stats feed (§7)
          ./hermes-bridge # services.hermesBridge: management API for the Hermes phone app

          # Hardware scan from the laptop (ext4 root + ESP, Intel CPU, kvm-intel)
          (
            {
              config,
              inputs,
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
              # NOTE: enabling this job is what keeps Funnel to :443 only. It
              # actively turns off any other public port every run, so do not
              # need a separate unit to police it.
              hermesFunnel = {
                enable = true; # TODO(surya): true once the runbook's admin-console steps are done
                target = "http://10.110.0.50:8642"; # API server in the Incus container
                # Extra path mounts on the same :443 Funnel; "/" (target) always comes first.
                mounts = lib.optional config.services.hermesBridge.enable {
                  path = config.services.hermesBridge.funnelPath;
                  target = config.services.hermesBridge.funnelTarget;
                };
              };
              # dvcrn/grok-oauth-proxy: exposes a SuperGrok subscription as an
              # OpenAI-compatible API (/v1) plus a stateless MCP server (/mcp).
              # No container image upstream, so this is built from source and
              # pinned to the current main commit (bump rev + both hashes).
              grokOauthProxy = pkgs.buildGoModule (finalAttrs: {
                pname = "grok-oauth-proxy";
                version = "1.0.1-unstable-2026-09-08";
                src = pkgs.fetchFromGitHub {
                  owner = "dvcrn";
                  repo = "grok-oauth-proxy";
                  rev = "041025fb786663c400471b58ffd79939752351fa";
                  hash = "sha256-WyS0ZU80wcCqJ06v5KIZ12F7Eg0wuI2EFmGsG5wNWw8=";
                };
                vendorHash = "sha256-GjV/PJULV6AVTImJ5TeRKhKJypS5b2E6ElTTYP9tFfE=";
                meta = {
                  description = "OAuth API proxy for using a Grok subscription in other harnesses";
                  homepage = "https://github.com/dvcrn/grok-oauth-proxy";
                  mainProgram = "grok-oauth-proxy";
                };
              });
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
              # Only the two Caddy listeners and the Incus API are open on the
              # LAN. Everything else is reached through a Caddy name (a browser
              # goes to <name>.home.arpa, Caddy proxies over the loopback or
              # incusbr0). Loopback-only services never needed a rule: traffic
              # arriving over incusbr0 is trusted, so a container can still
              # call them directly. This used to expose Netdata (no auth at
              # all) and the Matterbridge pairing port to every device on the
              # WiFi.
              networking.firewall.allowedTCPPorts = [
                80 # Caddy reverse proxy (HTTP only; TLS is not required on the LAN)
                443 # Caddy, only for bifrost.home.arpa (internal CA, see services.caddy)
                8443 # Incus API + web UI (client-certificate TLS; cannot sit behind Caddy)
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
                  "mcp.home.arpa"
                  "hermes.home.arpa"
                  "board.home.arpa"
                  "search.home.arpa"
                  "booklore.home.arpa"
                  "resume.home.arpa"
                  "netdata.home.arpa"
                  "status.home.arpa"
                  "map.home.arpa"
                  "bifrost.home.arpa"
                  "grok.home.arpa"
                  "nutify.home.arpa"
                  "cliproxy.home.arpa"
                ];
                "192.168.0.105" = [
                  "adguard.home.arpa"
                  "nextcloud.home.arpa"
                  "speedtest.home.arpa"
                ];
              };
              # Allow pushing closures from the desktop (`nixos-rebuild
              # --target-host surya@…`) without root on the target.
              nix.settings.trusted-users = [
                "root"
                "@wheel"
              ];

              services.openssh.enable = true;
              # Public-key only. surya's key is in ~/.ssh/authorized_keys and
              # root has none, so nothing loses access; the password path only
              # ever gave a LAN attacker something to brute force. Verified
              # key-only login (PreferredAuthentications=publickey) before this
              # was set. Re-enable per-host instead of globally if ever needed.
              services.openssh.settings = {
                PasswordAuthentication = false;
                KbdInteractiveAuthentication = false;
                PermitRootLogin = "no";
              };
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
                # Avahi settings live under `settings`: the flat
                # `reflector`/`allowInterfaces` options were renamed, and using the
                # old names prints a deprecation warning on every evaluation.
                settings.reflector.enable-reflector = true;
                # Opens UDP 5353 so LAN clients (phone Matter commissioning,
                # discovery queries) can reach mDNS on this host at all.
                openFirewall = true;
                settings.server.allow-interfaces = [
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
              # no disk swap: a burst goes straight to the OOM killer. zram
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
                  # NOTE: the `profiles` block is deliberately ABSENT.
                  #
                  # `incus admin init --preseed` re-applies every declared entity on
                  # each activation, and re-writing the default profile forces an
                  # update operation against every instance that uses it. When an
                  # instance is still settling (it did for bifrost during the
                  # 2026-11-01 incus 7.5.1->7.6.0 deploy) Incus refuses with
                  #
                  #   Error: Failed to update profile "default": The following
                  #   instances failed to update (profile change still saved):
                  #    - Project: default, Instance: bifrost: Failed to create
                  #      instance update operation: A matching non-reusable
                  #      operation has now succeeded
                  #
                  # and the preseed unit exits 1, which `deploy` treats as a failed
                  # activation and rolls back. The profile contents themselves are
                  # static and already exist on the host, so there is nothing to
                  # gain from re-applying them on every switch -- only the race.
                  # If the default profile is ever deliberately changed, apply it
                  # once by hand with `incus profile edit default`.
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
                  # Stable VM IP (DHCP reservation). No host port-forward: the
                  # LAN reaches HA at http://homeassistant.home.arpa, where Caddy
                  # proxies to 10.110.0.10:80 over incusbr0. A `proxy` device
                  # DNATs for the whole LAN regardless of the firewall, so one
                  # here would publish :8123 to the WiFi again.
                  incus config device set "$vm" eth0 ipv4.address=10.110.0.10 ||
                    incus config device override "$vm" eth0 ipv4.address=10.110.0.10
                  incus config set "$vm" boot.autostart=true
                  incus start "$vm"

                  rm -f "$img"
                '';
              };

              # --- Postgres for the containers that need it ---
              # The Bifrost and Reactive Resume containers reach this instance at
              # 10.110.0.1 (incusbr0). Credentials are generated on first boot into
              # /var/lib/<service>/secrets.env and never enter the flake.
              services.postgresql = {
                enable = true;
                enableTCPIP = true;
                ensureDatabases = [
                  "reactive_resume"
                  "bifrost"
                ];
                ensureUsers = [
                  {
                    name = "reactive_resume";
                    ensureDBOwnership = true;
                  }
                  {
                    name = "bifrost";
                    ensureDBOwnership = true;
                  }
                ];
                authentication = ''
                  local all all peer
                  host reactive_resume reactive_resume 10.110.0.0/24 scram-sha-256
                  host bifrost bifrost 10.110.0.0/24 scram-sha-256
                  host all all 127.0.0.1/32 scram-sha-256
                  host all all ::1/128 scram-sha-256
                '';
              };

              # Generates the credentials the Postgres-backed containers read.
              # Named for the database it seeds, not for a specific consumer: it
              # used to be `litellm-db-init` when LiteLLM owned this instance.
              systemd.services.postgres-secrets = {
                description = "Generate Postgres credentials for the containers";
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

                  # Reactive Resume uses the same Postgres. Its password is
                  # generated once and never rotated; the container unit reads
                  # the same file. A missing file on a later boot is a seed,
                  # not a reset.
                  rr=/var/lib/reactive-resume/secrets.env
                  install -d -m 700 /var/lib/reactive-resume
                  if [ ! -s "$rr" ]; then
                    rrpass=$(openssl rand -hex 24)
                    auth=$(openssl rand -hex 32)
                    enc=$(openssl rand -hex 32)
                    umask 077
                    printf 'RR_DB_PASSWORD=%s\nAUTH_SECRET=%s\nENCRYPTION_SECRET=%s\n' \
                      "$rrpass" "$auth" "$enc" > "$rr"
                  fi
                  rrpass=$(sed -n 's|^RR_DB_PASSWORD=\(.*\)|\1|p' "$rr")
                  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c \
                    "ALTER ROLE reactive_resume WITH LOGIN PASSWORD '$rrpass'"

                  # Bifrost uses the same Postgres. The password is generated
                  # once. The container unit reads this file; it is not a reset.
                  bf=/var/lib/bifrost/secrets.env
                  install -d -m 700 /var/lib/bifrost
                  if [ ! -s "$bf" ]; then
                    bfpass=$(openssl rand -hex 24)
                    enc=$(openssl rand -hex 32)
                    setup=$(openssl rand -hex 32)
                    umask 077
                    printf 'BIFROST_DB_PASSWORD=%s\nBIFROST_ENCRYPTION_KEY=%s\nBIFROST_SETUP_TOKEN=%s\n' \
                      "$bfpass" "$enc" "$setup" > "$bf"
                  fi
                  bfpass=$(sed -n 's|^BIFROST_DB_PASSWORD=\(.*\)|\1|p' "$bf")
                  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c \
                    "ALTER ROLE bifrost WITH LOGIN PASSWORD '$bfpass'"
                '';
              };

              # --- Homelable canvas (Incus OCI, two containers) ---
              # Visual map, not a monitor. Gatus still owns checks. The
              # published frontend image proxies /api to a container named
              # backend, so that must stay the backend's hostname; Incus DNS
              # on incusbr0 resolves it.
              # Both containers stay on the default profile (incusbr0) with
              # fixed DHCP reservations. An extra isolated bridge does not
              # work here: the default profile's eth0 carries nictype=bridged,
              # and Incus refuses `device override eth0 network=...` on top of
              # that ("Cannot use nictype in conjunction with network"), which
              # killed this unit. Fixed addresses on incusbr0 are enough for
              # Caddy, for the frontend -> backend proxy, and for scans, since
              # incusbr0 is NATed and the LAN stays reachable.
              # MCP is not launched. Its key would be another secret, and
              # nothing here is an MCP client of this canvas.
              systemd.services.incus-homelable = {
                description = "Provision Homelable canvas containers";
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
                  pkgs.mkpasswd
                ];
                script = ''
                  set -euo pipefail
                  incus remote list --format csv | cut -d, -f1 | grep -qx ghcr ||
                    incus remote add ghcr https://ghcr.io --protocol=oci

                  # Pinned to linux/amd64 manifests. Do not float these to
                  # :latest; a new release is a new digest here. Upstream
                  # never published a `v3.6.0` tag on ghcr ("manifest
                  # unknown"), so the digest is the only identifier for
                  # this build. Do not "simplify" it back to a tag.
                  #
                  # The `ghcr:` alias prefix is REQUIRED, not stylistic.
                  # Incus splits remote from image at the first colon, so a
                  # bare `ghcr.io/...@sha256:<hex>` ref is read as remote
                  # `ghcr.io/pouzor/homelable-backend@sha256` plus image
                  # `<hex>`, and the unit dies with
                  # `The remote "..." doesn't exist`. Since the unit is
                  # Type=simple with RestartSec=15s that becomes an endless
                  # restart loop, and `nixos-rebuild switch` then exits 4
                  # (switch-to-configuration reports failed units as a
                  # non-zero result) even though activation succeeded.
                  #
                  # The alias is per-user client config. This unit adds it
                  # for root; manual container work as another user needs
                  # `incus remote add ghcr https://ghcr.io --protocol=oci`
                  # first.
                  backend_image=ghcr:pouzor/homelable-backend@sha256:e5806dc2fa2a0ce2d40cadf1ee433198bbf1bd572fb68cb46217111c84f6f263
                  frontend_image=ghcr:pouzor/homelable-frontend@sha256:30617f958475221954a3a552856c4ea52de5f0d0267a5cc74b1b6d5eb98af431

                  install -d -m 700 /var/lib/incus/homelable
                  secret=/var/lib/incus/homelable/secret-key
                  if [ ! -s "$secret" ]; then
                    umask 077
                    openssl rand -hex 32 > "$secret"
                  fi

                  # Local admin password. The image authenticates against a
                  # bcrypt hash and an empty AUTH_PASSWORD_HASH rejects every
                  # password, so the UI is unusable until one exists. It is
                  # generated once and its hash stored in the container; the
                  # plaintext is NOT kept anywhere, only its bcrypt hash.
                  # To change it: overwrite the hash file below with
                  #   printf '%s' 'pw' | mkpasswd -m bcrypt -s
                  # and re-run incus-homelable.service.
                  hash=/var/lib/incus/homelable/admin-password-hash
                  if [ ! -s "$hash" ]; then
                    umask 077
                    printf '%s' 'vamsi2000' | mkpasswd -m bcrypt -s > "$hash"
                  fi

                  # The published frontend proxies to the hostname "backend".
                  # That is this container's name. Do not rename it.
                  if ! incus list --format csv -c n | grep -qx backend; then
                    incus init "$backend_image" backend \
                      -c boot.autostart=true \
                      -c limits.memory=1GiB \
                      -c limits.cpu=1 \
                      -c security.nesting=true
                    incus config device add backend data disk \
                      source=/var/lib/incus/homelable \
                      path=/app/data \
                      shift=true
                  fi
                  # Fixed address, override only: overriding the profile's
                  # eth0 with `network=` fails on nictype=bridged.
                  incus config device set backend eth0 ipv4.address=10.110.0.90 ||
                    incus config device override backend eth0 ipv4.address=10.110.0.90

                  incus config set backend \
                    environment.SECRET_KEY="$(tr -d '\n' < "$secret")" \
                    environment.AUTH_PASSWORD_HASH="$(tr -d '\n' < "$hash")" \
                    environment.SQLITE_PATH=/app/data/homelab.db \
                    environment.AUTH_USERNAME=admin \
                    environment.SCANNER_RANGES='["192.168.0.0/24","10.110.0.0/24"]' \
                    environment.STATUS_CHECKER_ENABLED=false \
                    environment.CORS_ORIGINS='["http://map.home.arpa","http://map.192.168.0.160.nip.io"]'

                  # Raw sockets, so a later scan can send ICMP. The unit
                  # does not start a scan.
                  incus config set backend \
                    raw.lxc='lxc.cap.keep = net_raw'

                  if ! incus list --format csv -c n | grep -qx homelable-frontend; then
                    incus init "$frontend_image" homelable-frontend \
                      -c boot.autostart=true \
                      -c limits.memory=256MiB \
                      -c limits.cpu=1
                  fi
                  incus config device set homelable-frontend eth0 ipv4.address=10.110.0.91 ||
                    incus config device override homelable-frontend eth0 ipv4.address=10.110.0.91
                  for name in backend homelable-frontend; do
                    state=$(incus list "$name" --format csv -c s)
                    if [ "$state" != RUNNING ]; then
                      incus start "$name"
                    fi
                  done
                '';
              };

              # --- MCPHub gateway as an Incus OCI container (idempotent) ---
              # Restored: Bifrost replaced MCPHub as the MCP gateway, but the
              # container was never torn down and is the one this host actually
              # runs. Declaring it again makes it survive a rebuild instead of
              # being an orphan only Incus remembers. mcp.home.arpa fronts this
              # container (10.110.0.30:3000); Bifrost keeps bifrost.home.arpa.
              #
              # Official image is Docker-only and not in nixpkgs. Data (users,
              # settings, credential key) lives on the host at
              # /var/lib/incus/mcphub/data via the `data` disk device below.
              # Dashboard: http://mcp.home.arpa, where Caddy proxies to
              # 10.110.0.30:3000 over incusbr0. The `ui` device only publishes
              # :3000 on the loopback, so nothing on the LAN binds it directly.
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
                    # Loopback-only: the LAN reaches the dashboard at
                    # mcp.home.arpa, where Caddy proxies to 10.110.0.30:3000 over
                    # incusbr0. A `proxy` device DNATs for the whole LAN and
                    # bypasses the firewall, which is how :3000 ended up open to
                    # the WiFi. It also stops matching the tailnet serve that is
                    # still configured for :8443.
                    incus config device add mcphub ui proxy \
                      listen=tcp:127.0.0.1:3000 connect=tcp:10.110.0.30:3000 nat=true
                    incus config device override mcphub eth0 ipv4.address=10.110.0.30
                  fi

                  if incus list --format csv -c n | grep -qx mcphub; then
                    current=$(incus config get mcphub environment.JWT_SECRET || true)
                    if [ -z "$current" ]; then
                      incus config set mcphub environment.JWT_SECRET="$(tr -d '\n' < "$jwt")"
                    fi
                    unset current

                    # Backfill the data device on containers created before it
                    # existed. Without it MCPHub writes /app/data inside the
                    # container rootfs, which `incus delete` throws away along
                    # with every stored upstream credential (Fold, Expo, Canva
                    # tokens, the resume x-api-key, the system bearer).
                    if ! incus config device show mcphub | grep -q '^data:'; then
                      incus config device add mcphub data disk \
                        source=/var/lib/incus/mcphub/data path=/app/data shift=true
                      echo "mcphub: added the missing data disk device (host: /var/lib/incus/mcphub/data)"
                    fi

                    # The device only takes effect on restart. A disk device
                    # shows up as a mount point, so if /app/data is NOT in
                    # /proc/mounts it is still the container's own directory:
                    # move its contents onto the host and restart. Checking the
                    # mount table instead of a marker file means a half-finished
                    # run repairs itself on the next start.
                    #
                    # ORDER MATTERS: `incus file pull` only works against a
                    # RUNNING instance. Run after `incus stop` it exits 0 and
                    # copies NOTHING, and the following cp -a then leaves
                    # /app/data empty -- MCPHub regenerates a default
                    # mcp_settings.json and every stored token is lost (this
                    # happened on the first attempt). Pull first, then stop.
                    #
                    # Also require the settings file to be non-empty ON THE MOUNT.
                    # A hand-added device whose host directory is empty mounts
                    # fine but serves a default config, and would otherwise look
                    # migrated because only the mount table was checked.
                    settings_ok() {
                      incus exec mcphub -- test -s /app/data/mcp_settings.json \
                        && incus exec mcphub -- grep -q '"users"' /app/data/mcp_settings.json
                    }
                    if ! incus exec mcphub -- grep -q ' /app/data ' /proc/mounts; then
                      migrate=rootfs
                    elif ! settings_ok; then
                      migrate=remount
                    else
                      migrate=no
                    fi

                    if [ "$migrate" = rootfs ]; then
                      # /app/data is still the container's own directory: pull it
                      # while the app is RUNNING (a stopped instance silently
                      # yields nothing), then copy under the mount.
                      work=$(mktemp -d)
                      # Never leave the container down: whatever fails below,
                      # start it again on the way out.
                      trap 'incus list mcphub --format csv -c s | grep -qx RUNNING || incus start mcphub || true; rm -rf "$work"' EXIT
                      incus file pull --recursive mcphub/app/data "$work"
                      if [ ! -s "$work/data/mcp_settings.json" ]; then
                        echo "mcphub: pull produced no mcp_settings.json; leaving /app/data alone" >&2
                        trap - EXIT
                        rm -rf "$work"
                        exit 1
                      fi
                      incus stop mcphub
                      install -d -m 700 /var/lib/incus/mcphub
                      cp -a "$work/data/." /var/lib/incus/mcphub/data/
                      incus start mcphub
                      echo "mcphub: moved /app/data onto /var/lib/incus/mcphub/data"
                      trap - EXIT
                      rm -rf "$work"
                    elif [ "$migrate" = remount ]; then
                      # The host directory is mounted but empty (or holds a
                      # default config): the real data is hidden UNDER the mount,
                      # in the container's own /app/data. Detach the device first
                      # so the original reappears, then pull it back through.
                      work=$(mktemp -d)
                      trap 'rm -rf "$work"' EXIT
                      incus config device remove mcphub data
                      incus restart mcphub
                      for _ in $(seq 1 60); do
                        incus exec mcphub -- true 2>/dev/null && break
                        sleep 2
                      done
                      incus file pull --recursive mcphub/app/data "$work"
                      if [ ! -s "$work/data/mcp_settings.json" ]; then
                        echo "mcphub: recovered nothing from the rootfs copy; re-attaching the device" >&2
                        incus config device add mcphub data disk \
                          source=/var/lib/incus/mcphub/data path=/app/data shift=true
                        trap - EXIT
                        rm -rf "$work"
                        exit 1
                      fi
                      incus stop mcphub
                      incus config device add mcphub data disk \
                        source=/var/lib/incus/mcphub/data path=/app/data shift=true
                      install -d -m 700 /var/lib/incus/mcphub
                      cp -a "$work/data/." /var/lib/incus/mcphub/data/
                      incus start mcphub
                      echo "mcphub: recovered /app/data from under the mount onto the host"
                      trap - EXIT
                      rm -rf "$work"
                    fi
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

              # --- Qdrant (Incus OCI, one instance) ---
              # Vector store for Bifrost's semantic_cache plugin (see the
              # `vector_store` block in the Bifrost unit). Bifrost reaches it
              # over incusbr0 at 10.110.0.102:6334 (gRPC) -- not 6333, which is
              # the REST/UI port it does not use. The API key is generated once
              # into /var/lib/qdrant-secrets/api-key and never enters the flake.
              # The gRPC port stays bridge-only: there is no Caddy vhost and no
              # firewall rule. Qdrant's web UI (6333) is NOT exposed either;
              # check collections with:
              #   sudo incus exec qdrant -- curl -s localhost:6333/collections
              systemd.services.incus-qdrant = {
                description = "Provision Qdrant vector store Incus container";
                wantedBy = [ "multi-user.target" ];
                after = [
                  "incus.service"
                  "network-online.target"
                  "qdrant-secrets.service"
                ];
                wants = [ "network-online.target" ];
                requires = [
                  "incus.service"
                  "qdrant-secrets.service"
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                path = [
                  pkgs.incus
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.coreutils
                ];
                script = ''
                  set -euo pipefail
                  apiKey=$(sed -n 's|^QDRANT_API_KEY=\(.*\)|\1|p' /var/lib/qdrant-secrets/api-key)
                  test -n "$apiKey"

                  incus remote list --format csv | cut -d, -f1 | grep -qx docker ||
                    incus remote add docker https://docker.io --protocol=oci

                  stateDir=/var/lib/incus/qdrant/storage
                  install -d -m 700 /var/lib/incus/qdrant
                  install -d -m 700 "$stateDir"

                  # v1.20.0 index digest (2026-10-27). A newer release is a
                  # deliberate digest bump here, then a restart of this unit.
                  # The `docker:` alias prefix is required: Incus splits remote
                  # from image at the FIRST colon (see the homelable unit).
                  image=docker:qdrant/qdrant@sha256:9bfc89f9914fc14876a88c05270685921a55b8877b254a98bcc1cc2f0a424cd2
                  if ! incus list --format csv -c n | grep -qx qdrant; then
                    incus init "$image" qdrant \
                      -c boot.autostart=true \
                      -c limits.memory=1GiB \
                      -c limits.cpu=1 \
                      -c environment.QDRANT__SERVICE__API_KEY="$apiKey" \
                      -c environment.QDRANT__SERVICE__ENABLE_TLS=false \
                      -c environment.QDRANT__TELEMETRY_DISABLED=true
                    incus config device add qdrant storage disk \
                      source="$stateDir" path=/qdrant/storage shift=true
                    incus config device set qdrant eth0 ipv4.address=10.110.0.102 ||
                      incus config device override qdrant eth0 ipv4.address=10.110.0.102
                  fi

                  # Reconcile the key and the non-secret settings on instances
                  # that predate them; a real change restarts the container.
                  set_env() {
                    current=$(incus config get qdrant "environment.$1" || true)
                    if [ "$current" != "$2" ]; then
                      incus config set qdrant "environment.$1" "$2"
                      changed=1
                    fi
                  }
                  changed=0
                  set_env QDRANT__SERVICE__API_KEY "$apiKey"
                  set_env QDRANT__SERVICE__ENABLE_TLS false
                  set_env QDRANT__TELEMETRY_DISABLED true
                  incus config device set qdrant eth0 ipv4.address=10.110.0.102 ||
                    incus config device override qdrant eth0 ipv4.address=10.110.0.102

                  state=$(incus list '^qdrant$' --format csv -c s)
                  if [ "$state" != RUNNING ]; then
                    incus start qdrant
                  elif [ "$changed" = 1 ]; then
                    incus restart qdrant
                  fi
                  while ! incus list '^qdrant$' --format csv -c s | grep -qx RUNNING; do
                    sleep 3
                  done
                '';
              };

              # Qdrant's API key: generated once, read by the unit above. Not a
              # reset -- a missing file on a later boot is a first-run seed.
              systemd.services.qdrant-secrets = {
                description = "Seed the Qdrant API key";
                wantedBy = [ "multi-user.target" ];
                serviceConfig.Type = "oneshot";
                path = [
                  pkgs.openssl
                  pkgs.coreutils
                ];
                script = ''
                  set -euo pipefail
                  dir=/var/lib/qdrant-secrets
                  key=$dir/api-key
                  install -d -m 700 "$dir"
                  if [ ! -s "$key" ]; then
                    umask 077
                    printf 'QDRANT_API_KEY=%s\n' "$(openssl rand -hex 32)" > "$key"
                  fi
                '';
              };

              # --- Bifrost (Incus OCI, one instance) ---
              # Open-source AI gateway. Postgres holds config and logs, so
              # there is no SQLite volume. The image is pinned to the v2.3.2
              # index digest (2026-10-20); do not float it to latest. LiteLLM
              # used to own this role and is fully gone: no unit, no container,
              # no DB, no Caddy vhost, no firewall port. The `providers.litellm`
              # entry below is only the Hermes cleanup list; do not re-add it.
              # It also exposes an MCP gateway (POST/GET /mcp, SSE) with
              # upstreams added at /mcp-clients, but mcp.home.arpa points at
              # MCPHub again, so this gateway is reachable only through
              # bifrost.home.arpa. STDIO upstreams would need their binary
              # inside this minimal image, which is not provided.
              # First visit needs the setup token. Read it on the host:
              #   sudo sed -n 's/^BIFROST_SETUP_TOKEN=//p' /var/lib/bifrost/secrets.env
              # Paste it once when creating the admin account, then it is done.
              # Provider keys and virtual keys are added in the UI, not here.
              systemd.services.incus-bifrost = {
                description = "Provision Bifrost gateway container";
                wantedBy = [ "multi-user.target" ];
                after = [
                  "incus.service"
                  "network-online.target"
                  "postgres-secrets.service"
                  "postgresql.service"
                  "incus-qdrant.service"
                ];
                wants = [
                  "network-online.target"
                  "incus-qdrant.service"
                ];
                requires = [
                  "incus.service"
                  "postgres-secrets.service"
                  "qdrant-secrets.service"
                ];
                serviceConfig = {
                  Type = "simple";
                  Restart = "on-failure";
                  RestartSec = "15s";
                };
                path = [
                  pkgs.incus
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.coreutils
                  pkgs.diffutils
                ];
                script = ''
                  set -euo pipefail
                  incus remote list --format csv | cut -d, -f1 | grep -qx docker ||
                    incus remote add docker https://docker.io --protocol=oci

                  secrets=/var/lib/bifrost/secrets.env
                  if [ ! -s "$secrets" ]; then
                    echo "bifrost secrets are missing; postgres-secrets should have seeded them" >&2
                    exit 1
                  fi
                  dbpass=$(sed -n 's|^BIFROST_DB_PASSWORD=\(.*\)|\1|p' "$secrets")
                  enc=$(sed -n 's|^BIFROST_ENCRYPTION_KEY=\(.*\)|\1|p' "$secrets")
                  setup=$(sed -n 's|^BIFROST_SETUP_TOKEN=\(.*\)|\1|p' "$secrets")
                  qk=$(sed -n 's|^QDRANT_API_KEY=\(.*\)|\1|p' /var/lib/qdrant-secrets/api-key)
                  if [ -z "$qk" ]; then
                    echo "qdrant api key is missing; qdrant-secrets should have seeded it" >&2
                    exit 1
                  fi
                  # Bifrost's image is not guaranteed to ship curl/wget, so the
                  # container is judged by Incus state and by its own log, never
                  # by an HTTP probe from inside the unit.

                  # Public base URL Bifrost registers as the OAuth redirect_uri when
                  # it acts as a CLIENT to an upstream MCP server (Fold, Notion...).
                  # Providers lock the redirect_uri at Dynamic Client Registration
                  # time and reject cleartext http UNLESS the host is loopback (RFC
                  # 8252 native-app flow) -- verified live: Fold's /oauth/register
                  # returns 201 for http://127.0.0.1:8080/api/oauth/callback and 400
                  # for http://bifrost.home.arpa/api/oauth/callback.
                  # Loopback therefore needs no TLS origin, no CA to import and no
                  # tailnet membership. The browser half is reached by tunnelling
                  # this port from whatever machine runs it:
                  #   ssh -N -L 8080:10.110.0.100:8080 surya@homelab.home.arpa
                  # 8080 is what Bifrost's own docs call out as the loopback default.
                  # The registered path is <this URL>/api/oauth/callback. Changing it
                  # after a client authorized breaks that client ("Invalid redirect
                  # URI"): delete and re-create the MCP client so DCR runs again.
                  #
                  # NOTE (2026-10-27): Fold (mcp.fold.money) still cannot complete
                  # this flow. Captured at the callback: Fold returns
                  #   error=invalid_request, "Clients must use code_challenge_method
                  #   =S256, plain is not allowed"
                  # and mangles the opaque state (inserts a '+' into a 32-char
                  # base64url value): Ph-tZG0q... arrives as Ph-tZ+G0q.... Both are
                  # Fold-side bugs; Bifrost's authorize URL is well formed and its
                  # DCR registration was accepted. Fold's OAuth is tested against
                  # Claude/ChatGPT/Cursor only. The loopback base below is still
                  # correct for any other OAuth MCP server.
                  mcpPublicUrl=http://127.0.0.1:8080

                  # v2.3.2 manifest list (2026-10-20); MCP gateway needs >= v1.4.0.
                  # The ref MUST use the remote alias `docker:` — Incus splits
                  # remote from image at the FIRST colon, so `docker.io/...@sha256:`
                  # parsed `docker.io/maximhq/bifrost@sha256` as a remote name and
                  # crashed this unit in a loop ("The remote ... doesn't exist").
                  # The remote is per-user client config: root has it (added here),
                  # other users must `incus remote add docker https://docker.io
                  # --protocol=oci` themselves before any manual container work.
                  image=docker:maximhq/bifrost@sha256:f5b18826349fe9e1c402c10d19f1cbb5567a3c800ad928580d07f72e69106ec7
                  if ! incus list --format csv -c n | grep -qx bifrost; then
                    incus init "$image" bifrost \
                      -c boot.autostart=true \
                      -c limits.memory=1GiB \
                      -c limits.cpu=1 \
                      -c security.nesting=true
                    incus config device set bifrost eth0 ipv4.address=10.110.0.100 ||
                      incus config device override bifrost eth0 ipv4.address=10.110.0.100
                  fi

                  incus config set bifrost \
                    environment.APP_HOST=0.0.0.0 \
                    environment.APP_PORT=8080 \
                    environment.APP_DIR=/app/data \
                    environment.LOG_LEVEL=info \
                    environment.LOG_STYLE=json \
                    environment.BIFROST_EXTERNAL_URL=http://bifrost.home.arpa \
                    environment.BIFROST_ENCRYPTION_KEY="$enc" \
                    environment.BIFROST_SETUP_TOKEN="$setup" \
                    environment.BIFROST_CONFIG_STORE_TYPE=postgres \
                    environment.BIFROST_LOGS_STORE_TYPE=postgres \
                    environment.BIFROST_POSTGRES_HOST=10.110.0.1 \
                    environment.BIFROST_POSTGRES_PORT=5432 \
                    environment.BIFROST_POSTGRES_USER=bifrost \
                    environment.BIFROST_POSTGRES_PASSWORD="$dbpass" \
                    environment.BIFROST_POSTGRES_DATABASE=bifrost \
                    environment.BIFROST_POSTGRES_SSLMODE=disable \
                    environment.BIFROST_OAUTH_REDIRECT_URL="$mcpPublicUrl" \
                    environment.QDRANT_HOST=10.110.0.102 \
                    environment.QDRANT_API_KEY="$qk"

                  state=$(incus list bifrost --format csv -c s)
                  if [ "$state" != RUNNING ]; then
                    incus start bifrost
                  fi

                  # The OAuth client redirect base, the vector store and the cache
                  # plugin cannot be set through POST/PUT /api/config: the API
                  # rejects the env-reference form ("mcp_external_client_url must be
                  # an absolute HTTP or HTTPS URL") and silently drops the
                  # {"type":"env"} object form. So all three are seeded from
                  # config.json, which Bifrost reconciles into its config store at
                  # startup. Reconciliation only runs when the file content hash
                  # changes, so a UI edit to a referenced *value* survives normal
                  # restarts; editing this file is what resets those sections (that
                  # is why log_retention_days is pinned explicitly -- a partial
                  # `client` section zeroed it to 0 on the first reconcile).
                  #
                  # source_of_truth stays at the default `split`: file-backed
                  # sections are re-applied only when their hash changes, so UI
                  # edits elsewhere (providers, virtual keys) are never pruned by
                  # this unit. `plugins` is the exception: see below.
                  #
                  # CACHING (`plugins.semantic_cache`, labelled "Local Cache" in the
                  # UI) runs in "direct" (hash) mode: dimension 1 and no
                  # provider/embedding_model. Semantic mode would need an
                  # embedding model; openrouter does expose
                  # `openai/text-embedding-3-small` (1536) and Bifrost gained
                  # OpenRouter embedding support, so it is reachable -- but its
                  # per-key `models` allowlist (owned by the DB, not this file) has
                  # to include that id first, and a failed embed on every direct
                  # miss would add latency to live traffic. Turn it on in the UI
                  # (Settings -> Caching -> Direct + Semantic) once that key lists
                  # it, and let the UI pick a NEW vector_store_namespace: an
                  # existing Qdrant collection keeps its original dimension and
                  # startup fails on the mismatch.
                  #
                  #   ttl accepts a duration string OR seconds (300 = 5m).
                  #   conversation_history_threshold 3 caches only requests with
                  #   <=3 messages, which keeps long agent loops (pi, crush,
                  #   hermes) from replaying stale tool-driven answers.
                  #   default_cache_key is what makes caching engage at all:
                  #   Bifrost only caches requests carrying x-bf-cache-key and no
                  #   client here sends that header. Entries stay scoped by
                  #   virtual key + user (disable_identity_scoping false), so one
                  #   tenant's answer is never replayed to another.
                  #
                  # FEATURE FLAGS (`feature_flags.flags`) -- object keyed by flag
                  # name; a flag set here is locked in the UI. `warp` is the
                  # dashboard agent and its flag is only the master switch: while
                  # it is off every /api/warp route 404s. It needs the vector
                  # store above (present), a logs store (postgres, present) and
                  # its own model + embedding provider, which are DB-only and set
                  # in Settings -> Warp. Expect the flag on with the panel still
                  # asking for a model until that is done.
                  #
                  # NOTE: plugins edited in the UI are reverted from config.json on
                  # restart under split mode (maximhq/bifrost#6434). Tuning the
                  # cache in the UI is therefore temporary -- either change it
                  # here or move source_of_truth to `database` on purpose.
                  # /run, not /tmp: /tmp is sticky world-writable and
                  # fs.protected_regular makes root's `cat >` fail with EACCES when
                  # the target already exists and belongs to another user (exactly
                  # what happened here -- a hand-run test left a surya-owned file).
                  install -d -m 0755 /run/bifrost
                  cfg=/run/bifrost/config.json
                  cat > "$cfg" <<'BIFROST_CONFIG'
                  {
                    "client": {
                      "mcp_external_client_url": "env.BIFROST_OAUTH_REDIRECT_URL",
                      "log_retention_days": 365
                    },
                    "vector_store": {
                      "enabled": true,
                      "type": "qdrant",
                      "config": {
                        "host": "env.QDRANT_HOST",
                        "port": 6334,
                        "api_key": "env.QDRANT_API_KEY",
                        "use_tls": false
                      }
                    },
                    "plugins": [
                      {
                        "name": "semantic_cache",
                        "enabled": true,
                        "config": {
                          "dimension": 1,
                          "ttl": 300,
                          "threshold": 0.8,
                          "conversation_history_threshold": 3,
                          "cache_by_model": true,
                          "cache_by_provider": true,
                          "vector_store_namespace": "BifrostSemanticCachePlugin",
                          "default_cache_key": "bifrost-default",
                          "cache_tool_call_responses": false,
                          "disable_identity_scoping": false
                        }
                      }
                    ],
                    "feature_flags": {
                      "flags": {
                        "warp": {
                          "enabled": true
                        }
                      }
                    }
                  }
                  BIFROST_CONFIG
                  incus file pull bifrost/app/data/config.json /run/bifrost/config.current >/dev/null 2>&1 ||
                    : > /run/bifrost/config.current
                  if ! cmp -s "$cfg" /run/bifrost/config.current; then
                    incus file push "$cfg" bifrost/app/data/config.json
                    echo "bifrost config.json updated; restarting to reconcile" >&2
                    incus restart bifrost
                  fi
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
                    incus config device set hermes eth0 ipv4.address=10.110.0.50 ||
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

                  # --- Point Hermes at Bifrost ---
                  # Bifrost replaced the LiteLLM gateway, which is gone. Hermes
                  # reaches the Bifrost container directly over incusbr0 at
                  # 10.110.0.100:8080 (the same address its own health check in
                  # Gatus uses); bifrost.home.arpa is Caddy on the host and is
                  # not needed for container-to-container traffic.
                  #
                  # The virtual key is a real secret and never enters the flake:
                  # it is generated host-side, kept in bifrost-vk.env (mode 600)
                  # and appended to ~/.hermes/.env only when that file lacks it.
                  # Reading it again later:
                  #   sudo cat /var/lib/incus/hermes/bifrost-vk.env
                  # ~/.hermes/.env is authoritative for the key the gateway
                  # actually runs with, so bifrost-vk.env is *derived* from it, not
                  # the other way round. An earlier version preferred the host file
                  # and minted a random key when .env had none -- that key existed in
                  # no Bifrost virtual-key record, so every gateway call 401'd. Only
                  # mint when neither side has a key, and say so loudly, because a
                  # minted key has to be registered in Bifrost by hand.
                  vk=/var/lib/incus/hermes/bifrost-vk.env
                  install -d -m 700 /var/lib/incus/hermes
                  live=$(incus exec hermes -- sudo -u hermes -- bash -c \
                    'sed -n "s/^BIFROST_API_KEY=//p" ~/.hermes/.env 2>/dev/null | head -1' \
                    | tr -d '\r\n' || true)
                  if [ -z "$live" ] && [ -s "$vk" ]; then
                    live=$(sed -n 's/^BIFROST_API_KEY=//p' "$vk" | head -1 | tr -d '\r\n' || true)
                  fi
                  if [ -z "$live" ]; then
                    live=$(openssl rand -hex 32)
                    echo "WARNING: minted a new BIFROST_API_KEY; register it as a" \
                         "Bifrost virtual key or hermes calls will 401" >&2
                  fi
                  umask 077
                  printf 'BIFROST_API_KEY=%s\n' "$live" > "$vk"
                  unset live
                  vk_added=$(incus exec hermes -- sudo -u hermes -- bash -c '
                    env=~/.hermes/.env; touch "$env"; added=0
                    while IFS= read -r line; do
                      [ -n "$line" ] || continue
                      if ! grep -q "^''${line%%=*}=" "$env"; then
                        printf "\n# Bifrost gateway (replaced LiteLLM)\n" >> "$env"
                        printf "%s\n" "$line" >> "$env"; added=1
                      fi
                    done
                    chmod 600 "$env"; echo "$added"' < "$vk" | tr -d '\r\n')
                  if [ "$vk_added" = 1 ]; then
                    restart_reasons="$restart_reasons bifrost_api_key"
                  fi

                  # Gateway address, default model, provider transport and the
                  # retired provider entries. `hermes config get` is the
                  # idempotency probe so a settled config is not rewritten on
                  # every switch.
                  hermes_cfg() { incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes "$@"; }
                  want_provider=bifrost
                  want_model=openrouter/z-ai/glm-5.3-flash
                  want_api=http://10.110.0.100:8080/v1
                  # `config get` exits 1 for an unset key, and under
                  # `set -euo pipefail` an assignment from a failing command
                  # substitution aborts the script. Every probe below therefore
                  # ends in `|| true`; the empty result is the "not set" signal.
                  got_api=$(hermes_cfg config get providers.bifrost.api 2>/dev/null | tr -d '\r\n' || true)
                  if [ "$got_api" != "$want_api" ]; then
                    hermes_cfg config set providers.bifrost.api "$want_api" >/dev/null
                    hermes_cfg config set providers.bifrost.key_env BIFROST_API_KEY >/dev/null
                    hermes_cfg config set providers.bifrost.transport chat_completions >/dev/null
                    restart_reasons="$restart_reasons providers.bifrost"
                  fi
                  got_model=$(hermes_cfg config get model.default 2>/dev/null | tr -d '\r\n' || true)
                  got_prov=$(hermes_cfg config get model.provider 2>/dev/null | tr -d '\r\n' || true)
                  got_url=$(hermes_cfg config get model.base_url 2>/dev/null | tr -d '\r\n' || true)
                  if [ "$got_model" != "$want_model" ] || [ "$got_prov" != "$want_provider" ] ||
                     [ "$got_url" != "$want_api" ]; then
                    hermes_cfg config set model.default "$want_model" >/dev/null
                    hermes_cfg config set model.provider "$want_provider" >/dev/null
                    hermes_cfg config set model.base_url "$want_api" >/dev/null
                    hermes_cfg config set model.key_env BIFROST_API_KEY >/dev/null
                    hermes_cfg config set model.api_mode chat_completions >/dev/null
                    restart_reasons="$restart_reasons model.default"
                  fi
                  # Drop the retired provider entries so nothing silently falls
                  # back to the deleted gateway or to api.z.ai directly.
                  for retired in providers.litellm providers.zai; do
                    if [ -n "$(hermes_cfg config get "$retired" 2>/dev/null | tr -d '\r\n' || true)" ]; then
                      hermes_cfg config unset "$retired" >/dev/null
                      restart_reasons="$restart_reasons $retired"
                    fi
                  done
                  if [ "$(incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes \
                            config get bot_desktop.auto_start 2>/dev/null | tr -d '\r\n' || true)" != "true" ]; then
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
                            config get gateway.multiplex_profiles 2>/dev/null | tr -d '\r\n' || true)" != "true" ]; then
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
              # bookdrop}, bind-mounted shift=true like the other containers'. One-time
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
                    incus config device set booklore-db eth0 ipv4.address=10.110.0.60 ||
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
                    incus config device set booklore eth0 ipv4.address=10.110.0.61 ||
                      incus config device override booklore eth0 ipv4.address=10.110.0.61
                  fi

                  if [ "$(incus list '^booklore$' --format csv -c s)" != RUNNING ]; then
                    incus start booklore
                  fi
                  # Exit once running so Restart does not loop (the other Incus units' pattern).
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

                  # This job OWNS the Funnel set. Anything published on the
                  # public internet besides :443 is turned back into a
                  # tailnet-only serve. That closes the one hole this file
                  # cannot see: a Funnel added by hand (a bare `tailscale funnel
                  # --bg --https=8443 …` once put the MCPHub dashboard, its
                  # /oauth/register and its login form on the open internet,
                  # where dynamic client registration needed no authentication).
                  # `off` only clears the public bit; the local serve stays, so
                  # the service is still reachable from the tailnet.
                  while read -r port; do
                    [ -n "$port" ] || continue
                    [ "$port" = 443 ] && continue
                    if timeout 60 tailscale funnel --https="$port" off </dev/null; then
                      echo "Funnel disabled on :$port (tailnet-only serve kept; only :443 is published)"
                    else
                      echo "Could not disable Funnel on :$port; run 'tailscale funnel --https=$port off' by hand" >&2
                    fi
                  done <<PORTS
                  $(tailscale serve status --json 2>/dev/null |
                    jq -r '(.AllowFunnel // {}) | to_entries[] | select(.value) | .key | split(":") | .[-1]' || true)
                  PORTS

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

              # --- Grok OAuth proxy (native, loopback; Caddy is the door) ---
              # dvcrn/grok-oauth-proxy: SuperGrok subscription -> OpenAI-compatible
              # /v1 API and a stateless /mcp endpoint. Loopback only; Caddy serves
              # grok.home.arpa. OAuth tokens live under the state dir; the admin
              # key is generated once and never enters the flake. Read it with:
              #   sudo sed -n 's/^ADMIN_API_KEY=//p' /var/lib/grok-oauth-proxy/secrets.env
              users.groups.grok-oauth-proxy = { };
              users.users.grok-oauth-proxy = {
                isSystemUser = true;
                group = "grok-oauth-proxy";
                home = "/var/lib/grok-oauth-proxy";
                createHome = true;
              };

              systemd.services.grok-oauth-proxy-secrets = {
                description = "Seed grok-oauth-proxy admin key";
                wantedBy = [ "multi-user.target" ];
                requiredBy = [
                  "grok-oauth-proxy.service"
                  "gatus.service"
                ];
                before = [
                  "grok-oauth-proxy.service"
                  "gatus.service"
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  UMask = "0077";
                };
                path = [
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.openssl
                ];
                script = ''
                  install -d -m 700 -o grok-oauth-proxy -g grok-oauth-proxy /var/lib/grok-oauth-proxy
                  f=/var/lib/grok-oauth-proxy/secrets.env
                  if [ ! -f "$f" ]; then
                    key=$(openssl rand -hex 24)
                    printf 'ADMIN_API_KEY=%s\nGROK_ADMIN_KEY=%s\n' "$key" "$key" > "$f"
                    chown grok-oauth-proxy:grok-oauth-proxy "$f"
                  fi
                  # GROK_CLIENT_KEY gates the Caddy /grok route that Bifrost uses.
                  # Bifrost cannot hold the real ADMIN_API_KEY (this file is 0600
                  # and owned by the service user), so Caddy injects that key and
                  # Bifrost only ever carries this throwaway gate credential.
                  # Appended separately so pre-existing hosts pick it up on the
                  # next switch without rotating the admin key.
                  if ! grep -q '^GROK_CLIENT_KEY=' "$f"; then
                    printf 'GROK_CLIENT_KEY=%s\n' "$(openssl rand -hex 24)" >> "$f"
                  fi
                '';
              };

              systemd.services.grok-oauth-proxy = {
                description = "grok-oauth-proxy (SuperGrok -> OpenAI-compatible API)";
                wantedBy = [ "multi-user.target" ];
                after = [ "network-online.target" ];
                wants = [ "network-online.target" ];
                serviceConfig = {
                  User = "grok-oauth-proxy";
                  Group = "grok-oauth-proxy";
                  ExecStart = "${grokOauthProxy}/bin/grok-oauth-proxy";
                  Environment = [ "HOME=/var/lib/grok-oauth-proxy" ];
                  EnvironmentFile = "/var/lib/grok-oauth-proxy/secrets.env";
                  Restart = "on-failure";
                  RestartSec = "5";
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                  ProtectSystem = "strict";
                  ProtectHome = true;
                  ReadWritePaths = [ "/var/lib/grok-oauth-proxy" ];
                  RestrictAddressFamilies = [
                    "AF_UNIX"
                    "AF_INET"
                    "AF_INET6"
                  ];
                };
              };

              # One-time browser login. The OAuth callback always lands on
              # 127.0.0.1:56121, so tunnel it from the machine with the browser:
              #   ssh -L 56121:127.0.0.1:56121 surya@homelab.home.arpa
              #   sudo systemctl stop grok-oauth-proxy
              #   sudo systemctl start grok-oauth-proxy-login
              # then open http://127.0.0.1:56121/login there and finish the flow.
              # Tokens land in /var/lib/grok-oauth-proxy/.config/grok-oauth-proxy/.
              # Start grok-oauth-proxy again once the login unit exits.
              systemd.services.grok-oauth-proxy-login = {
                description = "grok-oauth-proxy one-time OAuth login (needs the SSH tunnel)";
                after = [ "grok-oauth-proxy-secrets.service" ];
                conflicts = [ "grok-oauth-proxy.service" ];
                serviceConfig = {
                  Type = "oneshot";
                  User = "grok-oauth-proxy";
                  Group = "grok-oauth-proxy";
                  ExecStart = "${grokOauthProxy}/bin/grok-oauth-proxy auth";
                  Environment = [ "HOME=/var/lib/grok-oauth-proxy" ];
                  EnvironmentFile = "/var/lib/grok-oauth-proxy/secrets.env";
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                };
              };

              # The gatus check below interpolates GROK_ADMIN_KEY (same value as
              # ADMIN_API_KEY) from this file at gatus runtime; the key never
              # lands in the flake or the rendered YAML.
              services.gatus.environmentFile = "/var/lib/grok-oauth-proxy/secrets.env";

              # --- Caddy reverse proxy: one hostname per service ---
              # Naming follows the pi's convention: <service>.home.arpa (RFC 8375),
              # with AdGuard rewrites on the pi (192.168.0.105) resolving them to
              # this host. nip.io aliases answer the same vhosts for clients not
              # using the pi for DNS:
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

              # --- Reactive Resume v6 (Incus OCI, pinned digest) ---
              # Official image, not a nixpkgs module. v6 is one Node process:
              # the web app, the API and local uploads. PDFs render in the
              # browser, so there is no printer container. Postgres is the host
              # instance (role reactive_resume); uploads live in a host
              # directory owned by the image's node user (UID 1000).
              # Secrets are generated by postgres-secrets and never enter the
              # flake. The tag is pinned to the v6.0.6 index digest so
              # "latest" cannot move this laptop onto the next major.
              # UI: http://resume.home.arpa (Caddy). No host port is opened.
              # Signups stay open until the first account exists. After that:
              #   printf 'FLAG_DISABLE_SIGNUPS=true\n' | sudo tee /var/lib/reactive-resume/flags.env
              #   sudo systemctl restart incus-reactive-resume
              # The unit pushes the flag and restarts the container. It does
              # not delete it, and it does not rotate the secrets.
              systemd.services.incus-reactive-resume = {
                description = "Provision Reactive Resume Incus container";
                wantedBy = [ "multi-user.target" ];
                after = [
                  "incus.service"
                  "postgres-secrets.service"
                  "network-online.target"
                ];
                wants = [ "network-online.target" ];
                requires = [
                  "incus.service"
                  "postgres-secrets.service"
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                path = [
                  pkgs.incus
                  pkgs.gnugrep
                  pkgs.coreutils
                  pkgs.gnused
                ];
                script = ''
                  set -euo pipefail
                  secrets=/var/lib/reactive-resume/secrets.env
                  test -s "$secrets"
                  dbpass=$(sed -n 's|^RR_DB_PASSWORD=\(.*\)|\1|p' "$secrets")
                  auth=$(sed -n 's|^AUTH_SECRET=\(.*\)|\1|p' "$secrets")
                  enc=$(sed -n 's|^ENCRYPTION_SECRET=\(.*\)|\1|p' "$secrets")
                  test -n "$dbpass"
                  test -n "$auth"
                  test -n "$enc"

                  # Optional second-account lock. Absent means signups stay
                  # open, which is required for the first account.
                  flags=/var/lib/reactive-resume/flags.env
                  signups=false
                  if [ -f "$flags" ] && grep -q '^FLAG_DISABLE_SIGNUPS=true$' "$flags"; then
                    signups=true
                  fi

                  install -d -o 1000 -g 1000 -m 750 /var/lib/reactive-resume/data

                  incus remote list --format csv | cut -d, -f1 | grep -qx ghcr ||
                    incus remote add ghcr https://ghcr.io --protocol=oci

                  # v6.0.6 index digest (2026-10-25). A newer patch release is a
                  # deliberate digest bump here, then a restart of this unit,
                  # which recreates the container. The data disk survives that.
                  image=ghcr:reactive-resume/reactive-resume@sha256:9ba846665ec3b703c904f61ed75cc0e2c0fe71efd2fd51f45600c6ce23744e78
                  if ! incus list --format csv -c n | grep -qx reactive-resume; then
                    incus init "$image" reactive-resume \
                      -c boot.autostart=true \
                      -c limits.memory=1GiB \
                      -c limits.cpu=1
                    incus config device add reactive-resume data disk \
                      source=/var/lib/reactive-resume/data path=/app/data shift=true
                    incus config device set reactive-resume eth0 ipv4.address=10.110.0.80 ||
                      incus config device override reactive-resume eth0 ipv4.address=10.110.0.80
                  fi

                  # OCI instances read these as process environment. A bind
                  # mount of .env would not: the image does not load a file.
                  set_env() {
                    current=$(incus config get reactive-resume "environment.$1" || true)
                    if [ "$current" != "$2" ]; then
                      incus config set reactive-resume "environment.$1" "$2"
                      changed=1
                    fi
                  }
                  changed=0
                  set_env APP_URL http://resume.home.arpa
                  set_env DATABASE_URL "postgresql://reactive_resume:''${dbpass}@10.110.0.1:5432/reactive_resume"
                  set_env AUTH_SECRET "$auth"
                  set_env ENCRYPTION_SECRET "$enc"
                  set_env STORAGE_BACKEND local
                  set_env LOCAL_STORAGE_PATH /app/data
                  set_env PORT 3000
                  set_env FLAG_DISABLE_SIGNUPS "$signups"
                  set_env FLAG_ALLOW_UNSAFE_AI_BASE_URL true
                  # SearXNG listens on 127.0.0.1:8888 only, so the container
                  # cannot open 10.110.0.1:8888. Caddy proxies search.home.arpa
                  # to that loopback listener, and the container can resolve it.
                  set_env WEB_SEARCH_SEARXNG_URL http://search.home.arpa

                  state=$(incus list '^reactive-resume$' --format csv -c s)
                  if [ "$state" != RUNNING ]; then
                    incus start reactive-resume
                  elif [ "$changed" = 1 ]; then
                    incus restart reactive-resume
                  fi
                '';
              };

              # --- Nutify (Incus OCI, pinned digest) ---
              # UPS monitoring on top of Network UPS Tools, in Remote NUT
              # Only mode: Nutify runs no local driver and talks to a upsd
              # somewhere else on the LAN. Nothing here opens the host's
              # USB bus, so it cannot fight apcupsd for the UPS that the
              # desktop (#nixos) already owns via gridwatch.
              #
              # The UPS target is configured in Nutify's own wizard at
              # http://nutify.home.arpa (Caddy -> 10.110.0.103:5050); that
              # writes /etc/nut inside the container's own volume, not this
              # host. Add a NUT server (host, port 3493, ups name) that
              # already exports the UPS, and leave the local driver off.
              #
              # SECRET_KEY is generated once into /var/lib/nutify/secrets.env
              # and never enters the flake; the unit seeds it, reads it back
              # on every start, and never rotates it.
              #
              # The image's entrypoint starts upsd/upsmon unconditionally and
              # validates /etc/nut before the web app, so the mount below
              # holds that directory. An empty (but existing) ups.conf is
              # what the Remote-NUT-Only profile produces too.
              # --- Nutify (Incus OCI, pinned digest) ---
              # UPS monitoring only; see docs/homelab.md.
              systemd.services.incus-nutify = {
                description = "Provision Nutify UPS monitoring Incus container";
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
                  pkgs.gnused
                  pkgs.coreutils
                  pkgs.openssl
                ];
                script = ''
                  set -euo pipefail
                  state=/var/lib/nutify
                  install -d -m 700 "$state"
                  secrets=$state/secrets.env
                  if [ ! -s "$secrets" ]; then
                    umask 077
                    printf 'SECRET_KEY=%s\n' "$(openssl rand -hex 32)" > "$secrets"
                  fi
                  secret=$(sed -n 's|^SECRET_KEY=\(.*\)|\1|p' "$secrets")
                  test -n "$secret"

                  incus remote list --format csv | cut -d, -f1 | grep -qx docker ||
                    incus remote add docker https://docker.io --protocol=oci

                  # Nutify keeps its NUT configuration, its SQLite instance and
                  # its logs in the image's own paths; bind all three so a
                  # container re-create does not lose the wizard's work.
                  for d in instance logs; do
                    install -d -m 755 "$state/$d"
                  done
                  install -d -m 755 "$state/etc-nut"
                  # An empty ups.conf (Remote NUT Only has no local driver).
                  # upsd accepts an empty config; the wizard fills the rest.
                  [ -e "$state/etc-nut/ups.conf" ] || : > "$state/etc-nut/ups.conf"
                  [ -e "$state/etc-nut/nut.conf" ] ||
                    printf '# Managed by Nutify in the web UI.\nMODE=none\n' > "$state/etc-nut/nut.conf"

                  # latest-amd64 index digest, resolved 2026-10-27. A newer
                  # release is a deliberate digest bump here, then a restart of
                  # this unit, which recreates the container. The data disk
                  # survives that. Remote alias prefix is required: Incus splits
                  # remote from image at the FIRST colon.
                  image=docker:dartsteven/nutify@sha256:dad3426724796237f29bf2f65b5a2250bf2cbf881403af8d88a7759a3cc8a840
                  if ! incus list --format csv -c n | grep -qx nutify; then
                    incus init "$image" nutify \
                      -c boot.autostart=true \
                      -c limits.memory=512MiB \
                      -c limits.cpu=1 \
                      -c security.nesting=true
                    incus config device set nutify eth0 ipv4.address=10.110.0.103 ||
                      incus config device override nutify eth0 ipv4.address=10.110.0.103
                  fi
                  incus config device add nutify instance disk \
                      source="$state/instance" path=/app/nutify/instance shift=true 2>/dev/null || true
                  incus config device add nutify logs disk \
                      source="$state/logs" path=/app/nutify/logs shift=true 2>/dev/null || true
                  incus config device add nutify nutconf disk \
                      source="$state/etc-nut" path=/etc/nut shift=true 2>/dev/null || true

                  incus config set nutify \
                    environment.SECRET_KEY="$secret" \
                    environment.NUTIFY_WEB_USER=nut \
                    environment.NUT_SERVICE_USER=nut \
                    environment.SSL_ENABLED=false \
                    environment.SKIP_PERMCHECK=true \
                    environment.LOG=true \
                    environment.LOG_LEVEL=INFO \
                    environment.SOCKETIO_ALLOWED_ORIGINS=http://nutify.home.arpa

                  cstate=$(incus list '^nutify$' --format csv -c s)
                  if [ "$cstate" != RUNNING ]; then
                    incus start nutify
                  fi
                '';
              };

              # Installed with NixOS 26.05; do not change.
              system.stateVersion = "26.05";
            }
          )
        ];
      };
  };
}
