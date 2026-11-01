# Restic backups onto the pi's spinning disk.
#
# Topology (chosen so no SSH key has to be copied between machines):
#   pi        runs `services.restic.server` (rest-server): data under
#             /mnt/media/backups/restic, `privateRepos = true` so each client
#             writes only its own subdirectory.
#   homelab   pushes /etc, /home, /var/lib to rest:http://<pi>:8000/homelab/
#   desktop   pushes the same to            rest:http://<pi>:8000/nixos/
#
# The repo name is `config.networking.hostName`, so each host's wiring is one
# line in its host file and there is no name to keep in sync by hand.
#
# Why rest-server and not SFTP: SFTP needs a `backup` user on the pi plus an
# authorized key planted on two clients, and root's key on the desktop lives in
# the 1Password agent (so a non-interactive unit would need a second on-disk key
# anyway). rest-server needs one htpasswd file and speaks plain HTTP on the LAN.
#
# Secrets stay out of the flake, as everywhere in this repo. They are Clan vars
# now (modules/clan/secrets.nix), decrypted to /run/secrets before sysinit:
#   pi      restic-htpasswd/htpasswd      bcrypt basic-auth users; installed to
#                                         /var/lib/restic-rest/htpasswd, which is
#                                         what rest-server reads
#   pi      restic-htpasswd/clients-env   same passwords, root-only, for
#                                         installing on the clients
#   client  restic-client/env             RESTIC_PASSWORD +
#                                         RESTIC_REST_<HOST>_USERNAME/PASSWORD
#
# Both restic-client and the pi's restic-htpasswd are *adopted*, never
# generated: a freshly minted password would not match the opposite side and
# every push would fail 401 with an unrecoverable repo.
{ lib, ... }:
{
  options.flake.modules.nixos.resticServer = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        # Clan vars replace the old first-boot seeder. `htpasswd` is what
        # rest-server reads; `clients-env` is the operator's plaintext copy for
        # provisioning a client. Both are 0400 under /run/secrets, so the
        # File= drop-in below copies them to the paths rest-server and the
        # operator already expect rather than rewriting those paths.
        vars = config.clan.core.vars.generators.restic-htpasswd;
        htpasswdVar = vars.files.htpasswd.path;
        clientsEnvVar = vars.files.clients-env.path;
        # ── Migration bridge (plans/clan-deploy-rs-migration.md §6.3) ──────
        # The htpasswd and the operator's client list now come from the
        # `restic-htpasswd` Clan var. This unit installs the decrypted var at the
        # path rest-server already reads, which is also what makes the migration
        # reversible: the legacy file is never overwritten in place, so restoring
        # it is a `cp` away (see .legacy-htpasswd below).
        #
        # The copy stays because rest-server runs with PrivateUsers=true: a
        # root-owned file under /run/secrets appears as `nobody` inside that user
        # namespace, so the file must live in a restic-owned directory.
        # ReadOnlyPaths keeps it read-only to the server either way.
        seedAuth = pkgs.writeShellApplication {
          name = "restic-rest-seed-auth";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            set -eu
            dir=/var/lib/restic-rest
            conf=$dir/htpasswd
            clients=$dir/clients.env

            install -d -m 0700 -o restic -g restic "$dir"

            if [ -s ${htpasswdVar} ]; then
              # Preserve the pre-Clan file once, before the first overwrite.
              # `conf` is the path rest-server reads, so leaving it alone is not
              # an option here; the preserved copy is the rollback path.
              if [ -s "$conf" ] && [ ! -e "$dir/.legacy-htpasswd" ]; then
                cp -p "$conf" "$dir/.legacy-htpasswd"
                chmod 0400 "$dir/.legacy-htpasswd"
                : > "$dir/.migrated-to-clan"
              fi
              install -m 0600 -o restic -g restic ${htpasswdVar} "$conf"
            elif [ ! -s "$conf" ]; then
              echo "restic-htpasswd did not decrypt and no legacy htpasswd exists" >&2
              exit 1
            fi

            if [ -s ${clientsEnvVar} ]; then
              install -m 0600 -o root -g root ${clientsEnvVar} "$clients"
            fi

            chown restic:restic "$dir"
            chmod 0700 "$dir"
          '';
        };
      in
      {
        services.restic.server = {
          enable = true;
          # rest-server uses systemd socket activation: a bare port, not an
          # address. The module asserts on the format.
          listenAddress = "8000";
          dataDir = "/mnt/media/backups/restic";
          privateRepos = true;
          htpasswd-file = "/var/lib/restic-rest/htpasswd";
          prometheus = false;
        };

        # dataDir is NOT listed here: on the pi it lives on the external media
        # disk, and a `d` rule would create it on the SD card when that disk is
        # absent, giving rest-server an empty repo on the wrong filesystem. The
        # host creates it after the mount instead. (Upstream's privateRepos `f`
        # rule for dataDir/.htpasswd stays: `f` does not create parents, so it
        # only errors when the disk is missing.) Auth state is host-local.
        systemd.tmpfiles.rules = [
          "d /var/lib/restic-rest 0700 restic restic -"
        ];

        # Upstream sets `home = dataDir` with createHome, which would create
        # the repo directory at user-setup time, before the media mount. Keep
        # the account's home on the root filesystem so `dataDir` is only ever
        # created by the host, after the mount. mkForce because upstream sets
        # this option unconditionally.
        users.users.restic.home = lib.mkForce "/var/lib/restic-rest";

        # rest-server reads the htpasswd through ReadOnlyPaths, so the file has
        # to be on disk before it starts rather than rest-server failing its
        # own path assertion on a fresh machine.
        systemd.services.restic-rest-seed-auth = {
          description = "Install the restic rest-server htpasswd from Clan vars";
          wantedBy = [ "multi-user.target" ];
          before = [ "restic-rest-server.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${seedAuth}/bin/restic-rest-seed-auth";
          };
        };

        # The server is socket-activated, so a connection can start it outside
        # the boot transaction, where the `before` above would not have ordered
        # it against the seeder. Require the seeder explicitly: without the
        # htpasswd rest-server exits instead of serving.
        systemd.services.restic-rest-server = {
          requires = [
            "restic-rest-seed-auth.service"
          ];
          after = [
            "restic-rest-seed-auth.service"
          ];
        };

        networking.firewall.allowedTCPPorts = [ 8000 ];
      };
  };

  options.flake.modules.nixos.backups = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, config, ... }:
      let
        name = "default";
        # The repository password and REST credentials. `restic-client` is a
        # per-machine Clan var, adopted from the pi's clients.env — it cannot be
        # generated, because a fresh password would not match the htpasswd on
        # the backup target and every push would fail with 401.
        envFile = config.clan.core.vars.generators.restic-client.files.env.path;

        # Writes a small JSON status document on every run — including the
        # ExecCondition skip — so homelab_stats can report "last backup 3h ago,
        # ok" without anyone reading journalctl. ExecStopPost runs after a
        # skip, which is exactly where services.restic.backups puts
        # backupCleanupCommand.
        statusWriter = pkgs.writeShellApplication {
          name = "restic-status";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
          ];
          text = ''
            set -u
            host="''${1:?host name}"
            dir=/var/lib/backup-status
            install -d -m 0755 "$dir"
            ok=false
            [ "''${SERVICE_RESULT:-}" = success ] && ok=true
            jq -n -c \
              --arg name "$host" \
              --arg result "''${SERVICE_RESULT:-unknown}" \
              --arg code "''${EXIT_CODE:-unknown}" \
              --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              --argjson ok "$ok" \
              '{name: $name, ok: $ok, result: $result, exitCode: $code, at: $at}' \
              > "$dir/$host.json.tmp"
            mv "$dir/$host.json.tmp" "$dir/$host.json"
            chmod 0644 "$dir/$host.json"
          '';
        };

        # The status document is named after the host, not the backup set: every
        # machine has a set called `default`, and the fleet view has to tell them
        # apart.
        statusName = config.networking.hostName;
      in
      {
        # Config + app state only. Media libraries, the Incus storage pool,
        # container images and caches are excluded: either re-downloadable or
        # too large to send nightly. Container *definitions* still land under
        # /var/lib/incus, which is why /var/lib is included minus the pool.
        services.restic.backups.${name} = {
          repository = "rest:http://192.168.0.105:8000/${config.networking.hostName}/";
          environmentFile = envFile;
          initialize = true;
          paths = [
            "/etc"
            "/home"
            "/var/lib"
          ];
          exclude = [
            "/home/*/.cache"
            "/home/*/.local/share/Trash"
            "/home/*/.local/share/containers"
            "/var/lib/containers"
            "/var/lib/docker"
            "/var/lib/incus/storage"
            "/var/lib/incus/database"
            "/var/cache"
            "/var/tmp"
            # Package trees: reproducible from the flake.
            "/var/lib/flatpak"
            "/nix"
          ];
          extraBackupArgs = [
            # /mnt/windows on the desktop and /mnt/media on the pi are their
            # own filesystems; never drag them in through a parent path.
            "--one-file-system"
            "--tag"
            "auto"
          ];
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 4"
            "--keep-monthly 6"
          ];
          checkOpts = [
            "--read-data-subset=5%"
          ];
          timerConfig = {
            OnCalendar = "*-*-* 03:30:00";
            Persistent = true;
            RandomizedDelaySec = "20min";
          };
          backupCleanupCommand = "${statusWriter}/bin/restic-status ${statusName}";
        };

        # The var file only exists while /run/secrets is mounted, so the unit
        # waits for the decrypt pass. Without the file it would fail every night
        # with a restic usage error; ExecCondition skips instead and
        # ExecStopPost still runs, so the status file records the skip and the
        # dashboard says "not configured" rather than showing a stale success.
        systemd.services."restic-backups-${name}" = {
          serviceConfig.ExecCondition = "${pkgs.bash}/bin/bash -c 'test -r ${envFile}'";
        };

        # Migration bridge (§6.3): the old root-only env file is never read or
        # rewritten again; it stays as the rollback path. Point `environmentFile`
        # back at it to revert.
        systemd.services.restic-backups-env-migrated = {
          description = "Record that restic client credentials moved to Clan vars";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            if [ -s /var/lib/restic-backups/env ]; then
              : > /var/lib/restic-backups/.migrated-to-clan
            fi
          '';
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/restic-backups 0700 root root -"
          "d /var/lib/backup-status 0755 root root -"
        ];
      };
  };
}
