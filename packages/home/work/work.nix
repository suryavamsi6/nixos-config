{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ntfs3g
    citrix_workspace
  ];

}
