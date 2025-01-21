{
  config,
  lib,
  pkgs,
  ...
}:
{

  home.file.".config/kitty/kitty.conf" = {
    force = true;
    text = ''
      shell fish
    '';
  };

}
