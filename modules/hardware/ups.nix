# APC Back-UPS RS 1500G-IN connected over USB.
# PowerChute Serial Shutdown does not support Back-UPS models on Linux, so use
# apcupsd and read its shutdown policy from Serpantinum's validated settings.
{ lib, ... }:
{
  options.flake.modules.nixos.ups = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        settingsPath = "/home/surya/.config/serpantinum/settings.json";
        runtimeConfig = "/run/apcupsd/apcupsd.conf";

        apcupsdScripts = pkgs.runCommand "apcupsd-serpantinum-scripts" { } ''
          mkdir -p "$out"
          cp -r ${pkgs.apcupsd}/etc/apcupsd/. "$out/"
          chmod -R u+w "$out"
          rm -f "$out/apcupsd.conf" \
            "$out/changeme" "$out/commfailure" "$out/commok" \
            "$out/onbattery" "$out/offbattery"
          sed -i -e "s|^SCRIPTDIR=.*|SCRIPTDIR=$out|" "$out/apccontrol"
        '';

        generateRuntimeConfig = ''
          ${pkgs.python3}/bin/python3 ${./ups-policy.py} \
            --settings ${lib.escapeShellArg settingsPath} \
            --output ${lib.escapeShellArg runtimeConfig} \
            --script-dir ${apcupsdScripts}
        '';
      in
      {
        services.apcupsd.enable = true;

        systemd.services.apcupsd = {
          preStart = lib.mkForce generateRuntimeConfig;
          serviceConfig = {
            ExecStart = lib.mkForce "${pkgs.apcupsd}/bin/apcupsd -b -f ${runtimeConfig} -d1";
            RuntimeDirectoryPreserve = "yes";
          };
        };

        systemd.services.apcupsd-killpower.serviceConfig.ExecStart = lib.mkForce
          "${pkgs.apcupsd}/bin/apcupsd --killpower -f ${runtimeConfig}";

        systemd.services.apcupsd-policy-reload = {
          description = "Apply Serpantinum UPS shutdown settings";
          serviceConfig.Type = "oneshot";
          script = ''
            before="$(${pkgs.coreutils}/bin/cat /run/apcupsd/policy.json 2>/dev/null || true)"
            ${generateRuntimeConfig}
            after="$(${pkgs.coreutils}/bin/cat /run/apcupsd/policy.json)"
            if [[ "$before" != "$after" ]]; then
              ${pkgs.systemd}/bin/systemctl try-restart apcupsd.service
            fi
          '';
        };

        systemd.paths.apcupsd-policy = {
          description = "Watch Serpantinum UPS shutdown settings";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathChanged = settingsPath;
            Unit = "apcupsd-policy-reload.service";
          };
        };
      };
  };
}
