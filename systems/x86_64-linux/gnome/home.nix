{
  config,
  pkgs,
  ...
}:

{

  imports = [
    ./../../../modules/home/default.nix
    ./../../../packages/home/default.nix
  ];

  home.username = "surya";
  home.homeDirectory = "/home/surya";

  home.stateVersion = "24.11";

  hyprland-config1.enable = false;

  programs.home-manager.enable = true;
}
