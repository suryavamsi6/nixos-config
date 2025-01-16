{
  config,
  pkgs,
  ...
}:

{

  imports = [
    ./../../homeManagerModules/default.nix
    ./../../packages/home-manager/default.nix
  ];

  home.username = "surya";
  home.homeDirectory = "/home/surya";

  home.stateVersion = "24.11";



  programs.home-manager.enable = true;
}
