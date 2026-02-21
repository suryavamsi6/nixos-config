# Hardware configuration for gnome host — wraps auto-generated config as deferredModule
{ lib, ... }:
{
  options.flake.modules.nixos.hardwareGnome = lib.mkOption {
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
        { device = "/dev/disk/by-uuid/c3574133-0e99-4332-9da1-1d904b4bde18";
          fsType = "btrfs";
          options = [ "subvol=root" ];
        };

      fileSystems."/home" =
        { device = "/dev/disk/by-uuid/c3574133-0e99-4332-9da1-1d904b4bde18";
          fsType = "btrfs";
          options = [ "subvol=home" ];
        };

      fileSystems."/nix" =
        { device = "/dev/disk/by-uuid/c3574133-0e99-4332-9da1-1d904b4bde18";
          fsType = "btrfs";
          options = [ "subvol=nix" ];
        };

      fileSystems."/boot" =
        { device = "/dev/disk/by-uuid/12CE-A600";
          fsType = "vfat";
          options = [ "fmask=0022" "dmask=0022" ];
        };

      swapDevices = [ { device = "/swap/swapfile"; } ];

      networking.useDHCP = lib.mkDefault true;

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
  };
}
