{ pkgs, inputs, ... }:
{

  imports = [
    ./core/core.nix
    ./windowManager/hyprland.nix
    ./system/system.nix
  ];

  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.caskaydia-cove
  ];

}
