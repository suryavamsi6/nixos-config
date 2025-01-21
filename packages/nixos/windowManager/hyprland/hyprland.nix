{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
{
  options = {
    hyprland.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable/Disable Hyprland";
    };
  };
  config = lib.mkIf config.hyprland.enable {
    environment.systemPackages = with pkgs; [
      kanshi
      libnotify
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
      aquamarine
    ];

    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
    };

  };
}
