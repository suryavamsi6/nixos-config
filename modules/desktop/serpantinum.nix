# Official Serpantinum NixOS/Home Manager integration.
{ lib, ... }:
{
  options.flake.modules.nixos.serpantinum = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { inputs, ... }:
      {
        # Use the upstream flake's `nixosModules.default`, not the raw
        # `nix/nixos-module.nix`. Since 2.3.x the NixOS module calls
        # `programs.ski.enable`, and that option only exists because upstream's
        # default module also imports "${ski}/nix/module.nix". Importing the
        # bare file leaves `programs.ski` undefined and evaluation fails.
        imports = [ inputs.serpantinum.nixosModules.default ];
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
            # The upstream script stops Serpantinum's graphical target before
            # asking the compositor to exit, killing itself before logout.
            ${pkgs.python3}/bin/python3 ${./serpantinum-system/patch_exit.py} \
              $out/share/serpantinum/scripts/system/exit.sh

            ${pkgs.python3}/bin/python3 ${./serpantinum-bluetooth/patch_network_popup.py} \
              $out/share/serpantinum/quickshell/network/NetworkPopup.qml
            install -Dm755 ${btBattery}/bin/serpantinum-bt-battery \
              $out/share/serpantinum/quickshell/network/bt_battery.sh

            # 2.3.x collapses the Bluetooth bar pill on machines without a
            # battery. Drop those gates so the pill shows on this desktop.
            ${pkgs.python3}/bin/python3 ${./serpantinum-bluetooth/patch_bt_face.py} \
              $out/share/serpantinum/quickshell/bar/faces/bt/BtFace.qml

            # Read-only telemetry panel, Loader-ed by UpsTab.qml. The policy
            # editor that used to live here is gone: shutdown thresholds are
            # static in modules/hardware/apcupsd.nix.
            install -Dm644 ${./serpantinum-ups/UpsSettings.qml} \
              $out/share/serpantinum/quickshell/guide/UpsSettings.qml
            install -Dm644 ${./serpantinum-ups/UpsTab.qml} \
              $out/share/serpantinum/quickshell/guide/UpsTab.qml
            install -Dm755 ${upsStatus}/bin/ups_status.sh \
              $out/share/serpantinum/scripts/system/ups_status.sh
          '';
        });
        serpantinumPatched = serpantinumBluetoothPatched.overrideAttrs (old: {
          postInstall = (old.postInstall or "")
            + ''
              ${pkgs.python3}/bin/python3 ${./serpantinum-ups/patch_guide_popup.py} \
                $out/share/serpantinum/quickshell/guide/GuidePopup.qml
              ${pkgs.python3}/bin/python3 ${./serpantinum-ups/patch_translations.py} \
                $out/share/serpantinum/assets/languages/en.json
              ${pkgs.python3}/bin/python3 ${./serpantinum-workspaces/patch_top_bar.py} \
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
        config = {
          programs.serpantinum.enable = true;
          programs.serpantinum.package = serpantinumPatched;
          programs.serpantinum.systemd.enable = true;
          programs.serpantinum.settings = {
            bar.modules.left = [
              "left"
              "workspaces"
            ];
            launcher.terminalCommand = "ghostty -e";
            # Upstream's workspace face system replaced the old hand-patched
            # pill geometry. "numbers" renders the workspace digit in a pill;
            # "pills" (the default) is the dot style, "pacman" the variant.
            # Typed enum in the module's nix/settings-options.nix.
            bar.workspacesStyle = "numbers";
            # The old patch hid unoccupied workspaces unconditionally. Upstream
            # 2.3.x gates that behind this setting and defaults it to false, so
            # setting it keeps the bar showing only the current + occupied ones.
            bar.hideEmptyWorkspaces = true;
          };
        };
      };
  };
}
