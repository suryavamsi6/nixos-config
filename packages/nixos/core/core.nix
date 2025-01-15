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

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        ControllerMode = "bredr";
        FastConnectable = true;
      };

    };
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
  services.desktopManager.plasma6.enable = true;

  networking.networkmanager.enable = true;

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub = {
    enable = true;
    devices = [ "nodev" ];
    efiSupport = true;
    useOSProber = true;
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };
}
