{
  pkgs,
  config,
  lib,
  ...
}:
let
  tuigreet = "${pkgs.greetd.tuigreet}/bin/tuigreet";
  baseSessionsDir = "${config.services.displayManager.sessionData.desktops}";
  xSessions = "${baseSessionsDir}/share/xsessions";
  waylandSessions = "${baseSessionsDir}/share/wayland-sessions";
  tuigreetOptions = [
    "--remember"
    "--remember-session"
    "--sessions ${waylandSessions}:${xSessions}"
    "--time"
    "--cmd Hyprland"
  ];
  flags = lib.concatStringsSep " " tuigreetOptions;
in
{
  options = {
    gnome.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable/Disable Gnome";
    };
  };
  config = {
    hardware.graphics = {
      enable = true;
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services.printing.enable = true;

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${tuigreet} ${flags}";
          user = "greeter";
        };
      };
    };
    services.xserver.enable = true;

    #  services.displayManager.sddm.wayland.enable = true;

    #  services.displayManager.sddm.enable = true;
    services.desktopManager.gnome.enable = config.gnome.enable;

    networking.networkmanager.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot = {
      enable = true;
      configurationLimit = 1;
      consoleMode = "max";
    };
    # boot.loader.grub = {
    #   enable = true;
    #   devices = [ "nodev" ];
    #   efiSupport = true;
    #   useOSProber = true;
    #   theme = "${pkgs.catppuccin-grub}";
    # };

    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };

}
