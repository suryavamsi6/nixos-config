{ pkgs, ... }:
{
  imports = [
    ./gameModules/steam.nix
    ./systemModules/hyprland.nix
  ];
}
