# Hardware configuration for hyprland host — wraps auto-generated config as deferredModule
#
# IMPORTANT: After partitioning a fresh dual-boot install, replace every
# /dev/disk/by-uuid/... value below with the UUIDs from:
#   lsblk -f
#   blkid
# Or paste the relevant fileSystems / swapDevices from:
#   nixos-generate-config --root /mnt --show-hardware-config
#
# Expected layout (matches this module + README reinstall):
#   - NixOS ESP (vfat, label NIXBOOT) at /boot on nvme0n1p1 (Samsung)
#   - Windows ESP left on nvme1n1p1; Limine chainloads it by GPT GUID
#   - one ext4 root (label nixos) on nvme0n1p2 — /home /nix are directories
{ lib, ... }:
{
  options.flake.modules.nixos.hardwareHyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        config,
        lib,
        pkgs,
        modulesPath,
        ...
      }:
      {
        imports = [
          (modulesPath + "/installer/scan/not-detected.nix")
        ];

        boot.initrd.availableKernelModules = [
          "nvme"
          "xhci_pci"
          "ahci"
          "usb_storage"
          "usbhid"
          "sd_mod"
        ];
        boot.initrd.kernelModules = [ ];
        boot.kernelModules = [
          "kvm-amd"
          "r8125"
        ];
        # RTL8125 2.5G (10EC:8125) is bound to in-tree r8169, which often
        # underperforms Realtek's Windows driver. Use the vendor module.
        boot.extraModulePackages = [ config.boot.kernelPackages.r8125 ];
        boot.blacklistedKernelModules = [ "r8169" ];
        boot.extraModprobeConfig = ''
          options r8125 aspm=0 eee=0
        '';

        # Ext4 root — REPLACE UUID after wipe/reinstall (or keep by-label).
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          options = [ "noatime" ];
        };

        # NixOS EFI System Partition (2G on the Samsung SSD). Do not reuse
        # the 100M Windows ESP — Limine copies kernels here.
        fileSystems."/boot" = {
          device = "/dev/disk/by-label/NIXBOOT";
          fsType = "vfat";
          options = [
            "fmask=0022"
            "dmask=0022"
          ];
          neededForBoot = true;
        };

        # Create /swapfile on the ext4 root during install (see README)
        swapDevices = [ { device = "/swapfile"; } ];

        networking.useDHCP = lib.mkDefault true;

        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      };
  };
}
