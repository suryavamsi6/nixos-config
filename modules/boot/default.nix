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
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.efi.efiSysMountPoint = "/boot";

      # Limine 12+: UEFI Windows must use protocol `efi` (not `chainload`)
      # and path `boot():/...` (one slash after the colon).
      boot.loader.limine.extraEntries = ''
        /Windows 11
          protocol: efi
          path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
      '';

      # NixOS always writes default_entry: 2 (latest NixOS gen). Override after
      # install so Limine selects Windows by entry name (stable across gens).
      boot.loader.limine.extraInstallCommands = ''
        sed -i 's/^default_entry:.*/default_entry: Windows 11/' /boot/limine/limine.conf
      '';
    };
  };
}
