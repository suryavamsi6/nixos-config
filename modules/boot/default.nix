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
      boot.loader.limine.secureBoot.enable = false;
      boot.loader.limine.maxGenerations = 5;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.efi.efiSysMountPoint = "/boot";

      # Windows after NixOS gens (extraEntries appends). NixOS stays default.
      # Limine 12+: UEFI Windows must use protocol `efi` (not `chainload`)
      # and path `boot():/...` (one slash after the colon).
      boot.loader.limine.extraEntries = ''
        /Windows 11
          protocol: efi
          path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
      '';
    };
  };
}
