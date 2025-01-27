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
      playerctl
    ];

    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
      # set the flake package
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      # make sure to also set the portal package, so that they are in sync
      portalPackage =
        inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    };

  };
}
