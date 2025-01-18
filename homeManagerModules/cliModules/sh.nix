{ config, pkgs, ... }:
{
  programs.bash = {
    enable = false;
  };

  programs.fish = {
    enable = true;
    plugins = [
      {
        name = "tide";
        src = pkgs.fishPlugins.tide.src;
      }
      {
        name = "zoxide";
        src = pkgs.fishPlugins.z.src;
      }
    ];
  };

}
