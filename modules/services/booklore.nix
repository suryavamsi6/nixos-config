# Grimmory (Booklore) library, in two Incus containers.
#
# Extracted from modules/hosts/nixos-homelab.nix (§7 item 8.4 of
# plans/clan-deploy-rs-migration.md). The pi's `booklore` podman container ran
# ghcr.io/grimmory-tools/grimmory (the Booklore-derived library server) and moved
# here in October 2026; the pi copy under /mnt/media/booklore is kept as a
# fallback.
#
# Two guests: booklore-db (MariaDB, 10.110.0.60) and booklore (the app,
# 10.110.0.61). The app reads its .env on every switch and maps those inputs to
# whatever the image expects.
#
# LIVE DATA — do not move these paths. Everything lives under
# /var/lib/incus/booklore/{db,data,books,bookdrop} and is bind-mounted into the
# guests; the two addresses are wired into Caddy, Gatus and the app's config.
# Moving any of them presents an empty library, which reads as data loss.
{ lib, ... }:
{
  options.flake.modules.nixos.booklore = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        vars = config.clan.core.vars.generators;
        dbPasswordFile = vars.booklore-db-password.files.db-password.path;
        mysqlRootPasswordFile = vars.booklore-mysql-root-password.files.mysql-root-password.path;
        # Container settings that are not secrets. They are the values the live
        # containers carry (read with `incus config show --expanded`), hoisted
        # here so the adopt-set below cannot overwrite them with defaults.
        booklorePort = "6060";
        dbName = "booklore";
        dbUser = "booklore";
      in
      {
        systemd.services.incus-booklore = {
          description = "Provision Grimmory library + MariaDB Incus containers";
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

            # ── Migration bridge (plans/clan-deploy-rs-migration.md §6.3) ──
            # The old `/var/lib/incus/booklore/booklore.env` held two unrelated
            # credentials plus container settings. They are now two Clan vars —
            # DB_PASSWORD and MYSQL_ROOT_PASSWORD are separate so rotating one
            # cannot silently break the other — and the settings below are
            # module-level constants, so nothing here reads that file any more.
            env=$state/booklore.env
            if [ -s "$env" ]; then
              chmod 600 "$env"
              : > "$state/.migrated-to-clan"
            fi
            TZ=Etc/UTC
            BOOKLORE_PORT=${booklorePort}
            MYSQL_DATABASE=${dbName}
            DB_USER=${dbUser}
            DATABASE_URL="jdbc:mariadb://10.110.0.60:3306/${dbName}"
            DB_PASSWORD=$(sed -n 's|^DB_PASSWORD=\(.*\)|\1|p' ${dbPasswordFile})
            MYSQL_ROOT_PASSWORD=$(sed -n 's|^MYSQL_ROOT_PASSWORD=\(.*\)|\1|p' ${mysqlRootPasswordFile})
            if [ -z "$DB_PASSWORD" ] || [ -z "$MYSQL_ROOT_PASSWORD" ]; then
              echo "booklore Clan vars did not decrypt; is /run/secrets mounted?" >&2
              exit 1
            fi

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
                -c environment.DATABASE_URL="$DATABASE_URL" \
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
      };
  };
}
