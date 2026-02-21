# Hardware configuration for hyprland host — wraps auto-generated config as deferredModule
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

      fileSystems."/" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@" ];
        };

      fileSystems."/home" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@home" ];
        };

      fileSystems."/nix" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@nix" ];
        };

      fileSystems."/var/log" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@log" ];
        };

      fileSystems."/swap" =
        { device = "/dev/disk/by-uuid/a9bd7459-3b7f-484d-ac84-059612491c5d";
          fsType = "btrfs";
          options = [ "subvol=@swap" ];
        };

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
  };
}