# Qdrant vector database in an Incus OCI container.
#
# Extracted from modules/hosts/nixos-homelab.nix (§7 item 8 of
# plans/clan-deploy-rs-migration.md). The body is verbatim; only the section
# banner moved into this header.
#
# Two units, both idempotent oneshots: one seeds the API key, the other
# provisions the container. The key is generated once into
# /var/lib/qdrant-secrets/api-key and never enters the flake.
#
# LIVE DATA — do not change these paths. The vector store lives on the host at
# /var/lib/incus/qdrant/storage and is bind-mounted into the container; the
# guest address is pinned at 10.110.0.102 so Bifrost and friends find it.
# Moving either would present an empty database and look like data loss.
{ lib, ... }:
{
  options.flake.modules.nixos.qdrant = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        # Clan vars, not /var/lib: the key is decrypted to /run/secrets by the
        # `setupSecrets` activation script before units start, so the units below
        # only need `requires` on `qdrant-secrets.service`. The path is a fresh
        # tmpfs file every boot, so a rotation takes effect on restart with
        # nothing stale left behind.
        apiKeyFile = config.clan.core.vars.generators.qdrant-api-key.files.api-key.path;
      in
      {
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
            apiKey=$(sed -n 's|^QDRANT_API_KEY=\(.*\)|\1|p' ${apiKeyFile})
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

        # ── Migration bridge (plans/clan-deploy-rs-migration.md §6.3) ──────
        # This unit used to mint the key into /var/lib/qdrant-secrets/api-key.
        # The value now lives in a Clan var, and the unit's only remaining job
        # is to leave the old file untouched and record that it did.
        #
        # The old file is the rollback path: reverting `apiKeyFile` above to
        # /var/lib/qdrant-secrets/api-key brings the previous key back with no
        # re-provisioning. Delete this unit (and the file) one release later,
        # once a reboot has been observed with the vars path in place.
        #
        # It is a no-op by construction: no openssl, no write, no mkdir.
        systemd.services.qdrant-secrets = {
          description = "Record that the Qdrant API key moved to Clan vars";
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          path = [ pkgs.coreutils ];
          script = ''
            set -euo pipefail
            dir=/var/lib/qdrant-secrets
            if [ -s "$dir/api-key" ] && [ ! -e "$dir/.migrated-to-clan" ]; then
              : > "$dir/.migrated-to-clan"
            fi
          '';
        };
      };
  };
}
