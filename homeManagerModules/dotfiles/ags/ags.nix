{ pkgs, ... }:
{
  home.file.".config/ags/yami" = {
    text = ./my-shell;
  };
}
