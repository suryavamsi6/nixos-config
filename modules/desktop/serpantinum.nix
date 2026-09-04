# Official Serpantinum NixOS/Home Manager integration with the world-clock extension.
{ lib, ... }:
{
  options.flake.modules.nixos.serpantinum = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { inputs, ... }:
      {
        imports = [ (import "${inputs.serpantinum}/nix/nixos-module.nix") ];
        programs.serpantinum.enable = true;
      };
  };

  options.flake.modules.homeManager.serpantinum = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { config, inputs, pkgs, ... }:
      let
        worldClockPopup = pkgs.writeText "WorldClockPopup.qml" (builtins.readFile ./serpantinum/world-clock/WorldClockPopup.qml);
        worldClockGlobe = pkgs.writeText "WorldClockGlobe.qml" (builtins.readFile ./serpantinum/world-clock/WorldClockGlobe.qml);
        worldClockButton = pkgs.writeText "WorldClockButton.qml" (builtins.readFile ./serpantinum/world-clock/WorldClockButton.qml);
        worldClockTexture = pkgs.writeText "earth-land.svg" (builtins.readFile ./serpantinum/world-clock/earth-land.svg);
        worldClockQmldir = pkgs.writeText "world-clock-qmldir" (builtins.readFile ./serpantinum/world-clock/qmldir);
        worldClockScript = pkgs.writeText "world_clock.py" (builtins.readFile ./serpantinum/world-clock/world_clock.py);
        patchWorldClock = pkgs.writeText "patch-serpantinum-world-clock.py" (builtins.readFile ./serpantinum/world-clock/patch-serpantinum.py);
        serpantinum = pkgs.callPackage "${inputs.serpantinum}/nix/package.nix" { };
        worldClockQt = serpantinum.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            mkdir -p $out/share/serpantinum/quickshell/worldclock
            mkdir -p $out/share/serpantinum/quickshell/bar/modules/worldclock
            mkdir -p $out/share/serpantinum/scripts
            cp ${worldClockPopup} $out/share/serpantinum/quickshell/worldclock/WorldClockPopup.qml
            cp ${worldClockGlobe} $out/share/serpantinum/quickshell/worldclock/WorldClockGlobe.qml
            cp ${worldClockQmldir} $out/share/serpantinum/quickshell/worldclock/qmldir
            cp ${worldClockTexture} $out/share/serpantinum/quickshell/worldclock/earth-land.svg
            cp ${worldClockButton} $out/share/serpantinum/quickshell/bar/modules/worldclock/WorldClockButton.qml
            cp ${worldClockScript} $out/share/serpantinum/scripts/world_clock.py
            substituteInPlace $out/share/serpantinum/scripts/world_clock.py --replace-fail __TZDATA_ZONE1970__ ${pkgs.tzdata}/share/zoneinfo/zone1970.tab
            chmod +x $out/share/serpantinum/scripts/world_clock.py
            ${pkgs.python3}/bin/python3 ${patchWorldClock} $out
            substituteInPlace $out/share/serpantinum/quickshell/bar/modules/system/BtWidget.qml \
              --replace-fail 'moduleActive && !isDesktop && sysLayout.implicitWidth > 0' \
                             'moduleActive && sysLayout.implicitWidth > 0' \
              --replace-fail 'showLayout && moduleActive && !isDesktop' \
                             'showLayout && moduleActive' \
              --replace-fail 'isDesktop ? 0 : implicitWidth' 'implicitWidth'
          '';
        });
        worldClockDefaults = {
          hour12 = null;
          showSeconds = false;
          globe = { idleRotation = true; };
          regions = [
            { label = "Local"; zone = "local"; }
            { label = "UTC"; zone = "UTC"; }
            { label = "New York"; zone = "America/New_York"; }
            { label = "London"; zone = "Europe/London"; }
            { label = "Tokyo"; zone = "Asia/Tokyo"; }
          ];
        };
        worldClockDefaultsJson = builtins.toJSON worldClockDefaults;
      in
      {
        imports = [
          (import "${inputs.serpantinum}/nix/hm-module.nix" {
            self = inputs.serpantinum;
          })
        ];
        programs.serpantinum.enable = true;
        programs.serpantinum.package = worldClockQt;
        programs.serpantinum.systemd.enable = true;
        programs.serpantinum.settings.launcher.terminalCommand = "ghostty -e";
        programs.serpantinum.settings.worldClock = worldClockDefaults;

        home.activation.serpantinumWorldClockDefaults = config.lib.dag.entryAfter [ "serpantinumSettings" ] ''
          settings_file="$HOME/.config/serpantinum/settings.json"
          if [ -f "$settings_file" ] && ! ${pkgs.jq}/bin/jq -e 'has("worldClock")' "$settings_file" >/dev/null 2>&1; then
            ${pkgs.jq}/bin/jq --argjson worldClock ${lib.escapeShellArg worldClockDefaultsJson} \
              '. + {worldClock: $worldClock}' "$settings_file" > "$settings_file.tmp"
            ${pkgs.jq}/bin/jq -e . "$settings_file.tmp" >/dev/null
            mv "$settings_file.tmp" "$settings_file"
          fi
        '';
      };
  };
}
