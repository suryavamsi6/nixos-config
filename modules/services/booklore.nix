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
      { pkgs, ... }:
      {
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
      };
  };
}
