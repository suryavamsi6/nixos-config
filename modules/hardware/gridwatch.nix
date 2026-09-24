# Gridwatch APC UPS manager — replaces the Serpantinum-driven apcupsd
# pipeline on this host. The Gridwatch agent owns the runtime apcupsd
# configuration (BATTERYLEVEL/MINUTES) with atomic apply + health verify +
# rollback, and every mutation is Polkit-authorized.
{ lib, ... }:
{
  options.flake.modules.nixos.gridwatch = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { inputs, pkgs, ... }:
      {
        imports = [ inputs.gridwatch.nixosModules.default ];
        services.gridwatch = {
          enable = true;
          package = inputs.gridwatch.packages.x86_64-linux.default;
          users = [ "surya" ];
          enableApcupsd = true;
          manageShutdownPolicy = true;
        };

        # Preserve the exact production apcupsd configuration that the
        # Serpantinum pipeline generated (5% battery / 1 minute on battery,
        # local-only NIS, apcupsd events file that the agent ingests).
        # Gridwatch's module embeds this as the apcupsd template, then the
        # agent re-renders only the BATTERYLEVEL/MINUTES it owns.
        services.apcupsd.configText = ''
          UPSNAME back-ups-rs-1500g-in
          UPSCABLE usb
          UPSTYPE usb
          DEVICE
          POLLTIME 30
          LOCKFILE /run/lock
          PWRFAILDIR /run/apcupsd
          NOLOGINDIR /run/apcupsd
          ONBATTERYDELAY 6
          BATTERYLEVEL 5
          MINUTES 1
          TIMEOUT 0
          NETSERVER on
          NISIP 127.0.0.1
          NISPORT 3551
          EVENTSFILE /var/log/apcupsd.events
          EVENTSFILEMAX 10
        '';

        # Seed the agent's persisted policy on first boot so the shutdown
        # behavior stays exactly as it was (5% / 1 min). Without this the
        # agent falls back to its stock 50% / 5 min defaults and would
        # silently change when the UPS runs on battery.
        systemd.services.gridwatch-agent.preStart = ''
            if [ ! -e /var/lib/gridwatch/policy.json ]; then
              ${lib.getExe' pkgs.coreutils "cat"} > /var/lib/gridwatch/policy.json <<'EOF'
          {"batteryLevel":5,"minutes":1,"energyRate":0.2,"rawRetentionHours":24,"minuteRetentionDays":90,"notifyOnBattery":true,"notifyCritical":true,"silentHoursStart":22,"silentHoursEnd":7,"selfTestCadenceDays":14,"shutdownAction":"shutdown"}
          EOF
              ${lib.getExe' pkgs.coreutils "chmod"} 0640 /var/lib/gridwatch/policy.json
            fi
        '';
      };
  };

  options.flake.modules.homeManager.gridwatch = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        inputs,
        pkgs,
        lib,
        ...
      }:
      {
        imports = [ inputs.gridwatch.homeManagerModules.default ];
        programs.gridwatch = {
          enable = true;
          package = inputs.gridwatch.packages.x86_64-linux.default;
        };

        # Keep the Gridwatch app available, but prevent its notification relay
        # from being pulled in by graphical-session.target. This is declarative,
        # so Home Manager does not recreate the wants symlink on each activation.
        systemd.user.services.gridwatch-notifier.Install.WantedBy = lib.mkForce [];
      };
  };
}
