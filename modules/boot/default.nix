# Boot — Bootloader
{ lib, ... }:
{
  options.flake.modules.nixos.boot = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      boot.loader.limine.enable = true;
      boot.loader.limine.secureBoot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.limine.extraEntries = ''
        /Windows Boot Manager
          protocol: chainload
          path: boot():///EFI/Microsoft/Boot/bootmgfw.efi
      '';
    };
  };
}
