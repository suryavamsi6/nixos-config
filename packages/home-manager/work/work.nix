{ pkgs, ... }:
{
  home.packages = with pkgs; [
    citrix_workspace
    ntfs3g
    wine
  ];
}
