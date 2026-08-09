# Hardware configuration for hyprland host — wraps auto-generated config as deferredModule
#
# IMPORTANT: After partitioning a fresh dual-boot install, replace every
# /dev/disk/by-uuid/... value below with the UUIDs from:
#   lsblk -f
#   blkid
# Or paste the relevant fileSystems / swapDevices from:
#   nixos-generate-config --root /mnt --show-hardware-config
#
# Expected layout (matches this module):
#   - shared Windows EFI (vfat) mounted at /boot
#   - one btrfs partition with subvols: @ @home @nix @log @swap
{ lib, ... }:
{
  options.flake.modules.nixos.hardwareHyprland = lib.mkOption {
    type = lib.types.deferredModule;
    default = { config, lib, pkgs, modulesPath, ... }: {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

      boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      # Btrfs root UUID — REPLACE after install
      fileSystems."/" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@" "compress=zstd" "noatime" ];
        };

      fileSystems."/home" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@home" "compress=zstd" "noatime" ];
        };

      fileSystems."/nix" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@nix" "compress=zstd" "noatime" ];
        };

      fileSystems."/var/log" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@log" "compress=zstd" "noatime" ];
        };

      fileSystems."/swap" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@swap" "noatime" ];
        };

      # Shared Windows EFI System Partition — REPLACE FAT UUID after install
      fileSystems."/boot" =
        { device = "/dev/disk/by-uuid/XXXX-XXXX";
          fsType = "vfat";
          options = [ "fmask=0022" "dmask=0022" ];
        };

      # Create the swapfile on the @swap subvolume during install (see README)
      swapDevices = [ { device = "/swap/swapfile"; } ];

      networking.useDHCP = lib.mkDefault true;

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
  };
}