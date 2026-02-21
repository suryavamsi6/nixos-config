# Social apps (NixOS)
{ lib, ... }:
{
  options.flake.modules.nixos.social = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        element-desktop
        discord
      ];
    };
  };
}
