# Greetd — Login greeter (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.greetd = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, config, lib, ... }:
    let
      tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
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

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };

      services.printing.enable = true;

      programs.appimage = {
        enable = true;
        binfmt = true;
      };
    };
  };
}
