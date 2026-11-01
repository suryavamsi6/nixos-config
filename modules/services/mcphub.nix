# MCPHub gateway, in an Incus OCI container.
#
# Extracted from modules/hosts/nixos-homelab.nix (§7 item 8.6 of
# plans/clan-deploy-rs-migration.md).
#
# Restored deliberately: Bifrost replaced MCPHub as the MCP gateway, but the
# container was never torn down and is the one this host actually runs.
# Declaring it again makes it survive a rebuild instead of being an orphan only
# Incus remembers. mcp.home.arpa fronts this container (10.110.0.30:3000);
# Bifrost keeps bifrost.home.arpa.
#
# The official image is Docker-only and not in nixpkgs. Users, settings and the
# credential key live on the host at /var/lib/incus/mcphub/data via the `data`
# disk device — that is live state, do not move it.
{ lib, ... }:
{
  options.flake.modules.nixos.mcphub = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
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
      };
  };
}
