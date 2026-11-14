# Rebuild allowlisted Incus OCI instances onto newer upstream images.
#
# The allowlist is the whole safety model: `scripts/incus-app-update.py`
# touches nothing that is not described here, and each entry's host disks,
# in-container mounts and health URLs are verified before and after a
# rebuild. MariaDB, Home Assistant, Hermes and OpenBot are deliberately
# absent; see `docs/homelab.md`.
{ lib, ... }:
let
  stateDir = "/var/lib/incus-auto-update";
  backupDir = "/var/lib/incus-auto-update/backups";

  disk = source: path: {
    inherit source path;
  };

  # Instances listed together in one unit are stopped, snapshotted and
  # rebuilt as a set, so a paired app never runs mismatched builds.
  units = [
    {
      name = "mcphub";
      instances = [
        {
          name = "mcphub";
          image = "docker:samanhappy/mcphub:latest";
          disks.data = disk "/var/lib/incus/mcphub/data" "/app/data";
          requires = [ "/app/data/mcp_settings.json" ];
          health = [ "http://10.110.0.30:3000/" ];
          versionCommand = [ "node" "-p" "require('/app/package.json').version" ];
        }
      ];
    }
    {
      name = "reactive-resume";
      instances = [
        {
          name = "reactive-resume";
          image = "ghcr:reactive-resume/reactive-resume:latest";
          disks.data = disk "/var/lib/reactive-resume/data" "/app/data";
          health = [ "http://10.110.0.80:3000/api/health" ];
        }
      ];
    }
    {
      # Grimmory (Booklore) application container only. `booklore-db` is
      # MariaDB and is never rebuilt by this timer.
      name = "booklore";
      instances = [
        {
          name = "booklore";
          image = "ghcr:grimmory-tools/grimmory:latest";
          disks = {
            data = disk "/var/lib/incus/booklore/data" "/app/data";
            books = disk "/var/lib/incus/booklore/books" "/books";
            bookdrop = disk "/var/lib/incus/booklore/bookdrop" "/bookdrop";
          };
          health = [ "http://10.110.0.61:6060/" ];
        }
      ];
    }
    {
      name = "qdrant";
      instances = [
        {
          name = "qdrant";
          image = "docker:qdrant/qdrant:latest";
          disks.storage = disk "/var/lib/incus/qdrant/storage" "/qdrant/storage";
          health = [ "http://10.110.0.102:6333/healthz" ];
        }
      ];
    }
    {
      # No host disk: Bifrost keeps its configuration in Postgres and its
      # settings in the instance config, both preserved by a rebuild.
      name = "bifrost";
      instances = [
        {
          name = "bifrost";
          image = "docker:maximhq/bifrost:latest";
          health = [ "http://10.110.0.100:8080/health" ];
        }
      ];
    }
    {
      # The repository publishes architecture-suffixed tags; there is no
      # plain `latest` on Docker Hub.
      name = "nutify";
      instances = [
        {
          name = "nutify";
          image = "docker:dartsteven/nutify:latest-amd64";
          disks = {
            instance = disk "/var/lib/nutify/instance" "/app/nutify/instance";
            logs = disk "/var/lib/nutify/logs" "/app/nutify/logs";
            nutconf = disk "/var/lib/nutify/etc-nut" "/etc/nut";
          };
          health = [ "http://10.110.0.103:5050/" ];
        }
      ];
    }
    {
      # Not an OCI instance: the OpenBot installer provisions an Ubuntu
      # guest, so the app updates itself in place. `openbot status`
      # reports "OpenBot <version> is ready to install." when a release
      # is newer than the installed one.
      name = "openbot";
      kind = "in-guest";
      instance = "openbot";
      checkCommand = [ "openbot" "status" ];
      skipUnless = "is ready to install";
      updateCommand = [ "openbot" "update" ];
      healthCommand = [ "systemctl" "is-active" "openbot" ];
    }
    {
      # Also an in-guest install (git checkout + venv), updated through
      # `hermes update`. `--check` is read-only and prints "Up to date"
      # when the stable channel has nothing newer.
      name = "hermes";
      kind = "in-guest";
      instance = "hermes";
      checkCommand = [ "sudo" "-iu" "hermes" "--" "hermes" "update" "--check" ];
      skipWhen = "Up to date";
      updateCommand = [ "sudo" "-iu" "hermes" "--" "hermes" "update" "--yes" ];
      health = [ "http://10.110.0.50:9119/" ];
    }
    {
      # Gated: the backend keeps its SQLite database inside the instance
      # root filesystem, so a rebuild would discard it. Run
      # `scripts/homelable-migrate-data.sh`, move the database onto a host
      # disk, and re-verify before creating the precondition file.
      name = "homelable";
      precondition = "${stateDir}/homelable-enabled";
      instances = [
        {
          name = "backend";
          image = "ghcr:pouzor/homelable-backend:latest";
          health = [ "http://10.110.0.90:8000/docs" ];
        }
        {
          name = "homelable-frontend";
          image = "ghcr:pouzor/homelable-frontend:latest";
          health = [ "http://10.110.0.91/" ];
        }
      ];
    }
  ];
in
{
  options.flake.modules.nixos.incusAutoUpdate = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, pkgs, ... }:
      let
        configFile = pkgs.writeText "incus-app-update.json" (
          builtins.toJSON {
            inherit stateDir backupDir;
            inherit units;
          }
        );
        runner = "${pkgs.python3}/bin/python3 ${../../scripts/incus-app-update.py} --config ${configFile}";
        # Incus shells out to `skopeo` for every OCI remote, and a
        # systemd unit only sees what is on its own PATH, not the system
        # profile. Incus must also match the daemon the host runs (this
        # host pins the LTS line), not the newest nixpkgs build.
        incusPath = [
          config.virtualisation.incus.package
          pkgs.skopeo
        ];
      in
      {
        systemd.services.incus-app-update = {
          description = "Rebuild allowlisted Incus OCI instances onto newer images";
          after = [
            "incus.service"
            "network-online.target"
          ];
          requires = [ "incus.service" ];
          wants = [ "network-online.target" ];
          path = incusPath;
          unitConfig.ConditionPathExists = "!${stateDir}/disabled";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = runner;
            TimeoutStartSec = "90min";
            UMask = "0077";
          };
        };

        # Manual, read-only check: reports what the timer would do.
        systemd.services.incus-app-update-dryrun = {
          description = "Report pending Incus OCI updates without changing anything";
          after = [
            "incus.service"
            "network-online.target"
          ];
          requires = [ "incus.service" ];
          path = incusPath;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${runner} --dry-run";
            TimeoutStartSec = "20min";
          };
        };

        systemd.timers.incus-app-update = {
          description = "Check for allowlisted Incus OCI updates weekly";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "Sun *-*-* 04:30:00";
            Persistent = true;
            RandomizedDelaySec = "20min";
          };
        };
      };
  };
}
