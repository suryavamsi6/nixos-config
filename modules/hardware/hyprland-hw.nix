# Hardware configuration for hyprland host — wraps auto-generated config as deferredModule
#
# IMPORTANT: After partitioning a fresh dual-boot install, replace every
# /dev/disk/by-uuid/... value below with the UUIDs from:
#   lsblk -f
#   blkid
# Or paste the relevant fileSystems / swapDevices from:
#   nixos-generate-config --root /mnt --show-hardware-config
#
# Match disks by MODEL, not nvmeN (names swap). This machine:
#   - Samsung 980 PRO 1TB — NixOS ESP (~1G vfat) + ext4 root + swap
#   - WD SN850X 2TB — Windows 11; Limine chainloads its ESP by GPT GUID
# Currently Samsung is nvme1n1 and WD is nvme0n1.
{ lib, ... }:
{
  options.flake.modules.nixos.hardwareHyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      {
        config,
        lib,
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
          "r8169"
        ];
        # RTL8125 2.5G: use the maintained in-tree driver for standard
        # kernel reset and power-management handling across reboots.

        fileSystems."/" = {
          device = "/dev/disk/by-uuid/8e68c4ac-6bc7-4fa3-b43e-0cabc31931cf";
          fsType = "ext4";
          options = [ "noatime" ];
        };

        # NixOS EFI System Partition (~1G on the Samsung SSD). Do not reuse
        # the 100M Windows ESP — Limine copies kernels here.
        fileSystems."/boot" = {
          device = "/dev/disk/by-uuid/EC21-2EC2";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
          neededForBoot = true;
        };

        swapDevices = [ { device = "/dev/disk/by-uuid/6d00e2b3-74e5-4f10-aafa-3fda71eaa7e2"; } ];

        services.fstrim.enable = true;

        networking.useDHCP = lib.mkDefault true;

        nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
        hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      };
  };
}
