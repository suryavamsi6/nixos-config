# AGS widgets + packages (home-manager)
{ lib, ... }:
{
  options.flake.modules.homeManager.ags = lib.mkOption {
    type = lib.types.deferredModule;
    default = { inputs, pkgs, system, ... }: {
      imports = [ inputs.ags.homeManagerModules.default ];

      programs.ags = {
        enable = true;
        extraPackages = with pkgs; [
          inputs.ags.packages.${system}.battery
          inputs.ags.packages.${system}.hyprland
          inputs.ags.packages.${system}.mpris
          inputs.ags.packages.${system}.tray
          inputs.ags.packages.${system}.apps
          inputs.ags.packages.${system}.wireplumber
          inputs.ags.packages.${system}.bluetooth
          inputs.ags.packages.${system}.network
          libgtop
          fzf
        ];
      };

      home.file.".config/ags/yami.js" = {
        source = ./ags-config;
      };
    };
  };
}
