{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ntfs3g
    wine
    citrix_workspace
  ];

}
