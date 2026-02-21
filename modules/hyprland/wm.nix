# Hyprland window manager — NixOS packages + home-manager dotfiles
{ lib, ... }:
let
  # Data files for hyprland sub-configs (kept as importable attribute sets)
  animationsData = import ./animations.nix;
  autostartData = import ./autostart.nix;
  keybindsData = import ./keybinds.nix;
  defaultAppsData = import ./defaultApps.nix;
in
{
  # NixOS-level Hyprland packages
  options.flake.modules.nixos.hyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, inputs, ... }: {
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
        gst_all_1.gst-vaapi
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

  # Home-manager-level Hyprland dotfiles
  options.flake.modules.homeManager.hyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      imports = [
        ./script.nix
      ];

      wayland.windowManager.hyprland = {
        enable = true;
        extraConfig = ''
         plugin = ${pkgs.hyprlandPlugins.hyprexpo}/lib/libhyprexpo.so
        '';
        settings =
          (autostartData { inherit pkgs; })
          // (keybindsData { inherit pkgs; })
          // (defaultAppsData { inherit pkgs; })
          // (animationsData { inherit pkgs; })
          // {

            "$mainMod" = "SUPER";

            monitor = [
              "HDMI-A-2, highres,3440x1440@175, 1,bitdepth,10,cm,hdr,sdrbrightness, 1.2, sdrsaturation, 0.98"
            ];

            env = [
              "XCURSOR_SIZE = 24"
              "HYPRCURSOR_SIZE = 24"
            ];

            cursor = {
              no_hardware_cursors = true;
            };

            general = {
              gaps_in = 5;
              gaps_out = 20;
              border_size = 2;

              "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
              "col.inactive_border" = "rgba(595959aa)";

              resize_on_border = false;
              allow_tearing = false;
              layout = "master";
            };

            decoration = {
              rounding = 16;
              active_opacity = 0.95;
              inactive_opacity = 0.9;
              fullscreen_opacity = 0.95;

              dim_inactive = false;
              dim_strength = 0.05;

              blur = {
                enabled = true;
                size = 5;
                passes = 4;
                new_optimizations = true;
                xray = true;
                ignore_opacity = true;
              };

              shadow = {
                enabled = true;
                range = 50;
                render_power = 4;
                color = "0x99161925";
                color_inactive = "0x55161925";
                ignore_window = true;
              };
            };

            master = {
              new_status = "master";
              orientation = "center";
              mfact = 0.34;
            };

            misc = {
              force_default_wallpaper = -1;
              disable_hyprland_logo = false;
            };

            xwayland = {
              force_zero_scaling = true;
            };

            input = {
              kb_layout = "us";
              kb_variant = "";
              kb_model = "";
              kb_options = "";
              kb_rules = "";

              follow_mouse = 1;
              sensitivity = 0;
              accel_profile = "flat";
              touchpad = {
                natural_scroll = false;
              };
            };

            device = {
              name = "epic-mouse-v1";
              sensitivity = -0.5;
            };

            windowrule = [
              "suppress_event maximize"
            ];

            plugin = {
              hyprexpo = {
                columns = 3;
                gap_size = 5;
                bg_col = "rgb(111111)";
                workspace_method = "center current ";

                enable_gesture = true;
                gesture_fingers = 3;
                gesture_distance = 300;
                gesture_positive = true;
              };
            };

          };
      };
    };
  };
}
