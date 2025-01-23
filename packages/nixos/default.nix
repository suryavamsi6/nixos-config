{ pkgs, inputs, ... }:

{

  imports = [
    ./windowManager/hyprland/hyprland.nix
    ./system/system.nix
    ./game/game.nix
    ./core/core.nix
    ./social/social.nix
  ];

  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.caskaydia-cove
  ];


}
