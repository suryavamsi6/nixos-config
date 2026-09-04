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
          wtype
          ydotool
          (pkgs.callPackage "${inputs.hyprexpose}/default.nix" { })
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
        services.gnome.at-spi2-core.enable = true;

        # PAM for hyprlock (HM only installs the binary)
        programs.hyprlock.enable = true;
      };
  };

  # Home-manager-level Hyprland Lua config (Hyprland 0.55+)
  options.flake.modules.homeManager.hyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, inputs, ... }:
      let
        hyprexpose = pkgs.callPackage "${inputs.hyprexpose}/default.nix" { };
        arcMidnight = pkgs.runCommand "arc-midnight-cursors" { } ''
          mkdir -p $out/share/icons
          ln -s ${pkgs.fetchzip {
            url = "https://github.com/yeyushengfan258/ArcMidnight-Cursors/archive/refs/heads/main.zip";
            hash = "sha256-VgOpt0rukW0+rSkLFoF9O0xO/qgwieAchAev1vjaqPE=";
          }}/dist $out/share/icons/ArcMidnight-Cursors
        '';
      in
      {
        home.packages = [ hyprexpose arcMidnight ];
        home.pointerCursor = {
          enable = true;
          gtk.enable = true;
          x11.enable = true;
          package = arcMidnight;
          name = "ArcMidnight-Cursors";
          size = 24;
        };
        systemd.user.services.ydotoold = {
          Unit = {
            Description = "ydotool input daemon";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.ydotool}/bin/ydotoold";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
        systemd.user.services.hyprexpose = {
          Unit = {
            Description = "Workspace overview overlay";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe hyprexpose} --allow-mouse";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # Polkit GUI auth prompts (sudo/pkexec from desktop apps)
        services.hyprpolkitagent.enable = true;


        services.hypridle = {
          enable = true;
          settings = {
            general = {
              lock_cmd = "serpantinum lock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
            };
            listener = [
              {
                timeout = 120;
                on-timeout = "${lib.getExe pkgs.brightnessctl} -s set 10%";
                on-resume = "${lib.getExe pkgs.brightnessctl} -r";
              }
              {
                timeout = 180;
                on-timeout = "loginctl lock-session";
              }
              {
                timeout = 360;
                on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
                on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
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
          plugins = [ ];
          # Citrix CLStore needs gnome-keyring Secret Service. PAM unlocks it
          # at greetd login; XDG autostart keeps the daemon up for the session.
          systemd.enableXdgAutostart = true;

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
