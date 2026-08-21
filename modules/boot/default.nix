# Boot — Limine + Windows dual-boot chainload
#
# Secure Boot: sbctl keys live in /var/lib/sbctl. Enroll with
# `sudo sbctl enroll-keys --microsoft --firmware-builtin` while firmware
# is in Setup Mode (Windows needs the Microsoft keys), then rebuild.
{ lib, ... }:
{
  options.flake.modules.nixos.boot = lib.mkOption {
    type = lib.types.deferredModule;
    default = { ... }: {
      boot.loader.limine.enable = true;
      boot.loader.limine.secureBoot.enable = true;
      # Kernels live on the NixOS ESP (~1G on the Samsung SSD), not the
      # 100M Windows ESP. ~43M per generation.
      boot.loader.limine.maxGenerations = 10;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.efi.efiSysMountPoint = "/boot";

      # extraConfig is prepended. Nixpkgs then writes default_entry: 2 (the
      # NixOS folder once Windows is entry 1). Limine keeps the *first*
      # default_entry, so put 3 here: 1 Windows, 2 folder, 3 latest generation.
      boot.loader.limine.extraConfig = ''
        default_entry: 3

        /Windows 11
          protocol: efi
          path: guid(e60abccf-1a4b-4973-a37c-e20b992a9bc3):/EFI/Microsoft/Boot/bootmgfw.efi
      '';
    };
  };
}
