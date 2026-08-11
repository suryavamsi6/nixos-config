# Hyprland window manager — NixOS packages + home-manager Lua config
{ lib, ... }:
{
  # NixOS-level Hyprland packages
  options.flake.modules.nixos.hyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, inputs, ... }:
      {
        environment.systemPackages = with pkgs; [
          libnotify
          xorg.xrdb
          walker
          hyprpolkitagent
          xdg-desktop-portal-hyprland
          hyprpaper
          hyprcursor
          hypridle
          hyprutils
          hyprlang
          hyprshot
          hyprland-qtutils
          aquamarine
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-ugly
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-base
          libva
        ];

        programs.hyprland = {
          enable = true;
          xwayland.enable = true;
          package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
          portalPackage =
            inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        };
      };
  };

  # Home-manager-level Hyprland Lua config (Hyprland 0.55+)
  options.flake.modules.homeManager.hyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { ... }:
      {
        imports = [
          ./script.nix
        ];

        # Polkit GUI auth prompts (sudo/pkexec from desktop apps)
        services.hyprpolkitagent.enable = true;

        wayland.windowManager.hyprland = {
          enable = true;
          # stateVersion is < 26.05, so default would still be hyprlang
          configType = "lua";
          # NixOS module already installs Hyprland from the flake input
          package = null;
          portalPackage = null;

          extraLuaFiles = {
            # Required by binds.lua; not auto-required on its own
            "vars" = {
              content = ./lua/vars.lua;
              autoLoad = false;
            };
            "monitors" = ./lua/monitors.lua;
            "look" = ./lua/look.lua;
            "input" = ./lua/input.lua;
            "animations" = ./lua/animations.lua;
            "autostart" = ./lua/autostart.lua;
            "binds" = ./lua/binds.lua;
            "rules" = ./lua/rules.lua;
          };
        };
      };
  };
}
