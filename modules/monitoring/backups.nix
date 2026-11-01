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
# Secrets stay out of the flake, as everywhere in this repo:
#   pi      /var/lib/restic-rest/htpasswd     basic-auth users (seeded once)
#   pi      /var/lib/restic-rest/clients.env  same passwords, root-only, for
#                                             installing on the clients
#   client  /var/lib/restic-backups/env       RESTIC_PASSWORD +
#                                             RESTIC_REST_USERNAME/PASSWORD
{ lib, ... }:
{
  options.flake.modules.nixos.resticServer = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        # Passwords are generated on first boot only. The plaintext copy in
        # clients.env exists so the operator can scp it to each client without
        # reading a password out of a shell history or the journal. Ownership
        # and modes are re-applied on every start, so an install created
        # before the fix below repairs itself instead of failing.
        seedAuth = pkgs.writeShellApplication {
          name = "restic-rest-seed-auth";
          runtimeInputs = [
            pkgs.apacheHttpd
            pkgs.openssl
            pkgs.coreutils
          ];
          text = ''
            set -eu
            dir=/var/lib/restic-rest
            conf=$dir/htpasswd
            clients=$dir/clients.env
            # rest-server runs as User=restic with PrivateUsers=true, so both
            # the directory and the htpasswd must be owned by restic; a
            # root-owned path is unreadable inside the service namespace.
            # clients.env is never read by the server and stays root-only.
            install -d -m 0700 -o restic -g restic "$dir"

            if [ ! -s "$conf" ]; then
              umask 077
              : > "$conf"
              : > "$clients"

              for user in nixos homelab; do
                # 24 base64 chars: no shell metacharacters, 144 bits.
                pw=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-24)
                # -B: bcrypt. rest-server accepts bcrypt, SHA-1 and plaintext;
                # bcrypt is the only one worth using.
                printf '%s:%s\n' "$user" "$(htpasswd -nB -b "$user" "$pw" | cut -d: -f2)" >> "$conf"
                printf 'RESTIC_REST_%s_USERNAME=%s\nRESTIC_REST_%s_PASSWORD=%s\n' \
                  "$(echo "$user" | tr '[:lower:]' '[:upper:]')" "$user" \
                  "$(echo "$user" | tr '[:lower:]' '[:upper:]')" "$pw" >> "$clients"
              done
            fi

            # Applied on every start, not only on creation: an install that
            # predates this layout has the file at 0600 root:root inside a
            # 0700 root-owned directory, which rest-server cannot read (it
            # fails with `permission denied` before serving).
            #
            # Owned by restic rather than merely group-readable because
            # PrivateUsers=true maps that account to root *inside* the
            # service's user namespace, where a host file owned by root
            # appears as `nobody`. ReadOnlyPaths in the NixOS unit keeps the
            # file read-only to the server either way.
            chown restic:restic "$dir"
            chmod 0700 "$dir"
            chown restic:restic "$conf"
            chmod 0600 "$conf"
            if [ -e "$clients" ]; then
              chown root:root "$clients"
              chmod 0600 "$clients"
            fi
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
          description = "Seed restic rest-server credentials on first boot";
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
          requires = [ "restic-rest-seed-auth.service" ];
          after = [ "restic-rest-seed-auth.service" ];
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
        envFile = "/var/lib/restic-backups/env";

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

        # Without the env file the unit would fail every night with a restic
        # usage error (no repository password). ExecCondition skips instead;
        # ExecStopPost still runs, so the status file records the skip and the
        # dashboard says "not configured" rather than showing a stale success.
        systemd.services."restic-backups-${name}".serviceConfig.ExecCondition =
          "${pkgs.bash}/bin/bash -c 'test -r ${envFile}'";

        systemd.tmpfiles.rules = [
          "d /var/lib/restic-backups 0700 root root -"
          "d /var/lib/backup-status 0755 root root -"
        ];
      };
  };
}
