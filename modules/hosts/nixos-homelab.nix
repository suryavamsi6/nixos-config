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
          nixos.resticClientVars # the restic-client var that push reads (§6)
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
          nixos.homelable # Homelable canvas Incus OCI containers (§7)
          nixos.mcphub # MCPHub gateway Incus OCI container (§7)
          nixos.incusAutoUpdate # weekly rebuild of allowlisted OCI apps
          nixos.haos # Home Assistant OS Incus VM (§7)
          nixos.homelabVars # Clan vars: the generators for every secret below (§6)

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
              # The dashboard is public through Funnel and retains its own
              # password login. The job also limits public Funnel ports to 443.
              hermesFunnel = {
                enable = true;
                target = "http://10.110.0.50:9119";
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

              # --- Tailscale Funnel: authenticated Hermes dashboard ---
              # The reconciler configures the public URL and exact trusted
              # proxy IP, verifies that the dashboard reports auth enabled,
              # then publishes it. It removes the retired /bridge route and
              # retries transient failures every two minutes. See the runbook.
              systemd.services.hermes-funnel = lib.mkIf hermesFunnel.enable {
                description = "Tailscale Funnel for the Hermes dashboard";
                after = [
                  "tailscaled.service"
                  "incus-hermes.service"
                  "network-online.target"
                ];
                wants = [
                  "tailscaled.service"
                  "network-online.target"
                ];
                requires = [ "incus-hermes.service" ];
                wantedBy = [ "multi-user.target" ];
                path = [
                  config.services.tailscale.package
                  pkgs.incus
                  pkgs.curl
                  pkgs.jq
                  pkgs.coreutils
                ];
                serviceConfig.Type = "oneshot";
                script = ''
                  set -o pipefail
                  state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "Unknown"' || true)
                  state=''${state:-unreachable}
                  if [ "$state" != Running ]; then
                    echo "tailscale is $state, not Running; run 'sudo tailscale up' (docs/hermes-funnel.md). Retrying in 2 min." >&2
                    exit 0
                  fi
                  # This job OWNS the Funnel set. Anything published on the
                  # public internet besides :443 is removed. That closes the one hole this file
                  # cannot see: a Funnel added by hand (a bare `tailscale funnel
                  # --bg --https=8443 …` once put the MCPHub dashboard, its
                  # /oauth/register and its login form on the open internet,
                  # where dynamic client registration needed no authentication).
                  # `off` removes the affected port's Funnel handlers. Do this
                  # even if the dashboard is temporarily unavailable.
                  while read -r port; do
                    [ -n "$port" ] || continue
                    [ "$port" = 443 ] && continue
                    if timeout 60 tailscale funnel --https="$port" off </dev/null; then
                      echo "Funnel disabled on :$port (only :443 is published)"
                    else
                      echo "Could not disable Funnel on :$port; run 'tailscale funnel --https=$port off' by hand" >&2
                    fi
                  done <<PORTS
                  $(tailscale serve status --json 2>/dev/null |
                    jq -r '(.AllowFunnel // {}) | to_entries[] | select(.value) | .key | split(":") | .[-1]' || true)
                  PORTS

                  # tailscaled persists old mounts across NixOS generations.
                  # Remove this path explicitly before switching the root.
                  status=$(tailscale serve status --json 2>/dev/null) || {
                    echo "Cannot read Funnel configuration; retrying." >&2; exit 0;
                  }
                  has_bridge=$(printf '%s' "$status" | jq -r '
                    [.Web // {} | to_entries[] | select(.key | endswith(":443")) | (.value.Handlers // {}) | has("/bridge")] | any
                  ') || {
                    echo "Invalid Tailscale Serve configuration; retrying." >&2; exit 0
                  }
                  if [ "$has_bridge" = true ]; then
                    if ! timeout 60 tailscale funnel --https=443 --set-path /bridge off </dev/null; then
                      echo "Could not remove the retired /bridge Funnel route; retrying." >&2
                      exit 0
                    fi
                  fi

                  dns=$(tailscale status --json | jq -r '.Self.DNSName // "" | rtrimstr(".")')
                  case "$dns" in
                    *.ts.net) ;;
                    *) echo "No Tailscale DNS name yet; retrying." >&2; exit 0 ;;
                  esac
                  public_url="https://$dns"
                  hermes_cfg() {
                    incus exec hermes -- sudo -u hermes -H /home/hermes/.local/bin/hermes "$@"
                  }
                  uid=$(incus exec hermes -- id -u hermes | tr -d '\r\n ') || exit 0
                  pending=/var/lib/incus/hermes/.dashboard-funnel-restart-pending

                  # .env overrides config.yaml in Hermes, including a value
                  # left there by dashboard register. Set the authoritative
                  # env value instead of silently leaving a stale URL in force.
                  current=$(hermes_cfg config get HERMES_DASHBOARD_PUBLIC_URL 2>/dev/null | tr -d '\r\n' || true)
                  if [ "$current" != "$public_url" ]; then
                    touch "$pending" || { echo "Cannot record dashboard restart; retrying." >&2; exit 0; }
                    hermes_cfg config set HERMES_DASHBOARD_PUBLIC_URL "$public_url" >/dev/null || {
                      echo "Could not configure the dashboard URL; retrying." >&2; exit 0;
                    }
                  fi
                  # Merge the host's incusbr0 address into any existing list.
                  # It is the peer that terminates TLS and sends X-Forwarded-*.
                  trusted=$(hermes_cfg config get dashboard.trusted_proxies --json 2>/dev/null) || {
                    echo "Could not read dashboard.trusted_proxies; retrying." >&2; exit 0;
                  }
                  merged=$(printf '%s' "$trusted" | jq -ce '
                    if type == "array" and all(.[]; type == "string")
                    then if index("10.110.0.1") then . else . + ["10.110.0.1"] end
                    else error("trusted_proxies is not a list of strings") end
                  ') || { echo "Invalid dashboard.trusted_proxies; retrying." >&2; exit 0; }
                  if ! printf '%s' "$trusted" | jq -e 'index("10.110.0.1") != null' >/dev/null; then
                    touch "$pending" || { echo "Cannot record dashboard restart; retrying." >&2; exit 0; }
                    hermes_cfg config set dashboard.trusted_proxies "$merged" >/dev/null || {
                      echo "Could not configure the trusted proxy; retrying." >&2; exit 0;
                    }
                  fi
                  if [ -e "$pending" ]; then
                    incus exec hermes -- sudo -u hermes -- \
                      env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user restart hermes-dashboard.service || {
                        echo "Could not restart the dashboard; retrying." >&2; exit 0;
                      }
                    rm -f "$pending"
                  fi
                  # Never publish a dashboard that isn't reporting its auth
                  # gate. The user unit may need another cycle to start.
                  if ! curl -fsS --max-time 5 ${hermesFunnel.target}/api/health | jq -e '.ok == true and .auth_required == true' >/dev/null; then
                    echo "Dashboard is not ready with authentication enabled; retrying." >&2
                    # A later loss of the auth gate must close an existing
                    # dashboard route too, without touching a different root.
                    if tailscale serve status --json | jq -e --arg t ${lib.escapeShellArg hermesFunnel.target} '
                      [.Web // {} | to_entries[] | select(.key | endswith(":443")) | .value.Handlers["/"].Proxy] | index($t) != null
                    ' >/dev/null; then
                      timeout 60 tailscale funnel --https=443 --set-path / off </dev/null ||
                        echo "Could not remove the dashboard Funnel route; retrying." >&2
                    fi
                    exit 0
                  fi
                  if tailscale funnel status --json | jq -e --arg t ${lib.escapeShellArg hermesFunnel.target} '
                    ([.Web // {} | to_entries[] | select(.key | endswith(":443")) | .value.Handlers["/"].Proxy] | index($t)) != null
                    and ([.AllowFunnel // {} | to_entries[] | select(.key | endswith(":443")) | .value] | any)
                  ' >/dev/null; then
                    echo "Funnel already serves the authenticated dashboard at $public_url"
                  elif timeout 60 tailscale funnel --bg --yes --https=443 --set-path / ${lib.escapeShellArg hermesFunnel.target} </dev/null; then
                    echo "Funnel enabled for the dashboard at $public_url"
                  else
                    echo "Funnel not enabled yet; check HTTPS and the funnel node attribute (docs/hermes-funnel.md)." >&2
                  fi

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

              # gatus reads GROK_ADMIN_KEY from the grok-oauth Clan var; the
              # wiring lives in modules/services/gatus.nix now (§6).

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
