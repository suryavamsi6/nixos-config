# Locale — shared locale and timezone config for all NixOS hosts
{ lib, ... }:
{
  options.flake.modules.nixos.locale = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      time.timeZone = "Asia/Kolkata";

      i18n.defaultLocale = "en_US.UTF-8";
      i18n.extraLocaleSettings = {
        LC_ADDRESS = "en_US.UTF-8";
        LC_IDENTIFICATION = "en_US.UTF-8";
        LC_MEASUREMENT = "en_US.UTF-8";
        LC_MONETARY = "en_US.UTF-8";
        LC_NAME = "en_US.UTF-8";
        LC_NUMERIC = "en_US.UTF-8";
        LC_PAPER = "en_US.UTF-8";
        LC_TELEPHONE = "en_US.UTF-8";
        LC_TIME = "en_US.UTF-8";
      };

      services.xserver.xkb = {
        layout = "us";
        variant = "";
      };
    };
  };
}
