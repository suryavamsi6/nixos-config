{ pkgs, ... }:
{
  home.file.".config/wallpapers/leaf.png" = {
    source = ./leaf.png;
  };
}
