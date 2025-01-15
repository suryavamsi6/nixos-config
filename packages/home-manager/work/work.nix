{ pkgs, ... }:
{
  home-manager.packages = with pkgs; [
    citrix_workspace
  ];
}
