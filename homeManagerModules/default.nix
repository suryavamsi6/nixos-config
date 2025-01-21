{ pkgs, ... }:
{
  imports = [
    ./cliModules/kitty.nix
    ./cliModules/sh.nix
    ./dotfiles/hyprland/hyprland.nix
    ./dotfiles/hyprpanel/hyprpanel.nix
    ./systemModules/walker.nix
    #    ./systemModules/kanshi.nix
  ];
}
