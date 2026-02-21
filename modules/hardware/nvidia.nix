# Nvidia GPU config (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.nvidia = lib.mkOption {
    type = lib.types.deferredModule;
    default = { config, pkgs, ... }: {
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
    };
  };
}
