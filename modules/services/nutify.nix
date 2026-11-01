# Nutify UPS monitoring in an Incus OCI container.
#
# Extracted verbatim from modules/hosts/nixos-homelab.nix (§7 step 9 of
# plans/clan-deploy-rs-migration.md).
#
# Remote NUT Only mode: Nutify runs no local driver and talks to a upsd
# elsewhere on the LAN. Nothing here opens the host USB bus, so it cannot fight
# apcupsd for the UPS the desktop (#nixos) already owns via gridwatch.
#
# The UPS target is configured in Nutify's own wizard at
# http://nutify.home.arpa (Caddy -> 10.110.0.103:5050). That writes /etc/nut
# inside the container volume, not on this host: add a NUT server (host, port
# 3493, ups name) that already exports the UPS and leave the local driver off.
#
# SECRET_KEY is generated once into /var/lib/nutify/secrets.env and never enters
# the flake; the unit seeds it, reads it back on every start and never rotates
# it. Instance data, logs and /etc/nut are bind-mounted out of /var/lib/nutify so
# recreating the container does not lose the wizard's work.
#
# The image's entrypoint starts upsd/upsmon unconditionally and validates
# /etc/nut before the web app, so the mount holds that directory. An empty (but
# existing) ups.conf is what the Remote-NUT-Only profile produces too.
{ lib, ... }:
{
  options.flake.modules.nixos.nutify = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        secretFile = config.clan.core.vars.generators.nutify-secret.files.secret-env.path;
      in
      {
        systemd.services.incus-nutify = {
          description = "Provision Nutify UPS monitoring Incus container";
          wantedBy = [ "multi-user.target" ];
          after = [
            "incus.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          requires = [
            "incus.service"
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
            state=/var/lib/nutify
            install -d -m 700 "$state"
            # Migration bridge (§6.3): the old SECRET_KEY file is left in place
            # untouched as the rollback path; the live value now comes from the
            # `nutify-secret` Clan var.
            if [ -s "$state/secrets.env" ]; then
              : > "$state/.migrated-to-clan"
            fi
            secret=$(sed -n 's|^SECRET_KEY=\(.*\)|\1|p' ${secretFile})
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
      };
  };
}
