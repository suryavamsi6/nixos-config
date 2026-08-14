# Ant Esports GCB200 GPU-bracket LCD — github:suryavamsi6/gcb200-linux
{ lib, ... }:
{
  options.flake.modules.nixos.gcb200 = lib.mkOption {
    type = lib.types.deferredModule;
    default = { inputs, ... }: {
      imports = [ inputs.gcb200-linux.nixosModules.default ];
      services.gcb200.enable = true;
    };
  };
}
