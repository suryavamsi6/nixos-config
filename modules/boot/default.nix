# Boot — Limine + Windows dual-boot chainload
#
# Secure Boot: leave enabled only if you will enroll Limine keys (sbctl)
# after install. For the first dual-boot bring-up, disable Secure Boot in
# firmware, or temporarily set secureBoot.enable = false.
{ lib, ... }:
{
  options.flake.modules.nixos.boot = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      boot.loader.limine.enable = true;
      boot.loader.limine.secureBoot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.efi.efiSysMountPoint = "/boot";
      boot.loader.limine.extraEntries = ''
        /Windows Boot Manager
          protocol: chainload
          path: boot():///EFI/Microsoft/Boot/bootmgfw.efi
      '';
    };
  };
}
