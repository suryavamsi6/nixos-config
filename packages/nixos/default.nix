{ pkgs, inputs, ... }:
{

  imports = [
    ./windowManager/hyprland.nix
    ./system/system.nix
    ./game/game.nix
    ./core/core.nix
  ];

  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.caskaydia-cove
  ];

}
