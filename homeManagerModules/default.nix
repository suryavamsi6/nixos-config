{ pkgs, ... }:
{
  imports = [
    ./cliModules/kitty.nix
    ./cliModules/sh.nix
    ./dotfiles/hyprland/hyprland.nix
    ./dotfiles/hyprpanel/hyprpanel.nix
#    ./systemModules/kanshi.nix
  ];
}
