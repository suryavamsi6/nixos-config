{config, pkgs, ...} :
{
  programs.bash = {
    enable = false;
  };

  programs.fish = {
    enable = true;
  };

}