# CoolerControl fan control for the MSI X670E's Nuvoton NCT6687-R.
# X670/B650-era MSI boards use the driver's default fan-register mapping.
{ lib, ... }:
{
  options.flake.modules.nixos.coolercontrol = lib.mkOption {
    type = lib.types.deferredModule;
    default = { config, ... }:
    {
      programs.coolercontrol.enable = true;

      boot.extraModulePackages = [ config.boot.kernelPackages.nct6687d ];
      boot.kernelModules = [ "nct6687" ];
    };
  };
}
