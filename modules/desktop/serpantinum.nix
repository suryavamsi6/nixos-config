# Official Serpantinum NixOS/Home Manager integration.
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
      { inputs, pkgs, ... }:
      let
        quickshellBase = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
        # Current Quickshell already handles Hyprland 0.55 workspace addresses.
        quickshellUnwrapped = quickshellBase.unwrapped;
        quickshellPatched = quickshellBase.overrideAttrs (_: {
          installPhase = ''
            mkdir -p $out
            cp -r ${quickshellUnwrapped}/* $out
          '';
        });
        upsStatus = pkgs.writeShellApplication {
          name = "ups_status.sh";
          runtimeInputs = [
            pkgs.apcupsd
            pkgs.gawk
            pkgs.jq
          ];
          text = builtins.readFile ./serpantinum-ups/ups_status.sh;
        };
        btBattery = pkgs.writeShellApplication {
          name = "serpantinum-bt-battery";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.systemd
          ];
          text = builtins.readFile ./serpantinum-bluetooth/bt_battery.sh;
        };
        serpantinum = pkgs.callPackage "${inputs.serpantinum}/nix/package.nix" {
          quickshell = quickshellPatched;
        };
        serpantinumBluetoothPatched = serpantinum.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            substituteInPlace $out/share/serpantinum/quickshell/bar/modules/system/BtWidget.qml \
              --replace-fail 'moduleActive && !isDesktop && sysLayout.implicitWidth > 0' \
                             'moduleActive && sysLayout.implicitWidth > 0' \
              --replace-fail 'showLayout && moduleActive && !isDesktop' \
                             'showLayout && moduleActive' \
              --replace-fail 'isDesktop ? 0 : implicitWidth' 'implicitWidth'

            # The upstream script stops Serpantinum's graphical target before
            # asking the compositor to exit, killing itself before logout.
            ${pkgs.python3}/bin/python3 ${./serpantinum-system/patch_exit.py} \
              $out/share/serpantinum/scripts/system/exit.sh

            ${pkgs.python3}/bin/python3 ${./serpantinum-bluetooth/patch_network_popup.py} \
              $out/share/serpantinum/quickshell/network/NetworkPopup.qml
            install -Dm755 ${btBattery}/bin/serpantinum-bt-battery \
              $out/share/serpantinum/quickshell/network/bt_battery.sh

            install -Dm644 ${./serpantinum-ups/UpsSettings.qml} \
              $out/share/serpantinum/quickshell/guide/UpsSettings.qml
            install -Dm644 ${./serpantinum-ups/UpsTab.qml} \
              $out/share/serpantinum/quickshell/guide/UpsTab.qml
            install -Dm755 ${upsStatus}/bin/ups_status.sh \
              $out/share/serpantinum/scripts/system/ups_status.sh
          '';
        });
        serpantinumWorldClockPatched = inputs.world-clock.lib.patchSerpantinum {
          inherit pkgs;
          serpantinum = serpantinumBluetoothPatched;
        };
        serpantinumPatched = serpantinumWorldClockPatched.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            ${pkgs.python3}/bin/python3 ${./serpantinum-ups/patch_guide_popup.py} \
              $out/share/serpantinum/quickshell/guide/GuidePopup.qml
            ${pkgs.python3}/bin/python3 ${./serpantinum-ups/patch_translations.py} \
              $out/share/serpantinum/assets/languages/en.json
            ${pkgs.python3}/bin/python3 ${./serpantinum-ups/patch_mango.py} \
              $out/share/serpantinum
            ${pkgs.python3}/bin/python3 ${./serpantinum-workspaces/patch_top_bar.py} \
              $out/share/serpantinum/quickshell/bar/modules/WorkspacesWidget.qml \
              $out/share/serpantinum/quickshell/bar/TopBar.qml
          '';
        });
      in
      {
        imports = [
          (import "${inputs.serpantinum}/nix/hm-module.nix" {
            self = inputs.serpantinum;
          })
        ];
        programs.serpantinum.enable = true;
        programs.serpantinum.package = serpantinumPatched;
        programs.serpantinum.systemd.enable = true;
        programs.serpantinum.settings = {
          bar.modules.left = [
            "left"
            "workspaces"
          ];
          launcher.terminalCommand = "ghostty -e";
          ups = {
            shutdownBatteryLevel = 50;
            shutdownMinutes = 5;
          };
        };

      };
  };
}
