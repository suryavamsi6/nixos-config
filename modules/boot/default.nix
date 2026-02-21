# Boot — Bootloader, systemd-boot (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.boot = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot = {
        enable = true;
        configurationLimit = 1;
        consoleMode = "max";
      };
    };
  };
}
