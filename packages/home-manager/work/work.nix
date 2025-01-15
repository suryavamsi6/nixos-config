{ pkgs, ... }:
{
  home.packages = with pkgs; [
    citrix_workspace
  ];
}
