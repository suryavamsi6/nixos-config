{ pkgs, inputs, ... }:
{

  environment.systemPackages = with pkgs; [
    kanshi
    xorg.xrdb
    walker
  ];

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    package = inputs.hyprland.packages."${pkgs.system}".hyprland;
  };

}
