# Work tools (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.work = lib.mkOption {
    type = lib.types.deferredModule;
    default = { pkgs, ... }: {
      home.packages = with pkgs; [
        ntfs3g
        zoom-us
        citrix_workspace
      ];
    };
  };
}
