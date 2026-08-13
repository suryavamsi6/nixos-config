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
          xrdb
          hyprpolkitagent
          xdg-desktop-portal-hyprland
          xdg-desktop-portal-gtk
          hyprcursor
          hypridle
          hyprutils
          hyprlang
          hyprshot
          hyprland-qtutils
          hyprshutdown
          aquamarine
          wl-clipboard
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

        # PAM for hyprlock (HM only installs the binary)
        programs.hyprlock.enable = true;
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

        services.hypridle = {
          enable = true;
          settings = {
            general = {
              lock_cmd = "bash ~/.config/hypr/scripts/lock.sh";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch dpms on";
            };
            listener = [
              {
                timeout = 120;
                on-timeout = "brightnessctl -s set 10%";
                on-resume = "brightnessctl -r";
              }
              {
                timeout = 180;
                on-timeout = "loginctl lock-session";
              }
              {
                timeout = 360;
                on-timeout = "hyprctl dispatch dpms off";
                on-resume = "hyprctl dispatch dpms on";
              }
            ];
          };
        };

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
