{ inputs, pkgs, ... }:
{
  # add the home manager module
  imports = [ inputs.ags.homeManagerModules.default ];

  programs.ags = {
    enable = true;

    # symlink to ~/.config/ags
    configDir = ../../../homeManagerModules/dotfiles/ags/my-shell;

    # additional packages to add to gjs's runtime
    extraPackages = with pkgs; [
      inputs.ags.packages.${system}.battery
      inputs.ags.packages.${system}.hyprland
      inputs.ags.packages.${system}.mpris
      inputs.ags.packages.${system}.tray
      inputs.ags.packages.${system}.apps
      inputs.ags.packages.${system}.wireplumber
      inputs.ags.packages.${system}.bluetooth
      inputs.ags.packages.${system}.network
      libgtop # ags.packages.${system}.battery
      fzf
    ];
  };
}
