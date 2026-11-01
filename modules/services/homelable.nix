# Homelable canvas, in two Incus OCI containers.
#
# Extracted from modules/hosts/nixos-homelab.nix (§7 item 8.5 of
# plans/clan-deploy-rs-migration.md). Served by Caddy at map.home.arpa.
#
# LIVE DATA: both guests keep state in host directories that are bind-mounted
# in, and their bridge addresses are wired into Caddy and Gatus. Do not move the
# mounts or the addresses.
{ lib, ... }:
{
  options.flake.modules.nixos.homelable = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      {
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
      };
  };
}
