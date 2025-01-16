{ pkgs, inputs, ... }:
{

  environment.systemPackages = with pkgs; [
    kanshi
    xorg.xrdb
    walker
    hyprpolkitagent
    xdg-desktop-portal-hyprland
    hyprpaper
    hyprcursor
    hyprlock
    hypridle
    hyprutils
    hyprlang
    hyprland-qtutils
    nautilus
    nautilus-open-any-terminal
  ];

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    package = inputs.hyprland.packages."${pkgs.system}".hyprland;
  };

}
