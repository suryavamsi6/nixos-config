# Nvidia GPU config (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.nvidia = lib.mkOption {
    type = lib.types.deferredModule;
    default = { config, pkgs, ... }: {
      boot.kernelModules = [ "nvidia_uvm" ];
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        powerManagement.finegrained = false;
        open = true;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.beta;
      };

      hardware.graphics = {
        enable = true;
        package = pkgs.mesa;
        enable32Bit = true;
        package32 = pkgs.pkgsi686Linux.mesa;
      };

      # MAG 341C is on the RTX 5080 (01:00.0). Raphael iGPU is 17:00.0
      # with no monitor. Aquamarine splits AQ_DRM_DEVICES on `:`, so a
      # pci-0000:01:00.0 by-path is unusable (Hyprland aborts: no allocator).
      services.udev.extraRules = ''
        KERNEL=="card[0-9]", KERNELS=="0000:01:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/nvidia"
      '';
      environment.sessionVariables.AQ_DRM_DEVICES = "/dev/dri/nvidia";
    };
  };
}
