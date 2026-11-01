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
          nixos.grokOauthProxy # SuperGrok -> OpenAI-compatible API (§7)
          nixos.caddy # one home.arpa hostname per service, the LAN door (§7)
          nixos.openbot # OpenBot server in an Ubuntu Incus container (§7)
          nixos.reactiveResume # Reactive Resume v6 Incus OCI container (§7)
          nixos.nutify # Nutify UPS monitoring Incus OCI container (§7)
          nixos.qdrant # Qdrant vector DB Incus OCI container (§7)
          nixos.bifrost # Bifrost AI gateway Incus OCI container (§7)
          nixos.hermes # Hermes agent Incus container (§7)
          nixos.booklore # Grimmory/Booklore library + MariaDB Incus containers (§7)
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

              # The gatus check below interpolates GROK_ADMIN_KEY (same value as
              # ADMIN_API_KEY) from this file at gatus runtime; the key never
              # lands in the flake or the rendered YAML.
              services.gatus.environmentFile = "/var/lib/grok-oauth-proxy/secrets.env";

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

              # Installed with NixOS 26.05; do not change.
              system.stateVersion = "26.05";
            }
          )
        ];
      };
  };
}
