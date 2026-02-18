# MacBook M4 Air - home-manager configuration
{
  pkgs,
  lib,
  ...
}:
{
  home.username = "suryavamsi";
  home.homeDirectory = lib.mkForce "/Users/suryavamsi";

  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  # Home packages - add your packages here
  home.packages = with pkgs; [
    # CLI tools
    # git
    # htop
    # tmux
  ];
}
